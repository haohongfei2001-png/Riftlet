import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

@MainActor private final class CaptureBarrier {
    private var entered = false, released = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        observer?.resume(); observer = nil
        if released { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() {
        released = true
        waiting?.resume(); waiting = nil
    }
}

@MainActor private final class RecordingApplicationExecutor: WebClickTargetPinning {
    let target: TargetLease
    var barrier: CaptureBarrier?
    var captureError: WebAdapterError?
    var completionError: WebAdapterError?
    var executionError: WebAdapterError?
    private(set) var captures: [Task<TargetLease, Error>] = []
    private(set) var capturePrograms: [String] = []
    private(set) var commands: [WebBridgeCommand] = []
    private(set) var commandPrograms: [String] = []

    init(_ application: String) {
        target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: application,
            sessionID: "owned-fixture-session", windowID: "11", tabID: "12",
            documentID: "owned-fixture-document", composerID: "owned-fixture-composer",
            draftGeneration: "owned-fixture-draft", clickBindingID: UUID())
    }
    func targetForClick(program: WebPageProgram) throws -> Task<TargetLease, Error> {
        capturePrograms.append(program.sourceID)
        if let captureError { throw captureError }
        let target = target, barrier = barrier, completionError = completionError
        let capture = Task {
            await barrier?.wait()
            try Task.checkCancellation()
            if let completionError { throw completionError }
            return target
        }
        captures.append(capture)
        return capture
    }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        commands.append(command); commandPrograms.append(program.sourceID)
        if let executionError { throw executionError }
        return Data("original-host-reply".utf8)
    }
}

final class ApplicationWebExecutorTests: XCTestCase {
    private let chromeID = "com.google.Chrome", edgeID = "com.microsoft.edgemac"
    private let program = WebPageProgram(sourceID: "owned-mock-host-routing", functionSource: "function () {}")

    @MainActor func testClickSelectsHostSynchronouslyAndLaterClickCanIndependentlySelectAnother() async throws {
        let chrome = RecordingApplicationExecutor(chromeID), edge = RecordingApplicationExecutor(edgeID)
        let barrier = CaptureBarrier(); edge.barrier = barrier
        var current: String? = edgeID, foregroundReads = 0
        let bridge = ApplicationWebExecutor(executors: [chromeID: chrome, edgeID: edge], foreground: {
            foregroundReads += 1; return current
        })
        let original = try bridge.targetForClick(program: program)
        XCTAssertEqual(edge.capturePrograms, [program.sourceID])
        XCTAssertTrue(chrome.capturePrograms.isEmpty)
        XCTAssertEqual(foregroundReads, 1)
        current = chromeID
        let later = try bridge.targetForClick(program: program)
        barrier.release()
        let firstTarget = try await original.value, nextTarget = try await later.value
        XCTAssertEqual(firstTarget, edge.target)
        XCTAssertEqual(nextTarget, chrome.target)
        XCTAssertEqual(edge.captures.count, 1)
        XCTAssertEqual(chrome.captures.count, 1)
        XCTAssertEqual(foregroundReads, 2)
    }

