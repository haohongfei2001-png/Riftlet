import Darwin
import Foundation
import RiftletUI

/// These files describe presentation and archiving only. Opening the queue has
/// separate error handling and never falls back to replacement data.
final class RecoverablePreferences {
    enum Problem: Error, Equatable {
        case malformed, invalidValue, tooLarge, inaccessible, changed
    }

    private let root: URL
    private let defaultLayout: RiftConfiguration
    private var confirmedBytes: [SettingsPreferenceDomain: Data] = [:]
    private(set) var problems: [SettingsPreferenceDomain: Problem] = [:]
    private(set) var recoveryFailure: SettingsPreferenceDomain?
    var recoveryDomains: Set<SettingsPreferenceDomain> { Set(problems.keys) }
    private(set) var layout: RiftConfiguration
    private(set) var lifecycle = LifecycleSettings()
    private static let maxBytes = 1_048_576

    init(root: URL, defaultLayout: RiftConfiguration) {
        self.root = root
        self.defaultLayout = defaultLayout
        layout = defaultLayout
        do { try reloadLayout() } catch { /* reloadLayout keeps the reason. */ }
        do {
            if let bytes = try read(.archive) {
                lifecycle = try Self.decode(LifecycleSettings.self, bytes)
                try lifecycle.validate()
                confirmedBytes[.archive] = bytes
            } else {
                try saveLifecycle(lifecycle)
            }
        } catch {
            lifecycle.archiveAfterSeconds = nil
            problems[.archive] = error as? Problem ?? .inaccessible
        }
    }

    private func file(_ domain: SettingsPreferenceDomain) -> URL {
        root.appendingPathComponent(domain == .layout ? "rift-configuration.json" : "lifecycle-settings.json")
    }

    private func read(_ domain: SettingsPreferenceDomain) throws -> Data? {
        // A failing fileExists also means unreadable. Only ENOENT is a new file.
        let fd = open(file(domain).path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw Problem.inaccessible
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw Problem.inaccessible }
        guard info.st_size <= Self.maxBytes else { throw Problem.tooLarge }
        let data = try handle.read(upToCount: Self.maxBytes + 1) ?? Data()
        guard data.count <= Self.maxBytes else { throw Problem.tooLarge }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ bytes: Data) throws -> T {
        guard (try? JSONSerialization.jsonObject(with: bytes)) is [String: Any] else { throw Problem.malformed }
        do { return try JSONDecoder().decode(type, from: bytes) }
        catch { throw Problem.invalidValue }
    }

    func reloadLayout() throws {
        do {
            if let bytes = try read(.layout) {
                let value = try Self.decode(RiftConfiguration.self, bytes)
                try value.validate()
                layout = value
                confirmedBytes[.layout] = bytes
            } else if confirmedBytes[.layout] == nil, problems[.layout] == nil {
                try saveLayout(defaultLayout)
            } else { throw Problem.changed }
            problems.removeValue(forKey: .layout)
            if recoveryFailure == .layout { recoveryFailure = nil }
        } catch {
            problems[.layout] = error as? Problem ?? .inaccessible
            throw error
        }
    }

    func saveLayout(_ value: RiftConfiguration) throws {
        try value.validate()
        try write(value, previous: layout, domain: .layout)
        layout = value
    }

    func saveLifecycle(_ value: LifecycleSettings) throws {
        try value.validate()
        try write(value, previous: lifecycle, domain: .archive)
        lifecycle = value
    }

    /// Patch only fields the user actually changed. Unknown fields and the
    /// spelling/absence of legacy keys survive a save to this same domain.
    private func write<T: Encodable>(_ value: T, previous: T, domain: SettingsPreferenceDomain) throws {
        if let problem = problems[domain] { throw problem }
        guard try read(domain) == confirmedBytes[domain] else { throw Problem.changed }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        var bytes = try encoder.encode(value)
        if let original = confirmedBytes[domain] {
            guard var object = try JSONSerialization.jsonObject(with: original) as? [String: Any],
                  let before = try JSONSerialization.jsonObject(with: encoder.encode(previous)) as? [String: NSObject],
                  let after = try JSONSerialization.jsonObject(with: bytes) as? [String: NSObject] else { throw Problem.malformed }
            let changedKeys = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
            if changedKeys.isEmpty { return }
            for key in changedKeys { object[key] = after[key] }
            bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        }
        guard bytes.count <= Self.maxBytes else { throw Problem.tooLarge }
        try bytes.write(to: file(domain), options: .atomic)
        confirmedBytes[domain] = bytes
    }

    func restore(_ domain: SettingsPreferenceDomain) throws {
        guard problems[domain] != nil else { return }
        do {
            let url = file(domain)
            var info = stat()
            if lstat(url.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFREG else { throw Problem.inaccessible }
                let backup = url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + ".backup-" + UUID().uuidString)
                // Also preserves oversized documents without loading them into memory.
                try FileManager.default.copyItem(at: url, to: backup)
            } else if errno != ENOENT {
                throw Problem.inaccessible
            }
            let bytes: Data
            switch domain {
            case .layout: bytes = try JSONEncoder().encode(defaultLayout)
            case .archive: bytes = try JSONEncoder().encode(LifecycleSettings())
            }
            try bytes.write(to: url, options: .atomic)
            confirmedBytes[domain] = bytes
            if domain == .layout { layout = defaultLayout } else { lifecycle = LifecycleSettings() }
            problems.removeValue(forKey: domain)
            if recoveryFailure == domain { recoveryFailure = nil }
        } catch {
            recoveryFailure = domain
            throw error
        }
    }
}
