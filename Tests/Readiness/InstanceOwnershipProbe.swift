import Foundation
import Darwin

private enum OwnershipProbeError: Error { case deadline, childFailed, competingOwnerAccepted, historyChanged }

@main struct InstanceOwnershipProbe {
    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 4, arguments[1] == "--owned-child" {
            let root = URL(fileURLWithPath: arguments[2], isDirectory: true)
            let owner = try ApplicationInstanceOwnership(root: root)
            if arguments[3] == "termination" { owner.keepUntilProcessExit(); owner.close() }
            try Data("ready".utf8).write(to: root.appendingPathComponent("ready"), options: .atomic)
            Thread.sleep(forTimeInterval: 0.5)
            withExtendedLifetime(owner) {}
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-owner-process-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("historical-unknown-marker")
        let bytes = Data("retain original history".utf8); try bytes.write(to: marker)
        let modes = ["normal", "termination", "signal", "crash"]
        for mode in modes {
            for _ in 0..<3 {
                let ready = root.appendingPathComponent("ready"); try? FileManager.default.removeItem(at: ready)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
                process.arguments = ["--owned-child", root.path, mode]
                let finished = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in finished.signal() }
                try process.run()
                defer { if process.isRunning { process.terminate() } }
                let deadline = Date().addingTimeInterval(3)
                while !FileManager.default.fileExists(atPath: ready.path) {
                    guard process.isRunning else { throw OwnershipProbeError.childFailed }
                    guard Date() < deadline else { throw OwnershipProbeError.deadline }
                    Thread.sleep(forTimeInterval: 0.01)
                }
                do {
                    let unexpected = try ApplicationInstanceOwnership(root: root); unexpected.close()
                    throw OwnershipProbeError.competingOwnerAccepted
                } catch ApplicationInstanceOwnership.Failure.unavailable { }
                if mode == "signal" { process.terminate() }
                if mode == "crash" { guard kill(process.processIdentifier, SIGKILL) == 0 else { throw OwnershipProbeError.childFailed } }
                guard finished.wait(timeout: .now() + 4) == .success else { throw OwnershipProbeError.deadline }
                if mode == "normal" || mode == "termination" {
                    guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw OwnershipProbeError.childFailed }
                } else {
                    guard process.terminationReason == .uncaughtSignal else { throw OwnershipProbeError.childFailed }
                }
                let replacement = try ApplicationInstanceOwnership(root: root); replacement.close()
                guard try Data(contentsOf: marker) == bytes else { throw OwnershipProbeError.historyChanged }
            }
        }
        print("READINESS_OWNERSHIP_PASS: 12 isolated subprocess lifetimes; normal exit, termination retention, SIGTERM, SIGKILL; original history retained; no App launched")
    }
}