    @MainActor func testEveryBoundCommandUsesOriginalLeaseWithoutReadingLaterForeground() async throws {
        let chrome = RecordingApplicationExecutor(chromeID), edge = RecordingApplicationExecutor(edgeID)
        var current: String? = edgeID, foregroundReads = 0
        let bridge = ApplicationWebExecutor(executors: [chromeID: chrome, edgeID: edge], foreground: {
            foregroundReads += 1; return current
        })
        let target = try await bridge.targetForClick(program: program).value
        let identity = ObservationIdentity(operationID: UUID(), assetID: UUID(), attempt: 1,
            assetSHA256: String(repeating: "a", count: 64), target: target)
        let actions = WebBridgeAction.allCases.filter { $0 != .captureTarget }
        for (index, action) in actions.enumerated() {
            current = index.isMultiple(of: 2) ? chromeID : nil
            let command = WebBridgeCommand(action: action, target: target, identity: identity,
                uploadName: "neutral.png", mediaType: "image/png", byteCount: 3,
                chunkIndex: 0, chunkBase64: "AAAA", invocationID: UUID(), clickWitnessID: UUID())
            let reply = try await bridge.execute(command, program: program)
            XCTAssertEqual(reply, Data("original-host-reply".utf8))
            let forwarded = try XCTUnwrap(edge.commands.last)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            XCTAssertEqual(try encoder.encode(forwarded), try encoder.encode(command))
        }
        XCTAssertEqual(edge.commands.map(\.action), actions)
        XCTAssertEqual(edge.commandPrograms, Array(repeating: program.sourceID, count: actions.count))
        XCTAssertTrue(chrome.commands.isEmpty)
        XCTAssertTrue(chrome.captures.isEmpty)
        XCTAssertEqual(foregroundReads, 1)
    }

    @MainActor func testUnknownForegroundAndMissingOrUnknownLeaseNeverUseAvailableChrome() async throws {
        let chrome = RecordingApplicationExecutor(chromeID)
        var current: String? = nil, foregroundReads = 0
        let bridge = ApplicationWebExecutor(executors: [chromeID: chrome], foreground: {
            foregroundReads += 1; return current
        })
        for application in [nil, "unregistered.application", edgeID] as [String?] {
            current = application
            XCTAssertThrowsError(try bridge.targetForClick(program: program)) {
                XCTAssertEqual($0 as? WebAdapterError, .browserNotFrontmost)
            }
        }
        current = chromeID
        let unsupported = RecordingApplicationExecutor("unregistered.application").target
        let absentEdge = RecordingApplicationExecutor(edgeID).target
        for target in [nil, unsupported, absentEdge] as [TargetLease?] {
            for action in WebBridgeAction.allCases where action != .captureTarget {
                do {
                    _ = try await bridge.execute(.init(action: action, target: target), program: program)
                    XCTFail("Missing original executor must not redirect to Chrome")
                } catch { XCTAssertEqual(error as? WebAdapterError, .invalidTarget) }
            }
        }
        XCTAssertEqual(foregroundReads, 3)
        XCTAssertTrue(chrome.capturePrograms.isEmpty)
        XCTAssertTrue(chrome.commands.isEmpty)
    }

    @MainActor func testWrongHostCaptureReplyCannotBecomeChromeLease() async throws {
        let chrome = RecordingApplicationExecutor(chromeID)
        let misreportingEdge = RecordingApplicationExecutor(chromeID)
        let bridge = ApplicationWebExecutor(executors: [chromeID: chrome, edgeID: misreportingEdge], foreground: { self.edgeID })
        do {
            _ = try await bridge.targetForClick(program: program).value
            XCTFail("The selected Edge executor cannot return another host's lease")
        } catch { XCTAssertEqual(error as? WebAdapterError, .invalidTarget) }
        XCTAssertEqual(misreportingEdge.captures.count, 1)
        XCTAssertTrue(chrome.captures.isEmpty)
        XCTAssertTrue(chrome.commands.isEmpty)
    }

    @MainActor func testOriginalCaptureFailureNeverRecapturesLaterForeground() async throws {
        for synchronous in [true, false] {
            let chrome = RecordingApplicationExecutor(chromeID), edge = RecordingApplicationExecutor(edgeID)
            let barrier = CaptureBarrier(); edge.barrier = barrier
            if synchronous { edge.captureError = .nativeSelectionChanged }
            else { edge.completionError = .captureSuperseded }
            var current: String? = edgeID
            let bridge = ApplicationWebExecutor(executors: [chromeID: chrome, edgeID: edge], foreground: { current })
            do {
                let capture = try bridge.targetForClick(program: program)
                current = chromeID
                barrier.release()
                _ = try await capture.value
                XCTFail("Lost original capture must fail")
            } catch {
                XCTAssertEqual(error as? WebAdapterError, synchronous ? .nativeSelectionChanged : .captureSuperseded)
            }
            XCTAssertEqual(edge.capturePrograms.count, 1)
            XCTAssertTrue(chrome.capturePrograms.isEmpty)
            XCTAssertTrue(chrome.commands.isEmpty)
        }
    }

