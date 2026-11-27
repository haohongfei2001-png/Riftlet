import Foundation
import JavaScriptCore
import RiftletCore
import XCTest
@testable import RiftletAdapters

final class SafariTabHostTests: XCTestCase {
    private let token = UUID(uuidString: "243df900-f586-4daf-a2c9-f3992ff84c37")!

    func testTabAddressBindsPositionAndActualDocument() throws {
        let original = SafariTabAddress(position: 2, document: token)
        XCTAssertEqual(SafariTabAddress(serialized: original.serialized), original)
        XCTAssertTrue(AttachmentBrowser.safari.acceptsNativeTab(original.serialized))
        XCTAssertFalse(AttachmentBrowser.chrome.acceptsNativeTab(original.serialized))
        for wrong in ["2", "safari:0:", "safari:02:" + token.uuidString.lowercased(),
                      "safari:2:" + token.uuidString, "safari:2:invalid"] {
            XCTAssertFalse(AttachmentBrowser.safari.acceptsNativeTab(wrong))
        }
    }

    func testChangingDocumentOrRootAtSameURLDoesNotEnterOriginalCommand() throws {
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        var top=globalThis, self=globalThis, location={href:'https://claude.ai/new'};
        var doc=()=>({documentElement:{},visibilityState:'visible',hasFocus:()=>true});
        var document=doc(), inputCount=0;
        """)
        let install = try SafariDocumentBinding.prepare(url: "https://claude.ai/new", token: token)
        let input = SafariDocumentBinding.guarded("++inputCount", document: token)
        XCTAssertEqual(js.evaluateScript(install)?.toString(), token.uuidString.lowercased())
        XCTAssertEqual(js.evaluateScript(SafariDocumentBinding.readSelected)?.toString(), token.uuidString.lowercased())
        XCTAssertEqual(js.evaluateScript(input)?.toInt32(), 1)
        js.evaluateScript("var originalDocument=document, originalRoot=document.documentElement; document=doc()")
        XCTAssertEqual(js.evaluateScript(SafariDocumentBinding.readSelected)?.toString(), "")
        XCTAssertEqual(js.evaluateScript(input)?.toString(), SafariDocumentBinding.mismatch)
        js.evaluateScript("document.documentElement=originalRoot")
        XCTAssertEqual(js.evaluateScript(input)?.toString(), SafariDocumentBinding.mismatch)
        js.evaluateScript("document=originalDocument; document.documentElement={}")
        XCTAssertEqual(js.evaluateScript(input)?.toString(), SafariDocumentBinding.mismatch)
        XCTAssertEqual(js.evaluateScript("inputCount")?.toInt32(), 1)
        XCTAssertNil(js.exception)
    }

    func testAnotherRouteOrBackgroundTabCannotBePrepared() throws {
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        var top=globalThis,self=globalThis,location={href:'https://claude.ai/new'};
        var document={documentElement:{},visibilityState:'visible',hasFocus:()=>false};
        """)
        let install = try SafariDocumentBinding.prepare(url: "https://claude.ai/new", token: token)
        XCTAssertEqual(js.evaluateScript(install)?.toString(), "")
        js.evaluateScript("document.hasFocus=()=>true; location.href='https://claude.ai/chat/another'")
        XCTAssertEqual(js.evaluateScript(install)?.toString(), "")
        js.evaluateScript("location.href='https://claude.ai/new'; document.visibilityState='hidden'")
        XCTAssertEqual(js.evaluateScript(install)?.toString(), "")
        XCTAssertEqual(js.evaluateScript(SafariDocumentBinding.readSelected)?.toString(), "")
        XCTAssertNil(js.exception)
    }

    func testProviderNavigationRetainsSemanticQueryAndFragment() throws {
        let tab = SafariTabAddress(position: 3, document: token).serialized
        let url = "https://claude.ai/chat/123?draft=one#original"
        let original = try ChromeClickRoute.conversation(window: "17", tab: tab, url: url)
        XCTAssertEqual(original.address, url)
        XCTAssertNotEqual(original, try ChromeClickRoute.conversation(window: "17", tab: tab,
            url: "https://claude.ai/chat/123?draft=two#original"))
        XCTAssertNotEqual(original, try ChromeClickRoute.conversation(window: "17", tab: tab,
            url: "https://claude.ai/chat/123?draft=one#other"))
        XCTAssertThrowsError(try ChromeClickRoute.conversation(window: "17", tab: tab, url: "https://claude.ai/settings"))
        XCTAssertThrowsError(try ChromeClickRoute.conversation(window: "17", tab: tab, url: "https://claude.ai.example/new"))
        XCTAssertEqual(try ChromeClickRoute.conversation(window: "17", tab: tab,
            url: "https://chatgpt.com/?temporary-chat=true").address, "https://chatgpt.com/")
    }

    func testPrivateQATabRequiresRecognizedOriginalBrowserAndDocument() throws {
        let tab = SafariTabAddress(position: 3, document: token).serialized
        let data = ["applicationID":AttachmentBrowser.safari.rawValue, "session":"safari-kernel-v1:1781:99:34",
                    "windowID":"17", "tabID":tab]
        func request(_ override: [String:String] = [:]) throws -> QAOriginalBrowserTab {
            let bytes = try JSONEncoder().encode(data.merging(override) { _, replacement in replacement })
            return try QAOriginalBrowserTab.decode(String(decoding: bytes, as: UTF8.self))
        }
        XCTAssertEqual(try request().expectedURL, QAOriginalBrowserTab.temporaryChat)
        XCTAssertEqual(try request(["url":"https://claude.ai/new"]).expectedURL, "https://claude.ai/new")
        XCTAssertThrowsError(try request(["tabID":"3"]))
        XCTAssertThrowsError(try request(["session":"edge-kernel-v1:1781:99:34"]))
        XCTAssertThrowsError(try request(["url":"https://chatgpt.com/c/private"]))
        XCTAssertThrowsError(try request(["url":"https://user@claude.ai/new"]))
    }

    func testProviderCaptureRequiresCorrectLogicalDraftAndNativeBrowser() throws {
        let epoch = UUID().uuidString.lowercased()
        let tab = SafariTabAddress(position: 3, document: token).serialized
        func capture(_ provider: ConversationProvider, _ generation: String, _ expected: ConversationProvider) throws -> String {
            let target = TargetLease(adapterID: ConversationProvider.claude.adapterID, surface: .webChat,
                applicationID: AttachmentBrowser.safari.rawValue, sessionID: "session", windowID: "17", tabID: tab,
                documentID: "document", composerID: "composer", draftGeneration: epoch,
                logicalDraftIdentity: .init(profileID:"conversation-composer-20261125-v1", id:provider.rawValue + ":" + generation))
            return try NativeCaptureProof.digest(JSONEncoder().encode(target), session:"session", window:"17", tab:tab,
                applicationID:AttachmentBrowser.safari.rawValue, expectedProvider:expected)
        }
        XCTAssertEqual(try capture(.claude, epoch, .claude).count, 64)
        XCTAssertThrowsError(try capture(.gemini, epoch, .claude))
        XCTAssertThrowsError(try capture(.claude, UUID().uuidString, .claude))
        XCTAssertThrowsError(try capture(.claude, epoch, .gemini))
        XCTAssertThrowsError(try capture(.claude, epoch, .chatgpt))
    }

    func testSafariScriptSettingIsSeparateFromSystemAutomation() {
        func result(_ error: Int32, javaScript: Bool = true) -> ChromeSetupConnectionProbe.Result {
            func fail() throws -> String { throw WebAdapterError.nativeEventFailed(error) }
            return ChromeSetupConnectionProbe.evaluate(read: { try javaScript ? SafariTabEvents.javaScriptEvent(fail) : fail() },
                                                       stillCurrent: { true }, browser: .safari)
        }
        XCTAssertEqual(result(8), .javaScriptDisabled)
        XCTAssertEqual(result(8, javaScript: false), .unavailable)
        XCTAssertEqual(result(-1743), .permissionDenied)
        XCTAssertEqual(result(-1744), .permissionNotRequested)
        XCTAssertEqual(result(12), .unavailable)
    }
}
