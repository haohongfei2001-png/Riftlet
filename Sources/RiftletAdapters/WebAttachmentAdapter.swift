import Foundation
import CryptoKit
import Darwin
import RiftletCore

public enum WebAdapterMode: Sendable, Equatable { case disabled, syntheticDevelopment, systemScreenshotCandidate, ordinarySystemScreenshot, ordinaryProduct }
public enum WebBridgeAction: String, Codable, CaseIterable, Sendable {
    case captureTarget, pinTarget, validate, begin, chunk, commit, observe, discard
}

/// The sole page function is supplied from reviewed source. It returns a
/// serializable observation, or a Promise while discovering an attachment entry,
/// retains no chat text, and checks the original target immediately before
/// File/DataTransfer input. `discard`
/// clears only this operation's temporary byte buffer; it never removes attachments.
public struct WebPageProgram: Sendable {
    public let sourceID: String
    public let functionSource: String
    /// Code-owned transport capacity; never negotiated from page JSON. Older
    /// and generic programs retain their 64 KiB default.
    public let maximumChunkBytes: Int
    /// The current program can await attachment-entry discovery before input.
    /// This bounds recovery of that execution after a lost commit reply; it is
    /// not an upload timeout or a permission to repeat an operation.
    public let inputDiscoveryTimeout: TimeInterval
    public init(sourceID: String, functionSource: String, maximumChunkBytes: Int = 64 * 1024,
                inputDiscoveryTimeout: TimeInterval = 0) {
        self.sourceID = sourceID; self.functionSource = functionSource
        self.maximumChunkBytes = maximumChunkBytes
        self.inputDiscoveryTimeout = inputDiscoveryTimeout.isFinite ? min(3, max(0, inputDiscoveryTimeout)) : 0
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
    public let invocationID: UUID?
    /// Host diagnostics only, deliberately excluded from the page payload.
    public let captureInvocation: CaptureInvocationContext?

    private enum CodingKeys: String, CodingKey {
        case action, target, identity, uploadName, mediaType, byteCount, chunkIndex, chunkBase64, invocationID
    }

    init(action: WebBridgeAction, target: TargetLease? = nil, identity: ObservationIdentity? = nil,
         uploadName: String? = nil, mediaType: String? = nil, byteCount: Int64? = nil,
         chunkIndex: Int? = nil, chunkBase64: String? = nil, invocationID: UUID? = nil,
         captureInvocation: CaptureInvocationContext? = nil) {
        self.action = action; self.target = target; self.identity = identity
        self.uploadName = uploadName; self.mediaType = mediaType; self.byteCount = byteCount
        self.chunkIndex = chunkIndex; self.chunkBase64 = chunkBase64; self.invocationID = invocationID
        self.captureInvocation = captureInvocation
    }
}

public protocol WebBridgeExecutor: Sendable {
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data
}

@MainActor public protocol WebClickTargetPinning: WebBridgeExecutor {
    func targetForClick(program: WebPageProgram) throws -> Task<TargetLease, Error>
}

public enum WebAdapterError: Error, Equatable, Sendable {
    case disabled, programUnavailable, syntheticAssetsOnly, invalidTarget, invalidRequest
    case invalidPrivateFile, inputInFlight, invalidReply, browserNotFrontmost, nativeExecutionFailed
    case nativeEventFailed(Int32)
    case nativeSelectionChanged, captureSuperseded, pageRejected(WebPageRejection)

    /// Closed, content-free labels. Never interpolate a generic Error/NSError.
    public var diagnosticLabel: String {
        switch self {
        case .disabled: return "disabled"
        case .programUnavailable: return "programUnavailable"
        case .syntheticAssetsOnly: return "syntheticAssetsOnly"
        case .invalidTarget: return "invalidTarget"
        case .invalidRequest: return "invalidRequest"
        case .invalidPrivateFile: return "invalidPrivateFile"
        case .inputInFlight: return "inputInFlight"
        case .invalidReply: return "invalidReply"
        case .captureSuperseded: return "captureSuperseded"
        case .browserNotFrontmost: return "browserNotFrontmost"
        case .nativeExecutionFailed: return "nativeExecutionFailed"
        case .nativeEventFailed(let code): return "nativeEventFailed(\(code))"
        case .nativeSelectionChanged: return "nativeSelectionChanged"
        case .pageRejected(let code): return "pageRejected(\(code.rawValue))"
        }
    }