    @MainActor func testCancelledOriginalClickCancelsItsCaptureWithoutSelectingLaterHost() async throws {
        let chrome = RecordingApplicationExecutor(chromeID), edge = RecordingApplicationExecutor(edgeID)
        let barrier = CaptureBarrier(); edge.barrier = barrier
        var current: String? = edgeID
        let bridge = ApplicationWebExecutor(executors: [chromeID: chrome, edgeID: edge], foreground: { current })
        let capture = try bridge.targetForClick(program: program)
        await barrier.waitUntilEntered()
        current = chromeID
        capture.cancel()
        barrier.release()
        do { _ = try await capture.value; XCTFail("Cancelled click must not publish a lease") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try XCTUnwrap(edge.captures.first).isCancelled)
        XCTAssertEqual(edge.captures.count, 1)
        XCTAssertTrue(chrome.capturePrograms.isEmpty)
        XCTAssertTrue(chrome.commands.isEmpty)
    }

    @MainActor func testCaptureCommandCancellationPropagatesToOriginalClickTask() async throws {
        let chrome = RecordingApplicationExecutor(chromeID), edge = RecordingApplicationExecutor(edgeID)
        let barrier = CaptureBarrier(); edge.barrier = barrier
        var current: String? = edgeID
        let bridge = ApplicationWebExecutor(executors: [chromeID: chrome, edgeID: edge], foreground: { current })
        let program = program
        let command = Task { try await bridge.execute(.init(action: .captureTarget), program: program) }
        await barrier.waitUntilEntered()
        current = chromeID
        command.cancel()
        barrier.release()
        do { _ = try await command.value; XCTFail("Cancelled capture command must not publish a lease") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try XCTUnwrap(edge.captures.first).isCancelled)
        XCTAssertEqual(edge.captures.count, 1)
        XCTAssertTrue(chrome.capturePrograms.isEmpty)
        XCTAssertTrue(chrome.commands.isEmpty)
    }

    @MainActor func testCaptureCommandEncodesOriginalLeaseWithoutUsingGenericHostExecute() async throws {
        let edge = RecordingApplicationExecutor(edgeID)
        let bridge = ApplicationWebExecutor(executors: [edgeID: edge], foreground: { self.edgeID })
        let data = try await bridge.execute(.init(action: .captureTarget), program: program)
        XCTAssertEqual(try JSONDecoder().decode(TargetLease.self, from: data), edge.target)
        XCTAssertEqual(edge.captures.count, 1)
        XCTAssertTrue(edge.commands.isEmpty)
    }

    @MainActor func testOriginalEdgeCommandFailureNeverFallsBackToChrome() async throws {
        let chrome = RecordingApplicationExecutor(chromeID), edge = RecordingApplicationExecutor(edgeID)
        edge.executionError = .nativeEventFailed(-1712)
        let bridge = ApplicationWebExecutor(executors: [chromeID: chrome, edgeID: edge], foreground: { self.chromeID })
        for action in [WebBridgeAction.commit, .observe] {
            do {
                _ = try await bridge.execute(.init(action: action, target: edge.target), program: program)
                XCTFail("Lost Edge reply must not use another host")
            } catch { XCTAssertEqual(error as? WebAdapterError, .nativeEventFailed(-1712)) }
        }
        XCTAssertEqual(edge.commands.map(\.action), [.commit, .observe])
        XCTAssertTrue(chrome.commands.isEmpty)
        XCTAssertTrue(chrome.capturePrograms.isEmpty)
    }
}
