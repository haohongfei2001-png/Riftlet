import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class CaptureDiagnosticsTests: XCTestCase {
    private let program = WebPageProgram(sourceID: "synthetic-capture-diagnostics",
        functionSource: "function () { return null; }")
    private func context() -> CaptureInvocationContext {
        CaptureInvocationContext(armAttemptID: UUID(), hostEpoch: UUID())
    }
    private func adapter(_ executor: DiagnosticCaptureBridge, enabled: Bool = true) -> WebAttachmentAdapter {
        WebAttachmentAdapter(mediaDirectory: FileManager.default.temporaryDirectory,
            executor: executor, program: program, mode: enabled ? .syntheticDevelopment : .disabled)
    }

    func testHostInvocationMetadataIsNeverEncodedIntoThePageCommand() throws {
        let invocation = context()
        let command = WebBridgeCommand(action: .captureTarget, captureInvocation: invocation)
        XCTAssertEqual(command.captureInvocation, invocation)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(command), try encoder.encode(WebBridgeCommand(action: .captureTarget)))
        XCTAssertEqual(String(decoding: try encoder.encode(command), as: UTF8.self), #"{"action":"captureTarget"}"#)
    }

    func testDiagnosticAndOrdinaryCaptureKeepOneCommandAndTheExactSameLease() async throws {
        let bridge = DiagnosticCaptureBridge()
        let client = adapter(bridge), invocation = context()
        let before = ProcessInfo.processInfo.systemUptime
        let captured = try await client.captureTargetWithDiagnostics(context: invocation)
        let after = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(captured.target, DiagnosticCaptureBridge.target)
        XCTAssertEqual(captured.context, invocation)
        XCTAssertTrue(captured.adapterValidatedUptime.isFinite)
        XCTAssertGreaterThanOrEqual(captured.adapterValidatedUptime, before)
        XCTAssertLessThanOrEqual(captured.adapterValidatedUptime, after)
        XCTAssertEqual(captured.targetDigest, try NativeCaptureProof.digest(
            JSONEncoder().encode(captured.target), session: captured.target.sessionID,
            window: captured.target.windowID, tab: try XCTUnwrap(captured.target.tabID)))
        let original = try await client.captureTarget()
        XCTAssertEqual(original, captured.target)
        let commands = await bridge.commands()
        XCTAssertEqual(commands.map(\.action), [.captureTarget, .captureTarget])
        XCTAssertEqual(commands[0].captureInvocation, invocation)
        XCTAssertNil(commands[1].captureInvocation)
    }

    func testConcurrentCapturesOfTheSameLeaseCannotJoinByDigestOrSwapRequestIdentity() async throws {
        let bridge = DiagnosticCaptureBridge(), first = context(), second = context()
        let client = adapter(bridge)
        async let a = client.captureTargetWithDiagnostics(context: first)
        async let b = client.captureTargetWithDiagnostics(context: second)
        let (one, two) = try await (a, b)
        XCTAssertEqual(one.context, first); XCTAssertEqual(two.context, second)
        XCTAssertEqual(one.targetDigest, two.targetDigest)
        XCTAssertNotEqual(one.context.requestID, two.context.requestID)
        let commands = await bridge.commands()
        XCTAssertEqual(commands.map(\.action), [.captureTarget, .captureTarget])
        XCTAssertEqual(Set(commands.compactMap { $0.captureInvocation?.requestID }),
                       Set([first.requestID, second.requestID]))
    }

    func testDisabledDiagnosticCaptureNeverReachesTheExecutor() async throws {
        let bridge = DiagnosticCaptureBridge()
        do {
            _ = try await adapter(bridge, enabled: false).captureTargetWithDiagnostics(context: context())
            XCTFail("Diagnostic capture enabled a disabled adapter")
        } catch WebAdapterError.disabled {}
        let commands = await bridge.commands()
        XCTAssertTrue(commands.isEmpty)
    }

    func testInvalidTargetAndNativeFailureDoNotReturnDiagnosticsOrRecapture() async throws {
        for behavior in [DiagnosticCaptureBridge.Behavior.invalidTarget, .nativeFailure] {
            let bridge = DiagnosticCaptureBridge(behavior: behavior), invocation = context()
            do {
                _ = try await adapter(bridge).captureTargetWithDiagnostics(context: invocation)
                XCTFail("Invalid capture manufactured a diagnostic acknowledgement")
            } catch {
                XCTAssertEqual(error as? WebAdapterError,
                    behavior == .invalidTarget ? .invalidTarget : .nativeSelectionChanged)
            }
            let commands = await bridge.commands()
            XCTAssertEqual(commands.map(\.action), [.captureTarget])
            XCTAssertEqual(commands.first?.captureInvocation, invocation)
        }
    }
}

private actor DiagnosticCaptureBridge: WebBridgeExecutor {
    enum Behavior { case valid, invalidTarget, nativeFailure }
    static let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
        applicationID: "com.google.Chrome", sessionID: "synthetic-pid:launch", windowID: "1", tabID: "2",
        documentID: "synthetic-document", composerID: "synthetic-composer", draftGeneration: "synthetic-generation")
    private let behavior: Behavior
    private var recorded: [WebBridgeCommand] = []
    init(behavior: Behavior = .valid) { self.behavior = behavior }
    func commands() -> [WebBridgeCommand] { recorded }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        recorded.append(command)
        await Task.yield()
        if behavior == .nativeFailure { throw WebAdapterError.nativeSelectionChanged }
        let target = behavior == .invalidTarget ? TargetLease(adapterID: "other-adapter", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "synthetic-pid:launch", windowID: "1", tabID: "2",
            documentID: "synthetic-document", composerID: "synthetic-composer", draftGeneration: "synthetic-generation") : Self.target
        return try JSONEncoder().encode(target)
    }
}
