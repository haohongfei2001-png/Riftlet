import XCTest
import RiftletCore
@testable import RiftletAdapters

final class ChromePinnedRoutingTests: XCTestCase {
    func testLastTargetSurvivesFocusLeavingChromeButNeverAnObservedTabChange() {
        let cache = ObservedClickRoutes()
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "original-process", windowID: "11", tabID: "12", documentID: "doc",
            composerID: "editor", draftGeneration: "draft")
        cache.recordRoute(session: target.sessionID, window: target.windowID, tab: "12", uptime: 1)
        cache.record(target, uptime: 2)
        // Foreground app changes do not choose another process/tab or erase the
        // saved native route. Pinning still rechecks these exact native IDs.
        XCTAssertEqual(cache.snapshot().lastTarget(eventUptime: 300), target)
        XCTAssertNil(cache.snapshot().lastTarget(eventUptime: 2))
        cache.recordRoute(session: target.sessionID, window: "11", tab: "13", uptime: 301)
        XCTAssertNil(cache.snapshot().lastTarget(eventUptime: 302))
        cache.recordRoute(session: target.sessionID, window: "11", tab: "12", uptime: 303)
        XCTAssertNil(cache.snapshot().lastTarget(eventUptime: 304))
    }
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
        cache.recordRoute(session: "A", window: "1", tab: "2", uptime: 1)
        cache.record(a, uptime: 2)
        let press = cache.snapshot()
        XCTAssertNil(press.target(session: "A", window: "1", tab: "3", eventUptime: 3))
        cache.recordRoute(session: "A", window: "1", tab: "3", uptime: 4)
        cache.recordRoute(session: "A", window: "1", tab: "2", uptime: 5)
        XCTAssertNil(cache.snapshot().target(session: "A", window: "1", tab: "2", eventUptime: 3))
    }

    func testReturningToARequiresANewCaptureAfterObservedB() {
        let cache = ObservedClickRoutes()
        let a = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "A", windowID: "1", tabID: "2", documentID: "doc", composerID: "c", draftGeneration: "g")
        cache.recordRoute(session: "A", window: "1", tab: "2", uptime: 1)
        cache.record(a, uptime: 2)
        let originalPress = cache.snapshot()
        cache.recordRoute(session: "A", window: "1", tab: "3", uptime: 4)
        // A late receipt from A cannot seed B's epoch.
        cache.record(a, uptime: 5)
        cache.recordRoute(session: "A", window: "1", tab: "2", uptime: 6)
        XCTAssertNil(cache.snapshot().target(session: "A", window: "1", tab: "2", eventUptime: 7))
        // A press frozen before the switch still means that original A.
        XCTAssertEqual(originalPress.target(session: "A", window: "1", tab: "2", eventUptime: 3), a)
        cache.record(a, uptime: 8)
        XCTAssertEqual(cache.snapshot().target(session: "A", window: "1", tab: "2", eventUptime: 9), a)
    }

    func testPressEvidenceMustStrictlyPredateTheEventWithoutExpiringAContinuousTarget() {
        let cache = ObservedClickRoutes()
        let a = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
            sessionID: "A", windowID: "1", tabID: "2", documentID: "doc", composerID: "c", draftGeneration: "g")
        cache.recordRoute(session: "A", window: "1", tab: "2", uptime: 1)
        cache.record(a, uptime: 2)
        let press = cache.snapshot()
        XCTAssertNil(press.target(session: "A", window: "1", tab: "2", eventUptime: 2))
        XCTAssertNil(press.target(session: "A", window: "1", tab: "2", eventUptime: .nan))
        XCTAssertNil(press.target(session: "A", window: "1", tab: "2", eventUptime: .infinity))
        XCTAssertEqual(press.target(session: "A", window: "1", tab: "2", eventUptime: 300), a)
        cache.recordRoute(session: "A", window: "1", tab: "2", uptime: 301)
        // The physical down was at 300; a same-route poll completing before its
        // callback must not discard the valid earlier target and route proof.
        XCTAssertEqual(cache.snapshot().target(session: "A", window: "1", tab: "2", eventUptime: 300), a)
        XCTAssertEqual(cache.snapshot().target(session: "A", window: "1", tab: "2", eventUptime: 302), a)
    }

    func testNativePressAgeUsesOnlyTheNativeClockAndRejectsDelayedOrReplayedEvents() {
        XCTAssertTrue(NativePressTiming.accepts(eventUptime: 100, startedUptime: 100))
        XCTAssertTrue(NativePressTiming.accepts(eventUptime: 100, startedUptime: 100.75))
        XCTAssertFalse(NativePressTiming.accepts(eventUptime: 100, startedUptime: 100.751))
        XCTAssertFalse(NativePressTiming.accepts(eventUptime: 100.01, startedUptime: 100))
        for invalid in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertFalse(NativePressTiming.accepts(eventUptime: invalid, startedUptime: 100))
            XCTAssertFalse(NativePressTiming.accepts(eventUptime: 100, startedUptime: invalid))
        }
    }

    func testNativePressProofIsExplicitAndBoundToOnePinWithoutPrivateContent() throws {
        let pinID = UUID()
        let command = WebBridgeCommand(action: .pinTarget, clickBindingID: pinID,
            nativePressProof: NativePressProof(clickBindingID: pinID))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as! [String: Any]
        let proof = try XCTUnwrap(encoded["nativePressProof"] as? [String: Any])
        XCTAssertEqual(Set(proof.keys), Set(["kind", "clickBindingID"]))
        XCTAssertEqual(proof["kind"] as? String, "observed-target-before-press")
        XCTAssertEqual(proof["clickBindingID"] as? String, pinID.uuidString)
        XCTAssertEqual(encoded["clickBindingID"] as? String, proof["clickBindingID"] as? String)
        for action in [WebBridgeAction.captureTarget, .pinTarget, .validate, .begin, .commit] {
            let ordinary = WebBridgeCommand(action: action)
            let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ordinary)) as! [String: Any]
            XCTAssertNil(fields["nativePressProof"])
        }
    }

    @MainActor func testAsyncExecutorCannotManufactureNativePressAuthority() async throws {
        let executor = ChromeAppleEventsExecutor()
        let program = WebPageProgram(sourceID: "proof-denial-test", functionSource: "function(){return null}")
        for action in [WebBridgeAction.captureTarget, .validate, .pinTarget] {
            let id = UUID()
            let command = WebBridgeCommand(action: action, clickBindingID: id,
                nativePressProof: NativePressProof(clickBindingID: id))
            do {
                _ = try await executor.execute(command, program: program)
                XCTFail("An asynchronous path accepted native press authority")
            } catch {
                XCTAssertEqual(error as? WebAdapterError, .invalidRequest)
            }
        }
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
