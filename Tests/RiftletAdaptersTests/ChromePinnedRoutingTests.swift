import XCTest
import RiftletCore
@testable import RiftletAdapters

final class ChromePinnedRoutingTests: XCTestCase {
    func testColdClickSelectsVisibleChromeWindowWithoutAnyEarlierCapture() {
        // Two Chrome processes can coexist. Desktop z-order, not process-list
        // order or a prior page ACK, identifies the user's visible browser.
        XCTAssertEqual(ChromeReceiverSelection.choose(frontmost: nil, lastForeground: nil,
            visibleWindowOwners: [900, 20, 10], running: [10, 20]), 20)
        XCTAssertEqual(ChromeReceiverSelection.choose(frontmost: nil, lastForeground: nil,
            visibleWindowOwners: [], running: [10]), 10)
        XCTAssertNil(ChromeReceiverSelection.choose(frontmost: nil, lastForeground: nil,
            visibleWindowOwners: [], running: [10, 20]))
    }

    func testClickUsesLastActualChromeAfterThumbnailChangesApplicationFocus() {
        XCTAssertEqual(ChromeReceiverSelection.choose(frontmost: 900, lastForeground: 20,
            visibleWindowOwners: [10, 20], running: [10, 20]), 20)
        XCTAssertEqual(ChromeReceiverSelection.choose(frontmost: 10, lastForeground: 20,
            visibleWindowOwners: [20, 10], running: [10, 20]), 10)
        // A dead remembered process cannot displace a current visible window.
        XCTAssertEqual(ChromeReceiverSelection.choose(frontmost: nil, lastForeground: 30,
            visibleWindowOwners: [20, 10], running: [10, 20]), 20)
    }

    func testNativeSnapshotDetectsTabWindowAndSameTabConversationChanges() throws {
        let original = try ChromeClickRoute(window: "11", tab: "12", url: "https://chatgpt.com/c/original")
        XCTAssertNotEqual(original, try ChromeClickRoute(window: "13", tab: "12", url: original.address))
        XCTAssertNotEqual(original, try ChromeClickRoute(window: "11", tab: "13", url: original.address))
        XCTAssertNotEqual(original, try ChromeClickRoute(window: "11", tab: "12", url: "https://chatgpt.com/c/next"))
        XCTAssertNotEqual(original, try ChromeClickRoute(window: "11", tab: "12", url: "https://other.example/c/original"))
    }

    func testSnapshotHasNoNewChatOrProjectPathWhitelist() throws {
        for path in ["/", "/c/ordinary", "/g/project/project", "/g/project/c/conversation", "/future-chat-route"] {
            let route = try ChromeClickRoute(window: "1", tab: "2", url: "https://chatgpt.com" + path)
            XCTAssertEqual(route.address, "https://chatgpt.com" + path)
        }
        // The page program checks its supported service and usable composer.
        // Native addressing does not duplicate a historical URL allowlist.
        XCTAssertNoThrow(try ChromeClickRoute(window: "1", tab: "2", url: "https://fixture.example/chat"))
    }

    func testSnapshotIgnoresNonNavigatingURLDecorations() throws {
        let original = try ChromeClickRoute(window: "11", tab: "12", url: "https://chatgpt.com/c/chat")
        XCTAssertEqual(original, try ChromeClickRoute(window: "11", tab: "12",
            url: "https://CHATGPT.COM:443/c/chat?model=changed#attachment"))
        XCTAssertEqual(try ChromeClickRoute(window: "11", tab: "12", url: "https://chatgpt.com"),
            try ChromeClickRoute(window: "11", tab: "12", url: "https://chatgpt.com/"))
        for url in ["javascript:void(0)", "file:///tmp/chat", "about:blank", "not a URL"] {
            XCTAssertThrowsError(try ChromeClickRoute(window: "11", tab: "12", url: url))
        }
    }

    func testSelectionIsCheckedAtCaptureValidationAndActualInput() {
        for action in [WebBridgeAction.captureTarget, .validate, .commit] {
            XCTAssertTrue(ChromeCommandRouting.requiresSelectionCheck(action))
        }
        // Staging bytes does not input files. Rechecking active selection for
        // every chunk would add native round trips without protecting input.
        // Historical observation also keeps its original address after a switch.
        for action in [WebBridgeAction.begin, .chunk, .observe, .discard] {
            XCTAssertFalse(ChromeCommandRouting.requiresSelectionCheck(action))
        }
    }

    @MainActor func testObsoletePinCommandCannotEnterTheNativeTransport() async throws {
        let executor = ChromeAppleEventsExecutor()
        let program = WebPageProgram(sourceID: "unused-pin", functionSource: "function(){return null}")
        do {
            _ = try await executor.execute(WebBridgeCommand(action: .pinTarget), program: program)
            XCTFail("Obsolete pin route was accepted")
        } catch {
            XCTAssertEqual(error as? WebAdapterError, .invalidRequest)
        }
    }
}
