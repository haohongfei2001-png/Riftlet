import XCTest
import RiftletCore
@testable import RiftletAdapters

@MainActor private final class PendingProbe: WebClickTargetPinning {
    var calls = 0
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data { calls += 1; return Data() }
    func pinTargetAtPress(program: WebPageProgram, eventUptime: TimeInterval) throws -> TargetLease { calls += 1; throw WebAdapterError.invalidTarget }
    func prepareClickAtPress(assetID: UUID, program: WebPageProgram, eventUptime: TimeInterval) throws -> PendingWebClick { calls += 1; throw WebAdapterError.invalidTarget }
    func resolveClick(_ click: PendingWebClick, program: WebPageProgram) async throws -> TargetLease { calls += 1; throw WebAdapterError.invalidTarget }
}
final class PendingClickAdmissionTests: XCTestCase {
    @MainActor func testNewMechanismCannotRunOnOrdinaryCandidateOrDisabledSources() async {
        let executor = PendingProbe()
        var modes = [WebAdapterMode.disabled, .ordinarySystemScreenshot, .systemScreenshotCandidate]
        #if !RIFTLET_PENDING_CLICK_LOCAL
        modes.append(.syntheticDevelopment)
        #endif
        for mode in modes {
            let adapter = WebAttachmentAdapter(mediaDirectory: URL(fileURLWithPath:"/unused"), executor: executor,
                program: WebPageProgram(sourceID:"test",functionSource:"function(){}"),mode:mode)
            XCTAssertThrowsError(try adapter.prepareClickAtPress(assetID:UUID(),eventUptime:1)) { XCTAssertEqual($0 as? WebAdapterError,.disabled) }
            let click = PendingWebClick(assetID:UUID(),session:"p",window:"1",tab:"2",documentWitness:UUID(),eventUptime:1,routeFrozenUptime:1.01)
            do { _ = try await adapter.resolveClick(click); XCTFail("non-synthetic resolution") }
            catch { XCTAssertEqual(error as? WebAdapterError,.disabled) }
        }
        XCTAssertEqual(executor.calls,0)
    }
}
