import Foundation
import RiftletCore

@main struct SeedOperation {
    enum FixtureError: Error { case invalidFixture }

    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3, let temporary = ProcessInfo.processInfo.environment["RUNNER_TEMP"] else {
            throw FixtureError.invalidFixture
        }
        let path = URL(fileURLWithPath: args[1], isDirectory: true).resolvingSymlinksInPath()
        let authorized = URL(fileURLWithPath: temporary, isDirectory: true).resolvingSymlinksInPath()
            .appendingPathComponent("public-sparkle/detached65", isDirectory: true)
        guard path == authorized else { throw FixtureError.invalidFixture }
        let store = try QueueStore(databaseURL: path.appendingPathComponent("queue.sqlite"))
        let rows = try await store.assets(includeUsed: true)
        guard rows.count == 2, let record = rows.first(where: { $0.image.sha256 == args[2] }),
              record.visibility == .visible, record.status == .pending else { throw FixtureError.invalidFixture }
        let target = TargetLease(adapterID: "isolated-upgrade-sample", surface: .webChat,
            applicationID: "org.riftlet.qa.offline", sessionID: "qa", windowID: "fixture-window",
            tabID: "fixture-tab", documentID: "fixture-document", composerID: "fixture-editor",
            draftGeneration: "fixture-generation", clickBindingID: UUID())
        let operation = try await store.prepare(assetID: record.id, target: target)
        let owner = UUID()
        let invocation = try await store.markIndependentFileInputIntent(operation.id, ownerID: owner)
        let receipt = TransferReceipt(operationID: operation.id, assetID: record.id, attempt: operation.attempt,
            assetSHA256: record.image.sha256, target: target, outcome: .unknown, profileID: "offline-upgrade-qa",
            reason: "Synthetic persisted UNKNOWN for a version upgrade; no browser or network was invoked.")
        try await store.recordAppendReturned(receipt, invocationID: invocation, ownerID: owner)
        _ = try await store.apply(receipt)
        guard let asset = try await store.asset(id: record.id) else { throw FixtureError.invalidFixture }
        if asset.visibility == .visible {
            let click = try await store.beginTraySelection(assetID: asset.id, expectedRevision: asset.visibilityRevision, fromHistory: false)
            await store.endTraySelection(click)
        }
        guard try await store.receipt(for: operation.id) == receipt,
              try await store.dispatchInvocationID(for: operation.id) == invocation,
              try await store.operation(id: operation.id)?.phase == .unknown,
              try await store.recentTrayHistory().contains(where: { $0.id == record.id }) else { throw FixtureError.invalidFixture }
        let result: [String: Any] = ["operationID": operation.id.uuidString, "invocationID": invocation.uuidString,
            "assetID": record.id.uuidString, "attempt": operation.attempt, "assetSHA256": record.image.sha256,
            "receipt": "offline-upgrade-qa", "outcome": "unknown"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