    static func isDiagnosticLabel(_ value: String) -> Bool {
        let labels = ["none", "unclassified", "unclassifiedTransportError", "disabled", "programUnavailable",
            "syntheticAssetsOnly", "invalidTarget", "invalidRequest", "invalidPrivateFile", "inputInFlight",
            "invalidReply", "captureSuperseded", "browserNotFrontmost", "nativeExecutionFailed", "nativeSelectionChanged"]
        if labels.contains(value) { return true }
        if WebPageRejection.allCases.contains(where: { "pageRejected(\($0.rawValue))" == value }) { return true }
        let prefix = "nativeEventFailed("
        if value.hasPrefix(prefix), value.hasSuffix(")"),
           let code = Int32(value.dropFirst(prefix.count).dropLast()), value == "\(prefix)\(code))" { return true }
        return false
    }
}

/// One transport shared by source-scoped ordinary and isolated test compositions.
/// Each start/completion scope is assigned only to registered new
/// operations; historical operations retain their observation-only profiles.
public actor WebAttachmentAdapter: IndependentFileInputAdapter {
    public nonisolated let id: String
    private let mediaDirectory: URL
    private nonisolated let executor: any WebBridgeExecutor
    private nonisolated let program: WebPageProgram?
    private nonisolated let mode: WebAdapterMode
    private let normalizer: ObservationNormalizer
    private let polling: WebObservationPolling
    private let candidateJournal: SystemScreenshotObservationJournal?
    private let candidateAdmission: SystemScreenshotCandidateAdmission?
    private let productOrigins: Set<AssetOrigin>
    private let productBindings: [AssetOrigin: (admission: SystemScreenshotCandidateAdmission, journal: SystemScreenshotObservationJournal)]
    private let onInputTransportFinished: (@Sendable () async -> Void)?
    private let diagnosticTrace: BoundedDiagnosticTrace?
    // The transport lease is released only by its own original append. A prior
    // observer finishing must never unlock a later operation's begin/commit.
    private var inputOwner: UUID?
    // Lightweight identity tombstones, never file buffers. A repeated request
    // must not turn an earlier external input into local-before-begin proof.
    private var enteredOperations = Set<UUID>()

    public init(mediaDirectory: URL, executor: any WebBridgeExecutor,
                program: WebPageProgram? = nil, mode: WebAdapterMode = .disabled,
                profile: ObservationProfile = .init(adapterID: "chatgpt-web", surface: .webChat,
                                                     profileID: "web-unadmitted-v1"),
                polling: WebObservationPolling = .acceptance,
                candidateJournal: SystemScreenshotObservationJournal? = nil,
                candidateAdmission: SystemScreenshotCandidateAdmission? = nil,
                productStore: QueueStore? = nil, productOrigins: Set<AssetOrigin> = [],
                onInputTransportFinished: (@Sendable () async -> Void)? = nil,
                diagnosticTrace: BoundedDiagnosticTrace? = nil) {
        id = profile.adapterID; self.mediaDirectory = mediaDirectory.standardizedFileURL
        self.executor = executor; self.program = program; self.mode = mode
        if mode == .ordinarySystemScreenshot || mode == .ordinaryProduct {
            normalizer = ObservationNormalizer(profile: profile, developmentScope: .ordinarySystemScreenshot)
        } else if case .systemScreenshotCandidate = mode {
            normalizer = ObservationNormalizer(profile: profile, developmentScope: .systemScreenshotCandidate)
        } else { normalizer = ObservationNormalizer(profile: profile) }
        self.polling = polling
        self.candidateJournal = candidateJournal
        self.candidateAdmission = candidateAdmission
        self.productOrigins = productOrigins
        self.onInputTransportFinished = onInputTransportFinished
        self.diagnosticTrace = diagnosticTrace
        if mode == .ordinaryProduct, let productStore {
            productBindings = Dictionary(uniqueKeysWithValues: [SystemScreenshotAdmissionScope.productSystem, .productApplication].map {
                ($0.origin, (SystemScreenshotCandidateAdmission(store: productStore, scope: $0),
                             SystemScreenshotObservationJournal(store: productStore, scope: $0)))
            })
        } else { productBindings = [:] }
    }

    private var screenshotScope: SystemScreenshotAdmissionScope? {
        switch mode {
        case .systemScreenshotCandidate: return .candidate
        case .ordinarySystemScreenshot:
            return candidateAdmission?.scope == .ordinaryCurrentDraftInternal ? .ordinaryCurrentDraftInternal : .ordinary
        case .ordinaryProduct: return .productSystem
        default: return nil
        }
    }

    public func preflight(asset: ImportedAsset, fileURL: URL) async throws {
        if screenshotScope != nil {
            try requireEnabled()
            try checkOrigin(asset)
            try SystemScreenshotWebCandidate.preflight(asset, fileURL: fileURL, mediaDirectory: mediaDirectory,
                restrictedAdmission: candidateAdmission != nil || mode == .ordinaryProduct,
                expectedOrigin: mode == .ordinaryProduct ? asset.origin : .systemScreenshot)
        }
    }

    /// Freeze the native destination at the click boundary, then initialize and
    /// resolve that exact page asynchronously. A first click needs no earlier
    /// capture, relay or page acknowledgement.
    @MainActor public func targetForClick() throws -> Task<TargetLease, Error> {
        guard mode != .disabled, let program,
              let pinner = executor as? any WebClickTargetPinning else { throw WebAdapterError.disabled }
        return try pinner.targetForClick(program: program)
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
        try await append(request, inputConfirmed: nil)
    }

    public func append(_ request: TransferRequest,
                       onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) async throws -> TransferReceipt {
        try await append(request, inputConfirmed: onInputConfirmed)
    }

    public func append(_ request: TransferRequest,
                       onInputExecutionReturned: @escaping @Sendable () async -> Void) async throws -> TransferReceipt {
        try await append(request, inputConfirmed: nil, inputExecutionReturned: onInputExecutionReturned)
    }

    private func append(_ request: TransferRequest,
                        inputConfirmed: (@Sendable (TransferReceipt) async -> Void)?,
                        inputExecutionReturned: (@Sendable () async -> Void)? = nil) async throws -> TransferReceipt {
        try requireEnabled()
        try check(request.operation.target)
        try checkNewInputScope(request.operation.target)
        try checkOrigin(request.asset)
        guard request.operation.assetID == request.asset.id,
              request.operation.phase == .dispatchIntent else { throw WebAdapterError.invalidRequest }
        guard inputOwner == nil else { throw WebAdapterError.inputInFlight }
        guard enteredOperations.insert(request.operation.id).inserted else { throw WebAdapterError.invalidRequest }
        let operationID = request.operation.id
        inputOwner = operationID
        defer {
            releaseInput(ownedBy: operationID)
        }

        let input: (response: Data?, identity: ObservationIdentity)
        do { input = try await performFileInput(request) }
        catch {
            releaseInput(ownedBy: operationID)
            await inputExecutionReturned?()
            await onInputTransportFinished?()
            throw error
        }
        // The command has settled even when the attachment result is UNKNOWN.
        // A lost asynchronous commit first observes only its still-running
        // discovery, below. Upload/START observation never holds this lane.
        releaseInput(ownedBy: operationID)
        await inputExecutionReturned?()
        await onInputTransportFinished?()
        let response: Data
        if let returned = input.response {
            response = returned
        } else {
            // Even the first recovery read is observation, not file execution.
            // A delayed/lost reply here must not hold the next screenshot.
            response = try await perform(.init(action: .observe, target: input.identity.target,
                identity: input.identity))
        }
        return try await observeCompletion(initial: response, identity: input.identity,
            request: request, liveAppend: true, inputConfirmed: inputConfirmed)
    }

    private func releaseInput(ownedBy operationID: UUID) {
        if inputOwner == operationID { inputOwner = nil }
    }

    private func performFileInput(_ request: TransferRequest) async throws
        -> (response: Data?, identity: ObservationIdentity) {
        guard let maximumChunkBytes = program?.maximumChunkBytes else { throw WebAdapterError.programUnavailable }
        let file: PrivateUploadFile
        do {
            // No bridge command has occurred in this invocation. The durable
            // dispatch nonce is allocated by Core's one-shot intent claim.
            try await preflight(asset: request.asset, fileURL: request.fileURL)
            file = try PrivateUploadFile(request: request, mediaDirectory: mediaDirectory)
            let verifiedHeader = try file.verifyAndRewind()
            if screenshotScope != nil, let admission = binding(for: request.asset)?.admission {
                try SystemScreenshotWebCandidate.validateHeader(Array(verifiedHeader), asset: request.asset,
                    restrictedAdmission: true)
                try await admission.enroll(request)
            }
        } catch {
            if let invocationID = request.invocationID {
                throw PreInputRejection(operationID: request.operation.id, assetID: request.asset.id,
                    attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
                    target: request.operation.target, invocationID: invocationID, stage: .localBeforeBegin)
            }
            throw error
        }
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        let suffix = request.fileURL.pathExtension
        let uploadName = "riftlet-\(request.operation.id.uuidString).\(suffix)"
        var committing = false
        do {
            let begin = WebBridgeCommand(action: .begin, target: identity.target, identity: identity,
                uploadName: uploadName, mediaType: request.asset.mediaType, byteCount: request.asset.byteCount,
                invocationID: request.invocationID)
            let beginReply = try await perform(begin)
            try acknowledge(beginReply, identity: identity, nextChunk: 0)
            var index = 0
            var hash = SHA256()
            while let chunk = try file.nextChunk(maximumBytes: maximumChunkBytes) {
                hash.update(data: chunk)
                let command = WebBridgeCommand(action: .chunk, target: identity.target, identity: identity,
                    chunkIndex: index, chunkBase64: chunk.base64EncodedString(), invocationID: request.invocationID)
                let chunkReply = try await perform(command)
                try acknowledge(chunkReply, identity: identity, nextChunk: index + 1)
                index += 1
            }
            try file.verifyAfterRead(hash: hash.finalize().map { String(format: "%02x", $0) }.joined())
            // This is the only command permitted to trigger attachment input. The
            // page function rechecks the target and the complete current payload.
            committing = true
            let response: Data
            do {
                response = try await perform(.init(action: .commit, target: identity.target,
                    identity: identity, chunkIndex: index, invocationID: request.invocationID))
                // A malformed/lost transport receipt does not undo a file input.
                // Recover only by observing this operation, never another commit.
                _ = try ObservationDecoder.decode(response)
            } catch {
                // A lost native reply can leave asynchronous menu discovery
                // running. Keep only this current execution's lane until it
                // settles or its code-owned discovery deadline expires. Never
                // repeat commit, inspect old uploads, or wait for START here.
                return (await settleInterruptedInput(identity), identity)
            }
            return (response, identity)
        } catch {
            if !committing {
                _ = try? await perform(.init(action: .discard, target: identity.target,
                    identity: identity, invocationID: request.invocationID))
                // Only commit can invoke setter/change. We did not call it, so
                // no allocation, discard ACK or historical proof is needed to
                // know this screenshot was not submitted. Cleanup is best effort.
                if let invocationID = request.invocationID {
                    throw PreInputRejection(operationID: identity.operationID, assetID: identity.assetID,
                        attempt: identity.attempt, assetSHA256: identity.assetSHA256, target: identity.target,
                        invocationID: invocationID, stage: .localBeforeBegin,
                        reason: "fileInputCommandNotInvoked")
                }
            }
            // Coordinator owns the durable UNKNOWN result; never select another
            // transport or retry commit after an uncertain external side effect.
            throw error
        }
    }

    private func settleInterruptedInput(_ identity: ObservationIdentity) async -> Data? {
        guard let timeout = program?.inputDiscoveryTimeout, timeout > 0 else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout + 0.5
        var latest: Data?
        while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
            let slot = BoundedInputObservation()
            // A transport read can itself stall. A late read remains read-only
            // and cannot extend the absolute execution-recovery budget.
            let read = Task {
                let data = try? await self.perform(.init(action: .observe, target: identity.target, identity: identity))
                await slot.finish(data)
            }
            let timer = Task {
                let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                catch { return }
                await slot.finish(nil)
            }
            let data = await withTaskCancellationHandler(operation: { await slot.wait() }, onCancel: {
                read.cancel(); timer.cancel()
                Task { await slot.finish(nil) }
            })
            read.cancel(); timer.cancel()
            if let data, let envelope = try? ObservationDecoder.decode(data), envelope.observation.identity == identity {
                latest = data
                let item = envelope.observation
                if item.inputExecutionPending == false || item.preInputRetirement != nil
                    || [.inputTriggered, .uploadStarted, .attached, .ready, .failed, .invalidated].contains(item.state) {
                    return data
                }
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0, !Task.isCancelled else { break }
            do { try await Task.sleep(nanoseconds: UInt64(min(0.05, remaining) * 1_000_000_000)) }
            catch { break }
        }
        // The current JS program checks its discovery deadline again before
        // the setter. Expiry releases execution, never asserting input/START.
        return latest
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
                                   request: TransferRequest, liveAppend: Bool = false,
                                   inputConfirmed: (@Sendable (TransferReceipt) async -> Void)? = nil) async throws -> TransferReceipt {
        let deadline = ProcessInfo.processInfo.systemUptime + polling.timeout
        var response = initial
        var didConfirmInput = false
        while true {
            let envelope = try ObservationDecoder.decode(response)
            // Only the still-running original append may consume a positive
            // no-input retirement. Reconcile/restart never revives UNKNOWN.
            if liveAppend, let rejection = try WebPreInputRetirement.rejection(from: envelope, for: request) {
                recordResourceRefusal(envelope.observation.resourceRefusalReason,
                    action: .commit, operationID: request.operation.id)
                throw rejection
            }
            let receipt = try await normalize(envelope, for: request, liveAppend: liveAppend)
            if liveAppend, !didConfirmInput,
               receipt.outcome == .inputTriggered || receipt.outcome == .uploadStarted,
               receipt.operationID == request.operation.id, receipt.assetID == request.asset.id,
               receipt.attempt == request.operation.attempt, receipt.assetSHA256 == request.asset.sha256,
               receipt.target == request.operation.target, receipt.belongsToOriginalDraft, !receipt.hasError {
                // The page reports input only after setter/change has returned.
                // Release this short execution lane before any START observation.
                // Upload state and old FileLists never own the next input.
                didConfirmInput = true
                releaseInput(ownedBy: request.operation.id)
                await inputConfirmed?(receipt)
            }
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
        if mode == .ordinaryProduct {
            guard candidateJournal == nil, candidateAdmission == nil,
                  !productBindings.isEmpty, productOrigins.isSubset(of: [.systemScreenshot, .applicationScreenshot]),
                  program.sourceID == SystemScreenshotWebCandidate.sourceID,
                  normalizer.profile.profileID == OrdinaryProductScreenshotScope.systemProfile.profileID,
                  normalizer.profile.uploadStartProfileID == OrdinaryProductScreenshotScope.systemProfile.uploadStartProfileID,
                  normalizer.profile.adapterID == "chatgpt-web", normalizer.profile.surface == .webChat,
                  normalizer.profile.completionSignal == .attached, normalizer.profile.failureSignal == nil else {
                throw WebAdapterError.programUnavailable
            }
        } else if let scope = screenshotScope {
            guard candidateJournal?.scope == scope,
                  candidateAdmission == nil || candidateAdmission?.scope == scope,
                  (scope == .candidate || candidateAdmission != nil),
                  program.sourceID == SystemScreenshotWebCandidate.sourceID,
                  normalizer.profile.adapterID == scope.legacyProfile.adapterID,
                  normalizer.profile.surface == scope.legacyProfile.surface,
                  normalizer.profile.profileID == scope.legacyProfile.profileID,
                  normalizer.profile.uploadStartProfileID == scope.legacyProfile.uploadStartProfileID,
                  normalizer.profile.completionSignal == .attached, normalizer.profile.failureSignal == nil,
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
        case .systemScreenshotCandidate, .ordinarySystemScreenshot:
            guard asset.origin == .systemScreenshot else { throw SystemScreenshotInputError.systemScreenshotsOnly }
        case .ordinaryProduct:
            guard productOrigins.contains(asset.origin), productBindings[asset.origin] != nil else {
                throw SystemScreenshotInputError.sourceNotAdmitted
            }
        }
    }

    private func checkNewInputScope(_ target: TargetLease) throws {
        if let scope = screenshotScope, candidateAdmission != nil || mode == .ordinaryProduct {
            try scope.validateTarget(target)
        }
    }

    private func binding(for asset: ImportedAsset) -> (admission: SystemScreenshotCandidateAdmission, journal: SystemScreenshotObservationJournal)? {
        if mode == .ordinaryProduct { return productBindings[asset.origin] }
        guard let candidateAdmission, let candidateJournal else { return nil }
        return (candidateAdmission, candidateJournal)
    }

    private func normalize(_ data: Data, for request: TransferRequest) async throws -> TransferReceipt {
        try await normalize(ObservationDecoder.decode(data), for: request)
    }

    private func normalize(_ envelope: AttachmentObservationEnvelope, for request: TransferRequest,
                           liveAppend: Bool = false) async throws -> TransferReceipt {
        var scopedNormalizer = normalizer
        var originalScope: SystemScreenshotAdmissionScope?
        let binding = binding(for: request.asset)
        if mode == .ordinaryProduct, let binding {
            scopedNormalizer = ObservationNormalizer(profile: binding.admission.scope.legacyProfile,
                developmentScope: .ordinarySystemScreenshot)
        }
        if screenshotScope != nil, let binding {
            originalScope = try await binding.admission.admittedObservationScope(for: request)
        }
        if let scope = originalScope {
            scopedNormalizer = ObservationNormalizer(profile: scope.admittedProfile,
                developmentScope: scope.observationScope)
        }
        let receipt = try scopedNormalizer.receipt(from: envelope, for: request, liveAppend: liveAppend)
        if screenshotScope != nil {
            guard envelope.provenance.source == .integratedDevelopment,
                  let journal = binding?.journal ?? candidateJournal else {
                throw ObservationError.syntheticEvidenceForRealAsset
            }
            // Preserve the first original positive/negative observations in
            // SQLite, independently of the latest receipt and admitted starts.
            // Failure after commit remains UNKNOWN; this never retries input.
            if let originalScope, originalScope != journal.scope {
                try await journal.recordForOriginalScope(envelope, for: request, originalScope: originalScope)
            } else {
                try await journal.record(envelope, for: request)
            }
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
            var facts: [String: Any] = ["event": "web_command_refused", "action": command.action.rawValue,
                "error": (error as? WebAdapterError)?.diagnosticLabel ?? "unclassifiedTransportError"]
            if let id = command.identity?.operationID { facts["operationID"] = id.uuidString }
            if case .pageRejected(let code)? = error as? WebAdapterError, code.isInputResourceRefusal {
                facts["resourceRefusalReason"] = code.rawValue
            }
            diagnosticTrace?.record(facts, critical: command.action != .captureTarget && command.action != .observe)
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
                case .captureSuperseded?: label = "captureSuperseded"
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

    private func recordResourceRefusal(_ reason: WebPageRejection?, action: WebBridgeAction, operationID: UUID) {
        guard let reason, reason.isInputResourceRefusal else { return }
        diagnosticTrace?.record(["event": "input_resource_refused", "action": action.rawValue,
            "operationID": operationID.uuidString, "resourceRefusalReason": reason.rawValue], critical: true)
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

/// A single observation wins against its absolute deadline. Unlike a task group,
/// this does not wait indefinitely for a transport that ignores cancellation.
private actor BoundedInputObservation {
    private var completed = false
    private var value: Data?
    private var waiter: CheckedContinuation<Data?, Never>?
    func finish(_ value: Data?) {
        guard !completed else { return }
        completed = true; self.value = value
        waiter?.resume(returning: value); waiter = nil
    }
    func wait() async -> Data? {
        if completed { return value }
        return await withCheckedContinuation { waiter = $0 }
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
