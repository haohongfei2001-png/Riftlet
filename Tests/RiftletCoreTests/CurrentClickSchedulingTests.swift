import Foundation
import XCTest
@testable import RiftletCore

final class CurrentClickSchedulingTests: XCTestCase {
    private func target(_ tab: String) -> TargetLease {
        TargetLease(adapterID: "test", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "process", windowID: "1", tabID: tab, documentID: "document-\(tab)",
            composerID: "composer", draftGeneration: "draft")
    }

    func testCurrentClickWaitsForExecutionWithoutAnArbitraryThirtySecondExpiry() {
        let click = AcceptedSelection(assetID: UUID(), target: target("1"),
            visibilityRevision: 0, selectedAt: 10)
        XCTAssertTrue(click.isValid(at: 41))
        XCTAssertTrue(click.isValid(at: 600))
        click.cancel()
        XCTAssertFalse(click.isValid(at: 601))
    }

    func testBusyOriginalTabQueuesItsSiblingButAllowsAnotherTabAndPreservesOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        var assets: [ImportedAsset] = []
        for _ in 0..<3 {
            let name = UUID().uuidString
            let asset = ImportedAsset(sourceKey: name, fileName: name + ".png",
                sha256: String(repeating: "a", count: 64), byteCount: 1,
                pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
            try Data([1]).write(to: root.appendingPathComponent(asset.fileName))
            _ = try await store.importAsset(asset)
            assets.append(asset)
        }
        let adapter = HeldInputAdapter(heldAsset: assets[0].id)
        let coordinator = TransferCoordinator(store: store, adapter: adapter, mediaDirectory: root,
            validateAcceptedSelection: { $0.isValid() })
        for (index, tab) in ["1", "1", "2"].enumerated() {
            try await coordinator.select(AcceptedSelection(assetID: assets[index].id,
                target: target(tab), visibilityRevision: 0))
        }
        for _ in 0..<1000 {
            if await adapter.calls().contains(assets[2].id) { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let during = await adapter.calls()
        XCTAssertEqual(during, [assets[0].id, assets[2].id])
        let secondBefore = try await store.asset(id: assets[1].id)
        let operation = try await store.operation(id: XCTUnwrap(secondBefore?.activeOperationID))
        XCTAssertEqual(operation?.phase, .prepared)
        await adapter.release()
        for _ in 0..<1000 {
            if await adapter.calls().count == 3 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let after = await adapter.calls()
        XCTAssertEqual(after, [assets[0].id, assets[2].id, assets[1].id])
        for _ in 0..<1000 {
            if try await store.unresolvedOperations().allSatisfy({ $0.phase == .unknown }) { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let retained = try await store.assets()
        XCTAssertEqual(retained.count, 3)
        XCTAssertTrue(retained.allSatisfy { $0.visibility == .visible })
    }
}

private actor HeldInputAdapter: IndependentFileInputAdapter {
    nonisolated let id = "test"
    let heldAsset: UUID
    private var called: [UUID] = []
    private var waiting: CheckedContinuation<Void, Never>?
    init(heldAsset: UUID) { self.heldAsset = heldAsset }
    func calls() -> [UUID] { called }
    func release() { waiting?.resume(); waiting = nil }
    func captureTarget() throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) -> Bool { target.adapterID == id }
    func append(_ request: TransferRequest) throws -> TransferReceipt { throw RiftletError.invalidTransition }
    func append(_ request: TransferRequest,
        onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) throws -> TransferReceipt {
        throw RiftletError.invalidTransition
    }
    func append(_ request: TransferRequest,
        onInputExecutionReturned: @escaping @Sendable () async -> Void) async -> TransferReceipt {
        called.append(request.asset.id)
        if request.asset.id == heldAsset { await withCheckedContinuation { waiting = $0 } }
        await onInputExecutionReturned()
        return TransferReceipt(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256,
            target: request.operation.target, outcome: .unknown, profileID: "test")
    }
    func reconcile(_ request: TransferRequest) throws -> TransferReceipt { throw RiftletError.invalidTransition }
}
