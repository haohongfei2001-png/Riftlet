import XCTest
import AppKit
import RiftletCore
@testable import RiftletAdapters

final class ChromePinnedRoutingTests: XCTestCase {
    func testHistoryTabEnumerationMatchesAppleScriptAbsoluteOrdinal() throws {
        // The reference targets an in-process list. It sends no browser events.
        let script = try XCTUnwrap(NSAppleScript(source: "return a reference to every item of {1,2}"))
        var error: NSDictionary?
        let reference = script.executeAndReturnError(&error)
        XCTAssertNil(error)
        let selector = try XCTUnwrap(reference.forKeyword(AEKeyword(keyAEKeyData)))
        let native = try ChromeHistoryTabSelection.allTabsOrdinal()
        XCTAssertEqual(native.descriptorType, selector.descriptorType)
        XCTAssertEqual(native.data, selector.data)
    }

    func testProductionClickAcceptsOnlyCanonicalChatGPTOrigins() throws {
        for url in ["https://chatgpt.com/", "https://chat.openai.com:443/c/chat"] {
            XCTAssertNoThrow(try ChromeClickRoute.chatGPT(window: "11", tab: "12", url: url))
        }
        for url in ["https://example.org/", "https://chatgpt.com.example.org/",
                    "https://name@chatgpt.com/", "https://chatgpt.com:444/", "http://chatgpt.com/"] {
            XCTAssertThrowsError(try ChromeClickRoute.chatGPT(window: "11", tab: "12", url: url))
        }
    }

    func testNativeSnapshotDetectsTabWindowAndSameTabConversationChanges() throws {
        let original = try ChromeClickRoute(window: "11", tab: "12", url: "https://chatgpt.com/c/original")
        XCTAssertNotEqual(original, try ChromeClickRoute(window: "13", tab: "12", url: original.address))
        XCTAssertNotEqual(original, try ChromeClickRoute(window: "11", tab: "13", url: original.address))
        XCTAssertNotEqual(original, try ChromeClickRoute(window: "11", tab: "12", url: "https://chatgpt.com/c/next"))
        XCTAssertNotEqual(original, try ChromeClickRoute(window: "11", tab: "12", url: "https://other.example/c/original"))
    }

    func testSavedConversationLinksAcceptOnlyScopedUUIDPaths() throws {
        let id = UUID()
        for (path, expected) in [("/g/g-example/c/", id), ("/c/", id), ("/g//c/", nil), ("/g/%2F/c/", nil), ("/unrelated/c/", nil)] {
            let route = try ChromeClickRoute(window: "1", tab: "2", url: "https://chatgpt.com" + path + id.uuidString)
            XCTAssertEqual(route.historyConversationID, expected)
        }
    }

    func testRestartReadOnlyDiscoveryRejectsDifferentSavedChatAndCachedRoute() throws {
        let id = UUID(), other = UUID()
        let saved = try ChromeClickRoute.chatGPT(window: "1", tab: "2", url: "https://chatgpt.com/c/" + id.uuidString)
        let navigated = try ChromeClickRoute.chatGPT(window: "1", tab: "2", url: "https://chatgpt.com/c/" + other.uuidString)
        XCTAssertTrue(saved.matchesOriginal(route: nil, savedConversation: id))
        XCTAssertFalse(navigated.matchesOriginal(route: nil, savedConversation: id))
        XCTAssertFalse(navigated.matchesOriginal(route: saved, savedConversation: nil))
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

    func testCancellationCannotDispatchQueuedInputOrReopenCompletedSubmission() throws {
        let before = NativeCommandSubmission()
        before.cancel()
        XCTAssertThrowsError(try before.enter())

        let after = NativeCommandSubmission()
        try after.enter()
        after.cancel()
        XCTAssertThrowsError(try after.enter())
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
