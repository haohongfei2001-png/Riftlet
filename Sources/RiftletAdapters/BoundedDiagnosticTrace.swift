import Foundation
import CryptoKit

/// Opt-in local diagnostics only. Recent events and recent failures have separate
/// bounded windows, so routine capture polling cannot erase a later refusal or
/// exhaust a process-lifetime event allowance. It never changes input authority.
public final class BoundedDiagnosticTrace: @unchecked Sendable {
    private let enabled: Bool
    private let directory: URL?
    private let emitStandardError: Bool
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "com.riftlet.local-diagnostic-trace", qos: .utility)
    private var recent: [Data] = []
    private var failures: [Data] = []
    private var sequence: UInt64 = 0
    private var stderrCount = 0
    private var flushScheduled = false
    private let sessionDigest = SHA256.hash(data: Data(UUID().uuidString.utf8))
        .map { String(format: "%02x", $0) }.joined()
    static let recentCapacity = 128
    static let failureCapacity = 32
    static let maximumLineBytes = 4_096
    static let standardErrorCapacity = 2_048
    private static let labelCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.(): ")

    public convenience init(enabled: Bool, directory: URL? = nil) {
        self.init(enabled: enabled, directory: directory, emitStandardError: true)
    }

    init(enabled: Bool, directory: URL?, emitStandardError: Bool) {
        self.enabled = enabled; self.directory = directory
        self.emitStandardError = emitStandardError
        if enabled, let directory { failures = Self.loadPriorFailures(from: directory) }
    }

    /// Callers supply code-owned facts, never page payloads or error descriptions.
    /// Unknown string fields are dropped, local UUIDs are hashed, and page refusal
    /// labels must belong to the exact closed resource allowlist.
    public func record(_ fields: [String: Any], critical: Bool = false) {
        guard enabled else { return }
        var safe = Self.sanitized(fields)
        guard safe["event"] != nil else { return }
        lock.lock()
        sequence &+= 1
        safe["diagnosticSequence"] = sequence
        safe["diagnosticSessionDigest"] = sessionDigest
        safe["critical"] = critical
        guard let encoded = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
              encoded.count + 1 <= Self.maximumLineBytes else { lock.unlock(); return }
        let line = encoded + Data([10])
        recent.append(line)
        if recent.count > Self.recentCapacity { recent.removeFirst() }
        if critical {
            failures.append(line)
            if failures.count > Self.failureCapacity { failures.removeFirst() }
        }
        let emit = emitStandardError && stderrCount < Self.standardErrorCapacity
        if emit { stderrCount += 1 }
        let schedule = directory != nil && !flushScheduled
        if schedule { flushScheduled = true }
        lock.unlock()
        if emit { try? FileHandle.standardError.write(contentsOf: line) }
        if schedule { writer.async { [self] in persistPending() } }
    }

    private func persistPending() {
        while true {
            lock.lock()
            let revision = sequence
            let recentData = recent.reduce(into: Data()) { $0.append($1) }
            let failureData = failures.reduce(into: Data()) { $0.append($1) }
            lock.unlock()
            if let directory {
                do {
                    let manager = FileManager.default
                    try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700])
                    // Reject an observed non-directory. This is a path-based
                    // best-effort check, not protection from concurrent ancestor
                    // replacement. App ownership already protects its private root.
                    let attributes = try manager.attributesOfItem(atPath: directory.path)
                    guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                        throw CocoaError(.fileWriteInvalidFileName)
                    }
                    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                    for (name, data) in [("acceptance-recent.jsonl", recentData),
                                         ("acceptance-failures.jsonl", failureData)] {
                        let file = directory.appendingPathComponent(name)
                        try data.write(to: file, options: .atomic)
                        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                    }
                } catch {
                    // A diagnostic disk failure cannot retry input, affect the
                    // queue, or schedule an unbounded writer/retry backlog.
                }
            }
            lock.lock()
            if revision == sequence { flushScheduled = false; lock.unlock(); return }
            lock.unlock()
        }
    }

    func flushForTesting() { writer.sync {} }

    private static func loadPriorFailures(from directory: URL) -> [Data] {
        let file = directory.appendingPathComponent("acceptance-failures.jsonl")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= failureCapacity * maximumLineBytes,
              let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: failureCapacity * maximumLineBytes + 1),
              bytes.count <= failureCapacity * maximumLineBytes else { return [] }
        return bytes.split(separator: 10).suffix(failureCapacity).compactMap { line in
            guard line.count < maximumLineBytes,
                  let fields = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  fields["critical"] as? Bool == true else { return nil }
            let safe = sanitized(fields)
            guard safe["event"] != nil,
                  let encoded = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
                  encoded.count + 1 <= maximumLineBytes else { return nil }
            return encoded + Data([10])
        }
    }

    private static func sanitized(_ fields: [String: Any]) -> [String: Any] {
        let labels: Set<String> = ["event", "action", "phase", "purpose", "result", "usableResult",
            "publication", "publicationResult", "reason", "refusalReason", "freezeResult", "status",
            "visibility", "visibilityReason", "authorization", "source", "check", "route", "authority",
            "resourceKind"]
        let identifiers: Set<String> = ["requestID", "captureRequestID", "armAttemptID", "hostEpoch", "assetID",
            "operationID", "selectionID", "permissionRequestID", "effectiveCaptureRequestID",
            "effectiveArmAttemptID", "inFlightCaptureRequestID", "inFlightArmAttemptID"]
        let digests = Set(identifiers.map { $0 + "Digest" }).union(["targetDigest", "diagnosticSessionDigest"])
        var result: [String: Any] = [:]
        for (key, value) in fields where key.utf8.count <= 64 {
            if let text = value as? String {
                if identifiers.contains(key), UUID(uuidString: text) != nil {
                    result[key + "Digest"] = SHA256.hash(data: Data(text.lowercased().utf8))
                        .map { String(format: "%02x", $0) }.joined()
                } else if digests.contains(key), text.utf8.count == 64,
                          text.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) {
                    result[key] = text
                } else if key == "resourceRefusalReason", let code = WebPageRejection(rawValue: text),
                          code.isInputResourceRefusal { result[key] = code.rawValue
                } else if key == "error", WebAdapterError.isDiagnosticLabel(text) { result[key] = text
                } else if labels.contains(key), !text.isEmpty, text.utf8.count <= 128,
                          text.unicodeScalars.allSatisfy({ labelCharacters.contains($0) }) {
                    result[key] = text
                }
            } else if let number = value as? NSNumber, number.doubleValue.isFinite {
                result[key] = number
            }
        }
        return result
    }
}
