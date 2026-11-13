import XCTest
@testable import RiftletAdapters

final class ChromeSetupConnectionProbeTests: XCTestCase {
    func testExactReplyFromTheSameProcessIsRequired() {
        XCTAssertEqual(ChromeSetupConnectionProbe.evaluate(read: { "Riftlet" }, stillCurrent: { true }), .ready)
        XCTAssertEqual(ChromeSetupConnectionProbe.evaluate(read: { "Riftlet" }, stillCurrent: { false }), .unavailable)
        XCTAssertEqual(ChromeSetupConnectionProbe.evaluate(read: { "" }, stillCurrent: { true }), .unavailable)
    }

    func testMenuDisabledAndDeniedAutomationHaveDifferentRecovery() {
        for (code, expected): (Int32, ChromeSetupConnectionProbe.Result) in
            [(12, .javaScriptDisabled), (-1743, .permissionDenied), (-1728, .noWindow), (-1712, .unavailable)] {
            XCTAssertEqual(ChromeSetupConnectionProbe.evaluate(read: { throw WebAdapterError.nativeEventFailed(code) },
                stillCurrent: { true }), expected)
        }
    }
}
