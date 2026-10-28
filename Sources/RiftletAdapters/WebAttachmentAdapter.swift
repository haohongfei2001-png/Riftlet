import Foundation
import CryptoKit
import Darwin
import RiftletCore

public enum WebAdapterMode: Sendable { case disabled, syntheticDevelopment, systemScreenshotCandidate }
public enum WebBridgeAction: String, Codable, Sendable {
    case captureTarget, validate, begin, chunk, commit, observe, discard
}

/// The sole page function is supplied from reviewed source. It must synchronously
/// return a serializable observation, retain no chat text, and check the complete
/// lease in the same execution that commits File/DataTransfer input. `discard`
/// clears only this operation's temporary byte buffer; it never removes attachments.
public struct WebPageProgram: Sendable {
    public let sourceID: String
    public let functionSource: String
    /// Code-owned transport capacity; never negotiated from page JSON. Older
    /// and generic programs retain their 64 KiB default.
    public let maximumChunkBytes: Int
    public init(sourceID: String, functionSource: String, maximumChunkBytes: Int = 64 * 1024) {
        self.sourceID = sourceID; self.functionSource = functionSource
        self.maximumChunkBytes = maximumChunkBytes
    }
}

public struct WebBridgeCommand: Encodable, Sendable {
    public let action: WebBridgeAction
    public let target: TargetLease?
    public let identity: ObservationIdentity?
    public let uploadName: String?
    public let mediaType: String?
    public let byteCount: Int64?
    public let chunkIndex: Int?
    public let chunkBase64: String?
    /// Host diagnostics only, deliberately excluded from the page payload.
    public let captureInvocation: CaptureInvocationContext?

    private enum CodingKeys: String, CodingKey {
        case action, target, identity, uploadName, mediaType, byteCount, chunkIndex, chunkBase64
    }

    init(action: WebBridgeAction, target: TargetLease? = nil, identity: ObservationIdentity? = nil,
         uploadName: String? = nil, mediaType: String? = nil, byteCount: Int64? = nil,
         chunkIndex: Int? = nil, chunkBase64: String? = nil,
         captureInvocation: CaptureInvocationContext? = nil) {
        self.action = action; self.target = target; self.identity = identity
        self.uploadName = uploadName; self.mediaType = mediaType; self.byteCount = byteCount
        self.chunkIndex = chunkIndex; self.chunkBase64 = chunkBase64
        self.captureInvocation = captureInvocation
    }
}

public protocol WebBridgeExecutor: Sendable {
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data
}

public enum WebAdapterError: Error, Equatable, Sendable {
    case disabled, programUnavailable, syntheticAssetsOnly, invalidTarget, invalidRequest
    case invalidPrivateFile, inputInFlight, invalidReply, browserNotFrontmost, nativeExecutionFailed
    case nativeEventFailed(Int32)
    case nativeSelectionChanged, pageRejected(WebPageRejection)
}

