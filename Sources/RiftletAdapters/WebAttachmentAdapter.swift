import Foundation
import CryptoKit
import Darwin
import RiftletCore

public enum WebAdapterMode: Sendable { case disabled, syntheticDevelopment }
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
    public init(sourceID: String, functionSource: String) {
        self.sourceID = sourceID; self.functionSource = functionSource
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

    init(action: WebBridgeAction, target: TargetLease? = nil, identity: ObservationIdentity? = nil,
         uploadName: String? = nil, mediaType: String? = nil, byteCount: Int64? = nil,
         chunkIndex: Int? = nil, chunkBase64: String? = nil) {
        self.action = action; self.target = target; self.identity = identity
        self.uploadName = uploadName; self.mediaType = mediaType; self.byteCount = byteCount
        self.chunkIndex = chunkIndex; self.chunkBase64 = chunkBase64
    }
}

public protocol WebBridgeExecutor: Sendable {
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data
}

public enum WebAdapterError: Error, Equatable, Sendable {
    case disabled, programUnavailable, syntheticAssetsOnly, invalidTarget, invalidRequest
    case invalidPrivateFile, inputInFlight, invalidReply, browserNotFrontmost, nativeExecutionFailed
}

/// Real bridge code can be integrated without enabling real screenshots. There is
/// deliberately no production-enabling enum case in this unadmitted increment.
public actor WebAttachmentAdapter: AttachmentAdapter {
    public nonisolated let id: String
    private let mediaDirectory: URL
    private let executor: any WebBridgeExecutor
    private let program: WebPageProgram?
    private let mode: WebAdapterMode
    private let normalizer: ObservationNormalizer
    private var inputInFlight = false

    public init(mediaDirectory: URL, executor: any WebBridgeExecutor,
                program: WebPageProgram? = nil, mode: WebAdapterMode = .disabled,
                profile: ObservationProfile = .init(adapterID: "chatgpt-web", surface: .webChat,
                                                     profileID: "web-unadmitted-v1")) {
        id = profile.adapterID; self.mediaDirectory = mediaDirectory.standardizedFileURL
        self.executor = executor; self.program = program; self.mode = mode
        normalizer = ObservationNormalizer(profile: profile)
    }

    public func captureTarget() async throws -> TargetLease {
        let data = try await perform(.init(action: .captureTarget))
        let target = try decode(TargetLease.self, from: data)
        try check(target)
        return target
    }

    public func validate(_ target: TargetLease) async throws -> Bool {
        try check(target)
        let data = try await perform(.init(action: .validate, target: target))
        let response = try decode(ValidationReply.self, from: data)
        return response.valid && response.target == target
    }

    public func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try requireEnabled()
        try check(request.operation.target)
        guard request.asset.origin == .synthetic else { throw WebAdapterError.syntheticAssetsOnly }
        guard request.operation.assetID == request.asset.id,
              request.operation.phase == .dispatchIntent else { throw WebAdapterError.invalidRequest }
        guard !inputInFlight else { throw WebAdapterError.inputInFlight }
        inputInFlight = true
        defer { inputInFlight = false }

        // Two passes through the same no-follow descriptor: do not transfer an
        // already-corrupt file, and do not commit if bytes change while chunking.
        let file = try PrivateUploadFile(request: request, mediaDirectory: mediaDirectory)
        try file.verifyAndRewind()
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
            while let chunk = try file.nextChunk() {
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
            return try normalizer.receipt(from: ObservationDecoder.decode(response), for: request)
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
        guard request.asset.origin == .synthetic else { throw WebAdapterError.syntheticAssetsOnly }
        guard request.operation.assetID == request.asset.id,
              request.operation.phase.isUnresolved,
              request.operation.phase != .prepared else { throw WebAdapterError.invalidRequest }
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        let data = try await perform(.init(action: .observe, target: identity.target, identity: identity))
        return try normalizer.receipt(from: ObservationDecoder.decode(data), for: request)
    }

    private func requireEnabled() throws {
        guard case .syntheticDevelopment = mode else { throw WebAdapterError.disabled }
        guard let program, !program.sourceID.isEmpty, !program.functionSource.isEmpty,
              program.functionSource.utf8.count <= 128 * 1024 else { throw WebAdapterError.programUnavailable }
    }

    private func perform(_ command: WebBridgeCommand) async throws -> Data {
        try requireEnabled()
        guard let program else { throw WebAdapterError.programUnavailable }
        let reply = try await executor.execute(command, program: program)
        guard reply.count <= ObservationDecoder.maximumPayloadBytes else { throw WebAdapterError.invalidReply }
        return reply
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
              request.asset.byteCount <= 128 * 1024 * 1024 else { throw WebAdapterError.invalidPrivateFile }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
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

    func nextChunk() throws -> Data? {
        var data = Data(count: 64 * 1024)
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

    func verifyAndRewind() throws {
        var hash = SHA256()
        while let chunk = try nextChunk() { hash.update(data: chunk) }
        try verifyAfterRead(hash: hash.finalize().map { String(format: "%02x", $0) }.joined())
        guard lseek(fd, 0, SEEK_SET) == 0 else { throw WebAdapterError.invalidPrivateFile }
        readCount = 0
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
