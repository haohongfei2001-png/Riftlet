import Foundation
import RiftletCore

/// One input adapter for the candidate provider set. TransferCoordinator owns
/// the original FIFO, invocation and restart lifecycle for all of its routes.
struct ProviderAttachmentRuntime: IndependentFileInputAdapter {
    let id = "riftlet-web-provider-v1"
    let supportsOriginalHandoffChecks = true
    let resolver: AdapterResolver
    let store: QueueStore

    func captureTarget() async throws -> TargetLease { throw BindingError.unsupported }

    private func destination(_ target: TargetLease) throws -> (ProviderProfile, any IndependentFileInputAdapter) {
        guard target.adapterID == id, let b = target.providerBinding, target.clickBindingID != nil else {
            throw BindingError.invalidProfile
        }
        let matches = resolver.adapters.filter { key, adapter in
            key.adapterID == id && adapter.id == id && key.bundle == target.applicationID &&
            key.profile.id == b.providerID && key.profile.revision == b.revision && key.profile.digest == b.programSHA256
        }
        guard matches.count == 1, let (address, adapter) = matches.first else { throw BindingError.unsupported }
        return (address.profile, adapter)
    }

    func preflight(asset: ImportedAsset, fileURL: URL, frozenTarget: TargetLease?) async throws {
        guard let frozenTarget else { throw BindingError.unsupported }
        try await destination(frozenTarget).1.preflight(asset: asset, fileURL: fileURL, frozenTarget: frozenTarget)
    }

    func validate(_ target: TargetLease) async throws -> Bool {
        try await destination(target).1.validate(target)
    }

    private func claim(_ request: TransferRequest) async throws -> any IndependentFileInputAdapter {
        let (profile, adapter) = try destination(request.operation.target)
        try await StoredDispatch.claimInput(profile: profile, request: request, store: store)
        return adapter
    }

    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try await claim(request).append(request)
    }

    func append(_ request: TransferRequest,
                onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) async throws -> TransferReceipt {
        try await claim(request).append(request, onInputConfirmed: onInputConfirmed)
    }

    func append(_ request: TransferRequest,
                onInputExecutionReturned: @escaping @Sendable () async -> Void) async throws -> TransferReceipt {
        try await claim(request).append(request, onInputExecutionReturned: onInputExecutionReturned)
    }

    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        guard let saved = try await StoredDispatch.load(for: request.operation.id, store: store) else {
            throw BindingError.unsupported
        }
        let read = TransferRequest(operation: request.operation, asset: request.asset, fileURL: request.fileURL,
                                   invocationID: request.invocationID, requireLiveOriginal: true)
        return try await resolver.reader(for: read, original: saved).observe()
    }
}