/// The explicit screenshot candidate is isolated from ordinary production.
/// Its reviewed start/completion scope is assigned only to registered new
/// operations; historical operations retain their observation-only profiles.
public actor WebAttachmentAdapter: AttachmentAdapter {
    public nonisolated let id: String
    private let mediaDirectory: URL
    private let executor: any WebBridgeExecutor
    private let program: WebPageProgram?
    private let mode: WebAdapterMode
    private let normalizer: ObservationNormalizer
    private let polling: WebObservationPolling
    private let candidateJournal: SystemScreenshotObservationJournal?
    private let candidateAdmission: SystemScreenshotCandidateAdmission?
    private var inputInFlight = false

    public init(mediaDirectory: URL, executor: any WebBridgeExecutor,
                program: WebPageProgram? = nil, mode: WebAdapterMode = .disabled,
                profile: ObservationProfile = .init(adapterID: "chatgpt-web", surface: .webChat,
                                                     profileID: "web-unadmitted-v1"),
                polling: WebObservationPolling = .acceptance,
                candidateJournal: SystemScreenshotObservationJournal? = nil,
                candidateAdmission: SystemScreenshotCandidateAdmission? = nil) {
        id = profile.adapterID; self.mediaDirectory = mediaDirectory.standardizedFileURL
        self.executor = executor; self.program = program; self.mode = mode
        if case .systemScreenshotCandidate = mode {
            normalizer = ObservationNormalizer(profile: profile, developmentScope: .systemScreenshotCandidate)
        } else { normalizer = ObservationNormalizer(profile: profile) }
        self.polling = polling
        self.candidateJournal = candidateJournal
        self.candidateAdmission = candidateAdmission
    }

    public func preflight(asset: ImportedAsset, fileURL: URL) async throws {
        if case .systemScreenshotCandidate = mode {
            try requireEnabled()
            try SystemScreenshotWebCandidate.preflight(asset, fileURL: fileURL, mediaDirectory: mediaDirectory,
                restrictedAdmission: candidateAdmission != nil)
        }
    }

    public func captureTarget() async throws -> TargetLease {
        try await captureTarget(invocation: nil)
    }

    /// Optional diagnostic seam. Ordinary AttachmentAdapter and executor APIs
    /// are unchanged; this performs exactly the same single capture and checks.
    public func captureTargetWithDiagnostics(context: CaptureInvocationContext) async throws -> CapturedTargetDiagnostics {
        let target = try await captureTarget(invocation: context)
        return try CapturedTargetDiagnostics(context: context, target: target)
    }

    private func captureTarget(invocation: CaptureInvocationContext?) async throws -> TargetLease {
        let data = try await perform(.init(action: .captureTarget, captureInvocation: invocation))
        let target = try decode(TargetLease.self, from: data)
        try check(target)
        try checkNewInputScope(target)
        return target
    }

    public func validate(_ target: TargetLease) async throws -> Bool {
        try check(target)
        try checkNewInputScope(target)
        let data = try await perform(.init(action: .validate, target: target))
        let response = try decode(ValidationReply.self, from: data)
        return response.valid && response.target == target
    }

    public func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try requireEnabled()
        try check(request.operation.target)
        try checkNewInputScope(request.operation.target)
        try checkOrigin(request.asset)
        guard request.operation.assetID == request.asset.id,
              request.operation.phase == .dispatchIntent else { throw WebAdapterError.invalidRequest }
        guard !inputInFlight else { throw WebAdapterError.inputInFlight }
        inputInFlight = true
        defer { inputInFlight = false }

        try await preflight(asset: request.asset, fileURL: request.fileURL)

        guard let maximumChunkBytes = program?.maximumChunkBytes else { throw WebAdapterError.programUnavailable }
        // Two passes through the same no-follow descriptor: do not transfer an
        // already-corrupt file, and do not commit if bytes change while chunking.
        let file = try PrivateUploadFile(request: request, mediaDirectory: mediaDirectory)
        let verifiedHeader = try file.verifyAndRewind()
        if case .systemScreenshotCandidate = mode, let candidateAdmission {
            try SystemScreenshotWebCandidate.validateHeader(Array(verifiedHeader), asset: request.asset,
                restrictedAdmission: true)
            try await candidateAdmission.enroll(request)
        }
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        let suffix = request.fileURL.pathExtension
        let uploadName = "riftlet-\(request.operation.id.uuidString).\(suffix)"
        var began = false
        var committing = false
        do {
            let begin = WebBridgeCommand(action: .begin, target: identity.target, identity: identity,
                uploadName: uploadName, mediaType: request.asset.mediaType, byteCount: request.asset.byteCount)
            let beginReply = try await perform(begin)
            try acknowledge(beginReply, identity: identity, nextChunk: 0)
            began = true
            var index = 0
            var hash = SHA256()
            while let chunk = try file.nextChunk(maximumBytes: maximumChunkBytes) {
                hash.update(data: chunk)
                let command = WebBridgeCommand(action: .chunk, target: identity.target, identity: identity,
                    chunkIndex: index, chunkBase64: chunk.base64EncodedString())
                let chunkReply = try await perform(command)
                try acknowledge(chunkReply, identity: identity, nextChunk: index + 1)
                index += 1
            }
            try file.verifyAfterRead(hash: hash.finalize().map { String(format: "%02x", $0) }.joined())
            // This is the only command permitted to trigger attachment input. The
            // page function must validate target + all chunks/hash atomically here.
            committing = true
            let response = try await perform(.init(action: .commit, target: identity.target,
                                                   identity: identity, chunkIndex: index))
            return try await observeCompletion(initial: response, identity: identity, request: request)
        } catch {
            if began && !committing {
                _ = try? await perform(.init(action: .discard, target: identity.target, identity: identity))
            }
            // Coordinator owns the durable UNKNOWN result; never select another
            // transport or retry commit after an uncertain external side effect.
            throw error
        }
    }

    public func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        try requireEnabled()
        try check(request.operation.target)
        try checkOrigin(request.asset)
        guard request.operation.assetID == request.asset.id,
              (request.operation.phase.isUnresolved || request.operation.phase == .succeeded),
              request.operation.phase != .prepared else { throw WebAdapterError.invalidRequest }
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        let data = try await perform(.init(action: .observe, target: identity.target, identity: identity))
        // Successful operations may only be checked for identity-correlated late
        // errors. A single observation does not start another polling/upload loop.
        if request.operation.phase == .succeeded {
            return try await normalize(data, for: request)
        }
        return try await observeCompletion(initial: data, identity: identity, request: request)
    }

    private func observeCompletion(initial: Data, identity: ObservationIdentity,
                                   request: TransferRequest) async throws -> TransferReceipt {
        let deadline = ProcessInfo.processInfo.systemUptime + polling.timeout
        var response = initial
        while true {
            let envelope = try ObservationDecoder.decode(response)
            let receipt = try await normalize(envelope, for: request)
            // Positive start returns without waiting for completion. Core policy
            // independently admits visual exit; subsequent calls only observe.
            if receipt.outcome == .uploadStarted { return receipt }
            switch envelope.observation.state {
            case .attached, .ready, .failed, .invalidated: return receipt
            case .inputTriggered, .uploadStarted, .unknown: break
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return receipt }
            try await Task.sleep(nanoseconds: UInt64(min(polling.interval, remaining) * 1_000_000_000))
            guard ProcessInfo.processInfo.systemUptime < deadline else { return receipt }
            // Observation after an uncertain result can never cause a second
            // input. There is deliberately no commit/begin fallback here.
            response = try await perform(.init(action: .observe, target: identity.target, identity: identity))
        }
    }

    private func requireEnabled() throws {
        if case .disabled = mode { throw WebAdapterError.disabled }
        guard let program, !program.sourceID.isEmpty, !program.functionSource.isEmpty,
              program.functionSource.utf8.count <= 128 * 1024,
              (64 * 1024...256 * 1024).contains(program.maximumChunkBytes) else { throw WebAdapterError.programUnavailable }
        if case .systemScreenshotCandidate = mode {
            guard program.sourceID == SystemScreenshotWebCandidate.sourceID,
                  SystemScreenshotWebCandidate.matches(normalizer.profile),
                  normalizer.profile.profileID == SystemScreenshotWebCandidate.completionProfileID,
                  candidateJournal != nil else {
                throw WebAdapterError.programUnavailable
            }
        }
    }

    private func checkOrigin(_ asset: ImportedAsset) throws {
        switch mode {
        case .disabled: throw WebAdapterError.disabled
        case .syntheticDevelopment:
            guard asset.origin == .synthetic else { throw WebAdapterError.syntheticAssetsOnly }
        case .systemScreenshotCandidate:
            guard asset.origin == .systemScreenshot else { throw SystemScreenshotInputError.systemScreenshotsOnly }
        }
    }

    private func checkNewInputScope(_ target: TargetLease) throws {
        if case .systemScreenshotCandidate = mode, candidateAdmission != nil {
            try SystemScreenshotWebCandidate.validateAdmittedTarget(target)
        }
    }

    private func normalize(_ data: Data, for request: TransferRequest) async throws -> TransferReceipt {
        try await normalize(ObservationDecoder.decode(data), for: request)
    }

    private func normalize(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest) async throws -> TransferReceipt {
        var scopedNormalizer = normalizer
        if case .systemScreenshotCandidate = mode, let candidateAdmission,
           try await candidateAdmission.admits(request) {
            scopedNormalizer = ObservationNormalizer(profile: SystemScreenshotWebCandidate.admittedProfile,
                developmentScope: .systemScreenshotCandidate)
        }
        let receipt = try scopedNormalizer.receipt(from: envelope, for: request)
        if case .systemScreenshotCandidate = mode {
            guard envelope.provenance.source == .integratedDevelopment, let candidateJournal else {
                throw ObservationError.syntheticEvidenceForRealAsset
            }
            // Preserve the first original positive/negative observations in
            // SQLite, independently of the latest receipt and admitted starts.
            // Failure after commit remains UNKNOWN; this never retries input.
            try await candidateJournal.record(envelope, for: request)
        }
        return receipt
    }

    private func perform(_ command: WebBridgeCommand) async throws -> Data {
        try requireEnabled()
        guard let program else { throw WebAdapterError.programUnavailable }
        do {
            let reply = try await executor.execute(command, program: program)
            guard reply.count <= ObservationDecoder.maximumPayloadBytes else { throw WebAdapterError.invalidReply }
            return reply
        } catch {
            // This bridge is synthetic-development-only. Log only a closed set
            // of code-owned labels/numeric OSStatus, never NSError descriptions,
            // page text, target identities, JavaScript or user paths.
            if case .syntheticDevelopment = mode {
                let label: String
                switch error as? WebAdapterError {
                case .disabled?: label = "disabled"
                case .programUnavailable?: label = "programUnavailable"
                case .syntheticAssetsOnly?: label = "syntheticAssetsOnly"
                case .invalidTarget?: label = "invalidTarget"
                case .invalidRequest?: label = "invalidRequest"
                case .invalidPrivateFile?: label = "invalidPrivateFile"
                case .inputInFlight?: label = "inputInFlight"
                case .invalidReply?: label = "invalidReply"
                case .browserNotFrontmost?: label = "browserNotFrontmost"
                case .nativeExecutionFailed?: label = "nativeExecutionFailed"
                case .nativeEventFailed(let code)?: label = "nativeEventFailed(\(code))"
                case .nativeSelectionChanged?: label = "nativeSelectionChanged"
                case .pageRejected(let code)?: label = "pageRejected(\(code.rawValue))"
                case nil: label = "unclassifiedTransportError"
                }
                let message = "RIFTLET_WEB_DIAGNOSTIC action=\(command.action.rawValue) error=\(label)\n"
                try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            }
            throw error
        }
    }

    private func check(_ target: TargetLease) throws {
        guard target.adapterID == id, target.surface == normalizer.profile.surface,
              target.surface == .webChat || target.surface == .webWork,
              target.applicationID == "com.google.Chrome",
              !target.sessionID.isEmpty, !target.windowID.isEmpty, target.tabID?.isEmpty == false,
              !target.documentID.isEmpty, !target.composerID.isEmpty, !target.draftGeneration.isEmpty else {
            throw WebAdapterError.invalidTarget
        }
    }

    private struct ValidationReply: Decodable { let target: TargetLease; let valid: Bool }
    private struct Acknowledgement: Decodable {
        let operationID: UUID
        let attempt: Int
        let nextChunk: Int
    }

    private func acknowledge(_ data: Data, identity: ObservationIdentity, nextChunk: Int) throws {
        let reply = try decode(Acknowledgement.self, from: data)
        guard reply.operationID == identity.operationID, reply.attempt == identity.attempt,
              reply.nextChunk == nextChunk else { throw WebAdapterError.invalidReply }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw WebAdapterError.invalidReply }
    }
}

