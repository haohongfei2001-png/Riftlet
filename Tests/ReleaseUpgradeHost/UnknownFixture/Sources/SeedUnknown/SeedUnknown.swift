import Foundation
import RiftletCore

enum FixtureFailure: Error { case invalidLocation, unexpectedContents }

@main struct SeedUnknown {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let temp = ProcessInfo.processInfo.environment["RUNNER_TEMP"] else {
            throw FixtureFailure.invalidLocation
        }
        let action = args[1]
        let directory = URL(fileURLWithPath: args[2], isDirectory: true).resolvingSymlinksInPath()
        let scratch = directory.deletingLastPathComponent()
        let locations = ["seed": "legacy-data", "reject": "latest-upgraded-data"]
        guard locations[action] == directory.lastPathComponent,
              scratch.lastPathComponent.hasPrefix("riftlet-upgrade-"),
              scratch.deletingLastPathComponent().path == URL(fileURLWithPath: temp, isDirectory: true).resolvingSymlinksInPath().path
        else { throw FixtureFailure.invalidLocation }
        let database = directory.appendingPathComponent("queue.sqlite")
        if action == "reject" {
            do {
                _ = try QueueStore(databaseURL: database)
                throw FixtureFailure.unexpectedContents
            } catch RiftletError.database(let reason) where reason == "Unsupported schema version 4; database preserved" {
                return
            }
        }
        let store = try QueueStore(databaseURL: database)
        let assets = try await store.assets(includeUsed: true)
        guard assets.count == 1, let candidate = assets.first, candidate.image.sha256 == args[3],
              candidate.status == .pending, candidate.activeOperationID == nil
        else { throw FixtureFailure.unexpectedContents }
        let target = TargetLease(adapterID: "offline-fixture", surface: .webChat, applicationID: "fixture.invalid",
                                 sessionID: "local", windowID: "test", documentID: "test", composerID: "test", draftGeneration: "1")
        let op = try await store.prepare(assetID: candidate.id, target: target)
        _ = try await store.markDispatchIntent(op.id)
        try await store.markUnknown(op.id, reason: "Isolated update fixture")
        guard try await store.operation(id: op.id)?.phase == .unknown,
              try await store.asset(id: candidate.id)?.activeOperationID == op.id
        else { throw FixtureFailure.unexpectedContents }
    }
}
