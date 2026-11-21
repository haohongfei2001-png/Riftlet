import Foundation
import RiftletCore

private actor ReadProbe: IndependentFileInputAdapter {
    nonisolated let id = "fixture"
    nonisolated let supportsOriginalHandoffChecks = true
    var observations = 0
    func captureTarget() async throws -> TargetLease { fatalError("History cannot capture") }
    func validate(_ target: TargetLease) async throws -> Bool { fatalError("History cannot bind") }
    func append(_ request: TransferRequest) async throws -> TransferReceipt { fatalError("History cannot append") }
    func append(_ request: TransferRequest, onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) async throws -> TransferReceipt {
        fatalError("History cannot enter input")
    }
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt {
        observations += 1
        return TransferReceipt(operationID: request.operation.id, assetID: request.asset.id,
                               attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
                               target: request.operation.target, outcome: .unknown, profileID: "fixture")
    }
}

func checkReadOnlyRestart(click: BoundClick) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("fixture.sqlite")
    let db = try QueueStore(databaseURL: url)
    let stored = try await db.importAsset(ImportedAsset(sourceKey: "fixture", fileName: "capture.png",
        sha256: String(repeating: "a", count: 64), byteCount: 4, pixelWidth: 1, pixelHeight: 1, mediaType: "image/png"))
    let op = try await db.prepare(assetID: stored.id, target: click.target)
    let preexisting = try await StoredDispatch.load(for: op.id, store: db)
    precondition(preexisting == nil)
    let owner = UUID()
    let invocation = try await db.markIndependentFileInputIntent(op.id, ownerID: owner)
    guard let original = try await db.operation(id: op.id) else { throw BindingError.targetChanged }
    let fileURL = directory.appendingPathComponent(stored.image.fileName)
    let intent = TransferRequest(operation: original, asset: stored.image, fileURL: fileURL, invocationID: invocation)
    try await StoredDispatch.register(click, request: intent, store: db)
    try await db.recordInputExecutionReturned(operationID: op.id, invocationID: invocation, ownerID: owner)

    // Independently opened SQLite connection. No migration or write to user data.
    let reopened = try QueueStore(databaseURL: url)
    guard let binding = try await StoredDispatch.load(for: op.id, store: reopened),
          let recovered = try await reopened.operation(id: op.id) else { throw BindingError.targetChanged }
    let probe = ReadProbe()
    let address = AdapterAddress(bundle: click.native.bundle, profile: click.route.profile, adapterID: probe.id)
    let resolver = AdapterResolver(adapters: [address: probe])
    let read = TransferRequest(operation: recovered, asset: stored.image, fileURL: fileURL,
                               invocationID: invocation, requireLiveOriginal: true)
    let reader = try resolver.reader(for: read, original: binding)
    let receipt = try await reader.observe()
    precondition(receipt.operationID == op.id && receipt.outcome == .unknown)
    let wrongID = TransferRequest(operation: recovered, asset: stored.image, fileURL: fileURL,
                                  invocationID: UUID(), requireLiveOriginal: true)
    precondition((try? resolver.reader(for: wrongID, original: binding)) == nil)
    precondition((try? resolver.reader(for: intent, original: binding)) == nil)
    let changed = try ProviderProfile(id: click.route.profile.id, revision: click.route.profile.revision, program: Data("different".utf8))
    let changedAddress = AdapterAddress(bundle: address.bundle, profile: changed, adapterID: probe.id)
    precondition((try? AdapterResolver(adapters: [changedAddress: probe]).reader(for: read, original: binding)) == nil)
    let calls = await probe.observations
    let actualInvocation = try await reopened.dispatchInvocationID(for: op.id)
    let finalOp = try await reopened.operation(id: op.id)
    precondition(calls == 1 && actualInvocation == invocation && finalOp == recovered)
    print("PASS real SQLite: original dispatch survives reopen, one read, zero writes to the draft")
}