private final class PrivateUploadFile {
    private let fd: Int32
    private let expectedHash: String
    private let expectedSize: Int64
    private let original: stat
    private var readCount: Int64 = 0

    init(request: TransferRequest, mediaDirectory: URL) throws {
        let url = request.fileURL.standardizedFileURL
        guard url.isFileURL, url.lastPathComponent == request.asset.fileName,
              url.deletingLastPathComponent().resolvingSymlinksInPath() == mediaDirectory.resolvingSymlinksInPath(),
              !url.pathExtension.isEmpty, request.asset.byteCount > 0,
              request.asset.byteCount <= 8 * 1024 * 1024 else { throw WebAdapterError.invalidPrivateFile }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw WebAdapterError.invalidPrivateFile }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_size == request.asset.byteCount else {
            close(descriptor); throw WebAdapterError.invalidPrivateFile
        }
        fd = descriptor; original = info; expectedHash = request.asset.sha256
        expectedSize = request.asset.byteCount
    }

    deinit { close(fd) }

    func nextChunk(maximumBytes: Int = 64 * 1024) throws -> Data? {
        guard (1...256 * 1024).contains(maximumBytes) else { throw WebAdapterError.invalidPrivateFile }
        var data = Data(count: maximumBytes)
        let count: Int = data.withUnsafeMutableBytes { buffer in
            var result: Int
            repeat { result = read(fd, buffer.baseAddress, buffer.count) } while result < 0 && errno == EINTR
            return result
        }
        guard count >= 0 else { throw WebAdapterError.invalidPrivateFile }
        if count == 0 { return nil }
        readCount += Int64(count)
        guard readCount <= expectedSize else { throw WebAdapterError.invalidPrivateFile }
        data.count = count
        return data
    }

    func verifyAndRewind() throws -> Data {
        var hash = SHA256()
        var header = Data()
        while let chunk = try nextChunk() {
            if header.count < 33 { header.append(chunk.prefix(33 - header.count)) }
            hash.update(data: chunk)
        }
        try verifyAfterRead(hash: hash.finalize().map { String(format: "%02x", $0) }.joined())
        guard lseek(fd, 0, SEEK_SET) == 0 else { throw WebAdapterError.invalidPrivateFile }
        readCount = 0
        return header
    }

    func verifyAfterRead(hash: String) throws {
        var now = stat()
        guard hash == expectedHash, readCount == expectedSize, fstat(fd, &now) == 0,
              now.st_dev == original.st_dev, now.st_ino == original.st_ino,
              now.st_size == original.st_size,
              now.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec,
              now.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec else {
            throw WebAdapterError.invalidPrivateFile
        }
    }
}
