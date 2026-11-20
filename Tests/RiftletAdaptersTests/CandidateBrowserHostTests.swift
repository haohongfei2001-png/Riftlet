import ApplicationServices
import Carbon
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class CandidateBrowserHostTests: XCTestCase {
    @MainActor func testUnprovedHostsCannotEnqueueAnyPinOrUseTheStableRegistry() async throws {
        let bundles = ["com.apple.Safari", "org.mozilla.firefox", "com.brave.Browser"]
        let profile = try ProviderProfile(id: "fixture", revision: 1, program: Data("test".utf8))
        let route = ProviderRoute(profile: profile, route: DraftRoute(identity: "test", surface: "test", mode: "test"))
        for bundle in bundles {
            let host = try XCTUnwrap(CandidateBrowserHosts.host(for: bundle))
            XCTAssertNil(AttachmentBrowser(rawValue: bundle))
            XCTAssertFalse(host.capabilities.supportsPin)
            XCTAssertThrowsError(try BoundClick.capture(using: host, providers: []))
            let click = NativeClick(bundle: bundle, pid: 1, processBirth: "p", session: "s", window: "w", tab: "t",
                                    url: URL(fileURLWithPath: "/fixture"), generation: UUID(), uptime: 0)
            XCTAssertThrowsError(try host.enqueuePin(click: click, route: route, maximumBytes: 64))
        }
        XCTAssertNil(CandidateBrowserHosts.host(for: "com.apple.SafariTechnologyPreview"))
    }

    @MainActor func testBraveSettingReadKeepsJSDisabledSeparateFromOSConsentAndWrongReply() {
        XCTAssertEqual(try BraveBrowserHost.scriptRead(status: 12, reply: nil), .browserSettingDisabled)
        XCTAssertEqual(try BraveBrowserHost.scriptRead(status: OSStatus(errAEEventWouldRequireUserConsent), reply: nil), .automationRequired)
        XCTAssertThrowsError(try BraveBrowserHost.scriptRead(status: 0, reply: ""))
        XCTAssertThrowsError(try BraveBrowserHost.scriptRead(status: OSStatus(errAETimeout), reply: nil))
        XCTAssertEqual(try BraveBrowserHost.scriptRead(status: 0, reply: "RIFTLET_SCRIPT_AVAILABLE"), .available)
        XCTAssertEqual(CandidateReceiver.automationState(OSStatus(errAEEventNotPermitted)), .permissionRequired)
        XCTAssertEqual(CandidateReceiver.automationState(OSStatus(errAETimeout)), .unavailable)
    }

    func testAXSameURLReplacementOrSwitchOnceObservedCannotBecomeEvidenceAfterABA() {
        func objects(_ session: String = "original", window: Int32 = 1301, web: Int32 = 1302, focus: Int32 = 1303) -> BrowserAXObjects {
            func handle(_ key: Int32) -> MacAXElement { MacAXElement(AXUIElementCreateApplication(key)) }
            return BrowserAXObjects(receiverSession: session, window: handle(window), webArea: handle(web), focusedElement: handle(focus))
        }
        let original = objects()
        let alternatives: [BrowserAXObjects?] = [nil, objects("relaunched"), objects(window: 1401),
                                               objects(web: 1402), objects(focus: 1403)]
        for changed in alternatives {
            var observer = BrowserAXObservation(original: original)
            XCTAssertEqual(observer.compare(original), .sameExposedObjectsOnly)
            XCTAssertEqual(observer.compare(changed), .retired)
            XCTAssertEqual(observer.compare(original), .retired)
        }
    }
}
