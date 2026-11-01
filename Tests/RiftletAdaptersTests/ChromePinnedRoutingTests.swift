import XCTest
import RiftletCore
@testable import RiftletAdapters

final class ChromePinnedRoutingTests: XCTestCase {
    func testPressSnapshotCannotBorrowANewDocumentPublishedDuringNativeRead() {
        func lease(_ document: String, session: String = "A") -> TargetLease {
            .init(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
                  sessionID: session, windowID: "11", tabID: "12", documentID: document,
                  composerID: "editor", draftGeneration: document)
        }
        let cache = ObservedClickRoutes()
        let empty = cache.snapshot()
        cache.recordRoute(session: "A", window: "11", tab: "12", uptime: 1)
        cache.record(lease("original"), uptime: 2)
        let press = cache.snapshot()
        cache.record(lease("later"), uptime: 4)
        XCTAssertNil(empty.target(session: "A", window: "11", tab: "12", eventUptime: 3))
        XCTAssertEqual(press.target(session: "A", window: "11", tab: "12", eventUptime: 3), lease("original"))
        XCTAssertEqual(cache.snapshot().target(session: "A", window: "11", tab: "12", eventUptime: 5), lease("later"))
        XCTAssertNil(press.target(session: "reused-PID-new-birth", window: "11", tab: "12", eventUptime: 3))
        XCTAssertNil(press.target(session: "A", window: "other-window", tab: "12", eventUptime: 3))
        XCTAssertNil(press.target(session: "A", window: "11", tab: "other-tab", eventUptime: 3))
    }

    func testRouteObservedAfterPressOrCachedOtherTabCannotSubstituteForOriginal() {
        let cache = ObservedClickRoutes()
        let a = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "A", windowID: "1", tabID: "2", documentID: "doc", composerID: "c", draftGeneration: "g")
        cache.record(a, uptime: 1)
        cache.recordRoute(session: "A", window: "1", tab: "2", uptime: 2)
        let press = cache.snapshot()
        XCTAssertNil(press.target(session: "A", window: "1", tab: "3", eventUptime: 3))
        cache.recordRoute(session: "A", window: "1", tab: "2", uptime: 4)
        XCTAssertNil(cache.snapshot().target(session: "A", window: "1", tab: "2", eventUptime: 3))
    }

    func testPinnedReplyMustPreserveEveryExpectedIdentityField() throws {
        let original = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "A", windowID: "1", tabID: "2", documentID: "doc", composerID: "c", draftGeneration: "g")
        let id = UUID()
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        fields["clickBindingID"] = id.uuidString
        let valid = try JSONSerialization.data(withJSONObject: fields)
        XCTAssertEqual(try NativeCaptureProof.pinnedTarget(valid, expected: original, pinID: id).clickBindingID, id)
        for key in ["sessionID", "windowID", "tabID", "documentID", "composerID", "draftGeneration", "clickBindingID"] {
            var bad = fields; bad[key] = key == "clickBindingID" ? UUID().uuidString : "changed"
            XCTAssertThrowsError(try NativeCaptureProof.pinnedTarget(JSONSerialization.data(withJSONObject: bad), expected: original, pinID: id))
        }
    }

    func testOnlyExplicitPinGetsBackgroundInputAndCaptureNeverUsesIt() {
        func target(_ pin: UUID?) -> TargetLease {
            .init(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
                  sessionID: "A", windowID: "11", tabID: "12", documentID: "A-doc",
                  composerID: "A-editor", draftGeneration: "A-draft", clickBindingID: pin)
        }
        for action in [WebBridgeAction.validate, .begin, .chunk, .commit] {
            XCTAssertTrue(ChromeCommandRouting.requiresForeground(action, target: target(nil)))
            XCTAssertFalse(ChromeCommandRouting.requiresForeground(action, target: target(UUID())))
        }
        for action in [WebBridgeAction.captureTarget, .pinTarget] {
            XCTAssertTrue(ChromeCommandRouting.requiresForeground(action, target: target(UUID())))
        }
        for action in [WebBridgeAction.observe, .discard] {
            XCTAssertFalse(ChromeCommandRouting.requiresForeground(action, target: target(nil)))
        }
    }
}
