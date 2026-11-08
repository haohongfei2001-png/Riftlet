import Foundation
import RiftletCore

enum FixtureFailure: Error { case invalidLocation, unexpectedContents }

@main struct SeedUnknown {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let temp = ProcessInfo.processInfo.environment["RUNNER_TEMP"] else {
            throw FixtureFailure.invalidLocation
        }
        let directory = URL(fileURLWithPath: args[1], isDirectory: true).resolvingSymlinksInPath()
        let scratch = directory.deletingLastPathComponent()
        guard directory.lastPathComponent == "latest-upgraded-data",
              scratch.lastPathComponent.hasPrefix("riftlet-upgrade-"),
              scratch.deletingLastPathComponent().path == URL(fileURLWithPath: temp, isDirectory: true).resolvingSymlinksInPath().path
        else { throw FixtureFailure.invalidLocation }
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
        let assets = try await store.assets(includeUsed: true)
        guard args[2] != args[3], assets.count == 2, Set(assets.map { $0.image.sha256 }) == Set(args[2...3]),
              assets.allSatisfy({ $0.status == .pending && $0.activeOperationID == nil }),
              let candidate = assets.first(where: { $0.image.sha256 == args[3] })
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
