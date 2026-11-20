import Foundation
import JavaScriptCore
import XCTest
@testable import RiftletAdapters

final class ProviderDiscoveryPinTests: XCTestCase {
    private let url = "https://gemini.google.com/app"

    private func context() throws -> JSContext {
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        var window=this, top=this, self=this, hooks={}, pending=[], reads=0, closes=0, timer;
        var listen=(event,handler)=>{hooks[event]=handler};
        var location={href:'https://gemini.google.com/app'};
        var document={documentElement:{}, visibilityState:'visible', hasFocus:()=>true, addEventListener:listen};
        var navigation={currentEntry:{id:'original'}, addEventListener:listen};
        var addEventListener=listen, setTimeout=handler=>{timer=handler}, clearTimeout=()=>{};
        class AbortController {abort(){}}
        class MutationObserver {observe(){} disconnect(){} takeRecords(){return pending.splice(0)}}
        var provider={inspect:()=>{reads++;return 'editor_and_upload_action'},
          pin:id=>({inspectAttachmentEntry:()=> 'menu_owned_input_observed',close:()=>{closes++}})};
        """)
        return js
    }

    func testReadRequiresOriginalPinAndCanOnlyInspectOnce() throws {
        let pin = ProviderDiscoveryPin(id: UUID()), js = try context()
        let bind = try pin.bind(address: url)
        let read = pin.read(program: "provider")
        XCTAssertEqual(js.evaluateScript(read)?.toString(), "refused")
        XCTAssertEqual(js.evaluateScript(bind)?.toString(), "bound")
        XCTAssertEqual(js.evaluateScript(bind)?.toString(), "refused")
        XCTAssertEqual(js.evaluateScript(ProviderDiscoveryPin(id: UUID()).read(program: "provider"))?.toString(), "refused")
        XCTAssertEqual(js.evaluateScript(read)?.toString(), "editor_and_upload_action|menu_owned_input_observed")
        XCTAssertEqual(js.evaluateScript(read)?.toString(), "refused")
        XCTAssertEqual(js.evaluateScript("reads+','+closes")?.toString(), "1,1")
        XCTAssertThrowsError(try pin.bind(address: url, maximumBytes: 64))
    }

    func testRouteFocusMutationsAndExpiryCannotInspectALaterDocument() throws {
        let pin = ProviderDiscoveryPin(id: UUID())
        for change in ["location.href += '?other'", "navigation.currentEntry.id='changed'", "hooks.navigate()",
                       "hooks.currententrychange()", "hooks.blur()", "hooks.visibilitychange()", "hooks.pagehide()",
                       "document.documentElement={}", "document.hasFocus=()=>false", "pending.push({})", "timer()"] {
            let js = try context()
            XCTAssertEqual(js.evaluateScript(try pin.bind(address: url))?.toString(), "bound", change)
            js.evaluateScript(change)
            XCTAssertEqual(js.evaluateScript(pin.read(program: "provider"))?.toString(), "refused", change)
            XCTAssertEqual(js.evaluateScript("reads")?.toInt32(), 0, change)
        }
    }

    func testOnlyClosedReadOnlyResultsLeaveTheBrowser() throws {
        let menu = try ReadOnlyProviderResult(provider: "gemini", reply: "editor_and_upload_action|menu_owned_input_observed")
        XCTAssertEqual(menu.attachmentEntry, "menu_owned_input_observed")
        XCTAssertNoThrow(try ReadOnlyProviderResult(provider: "gemini", reply: "owned_input|direct_owned_input"))
        XCTAssertNoThrow(try ReadOnlyProviderResult(provider: "gemini", reply: "owner_unavailable|notReached"))
        for invalid in ["refused", "complete|menu_owned_input_observed", "owned_input|menu_owned_input_observed",
                        "editor_and_upload_action|private text", "editor_and_upload_action|original_surface_changed"] {
            XCTAssertThrowsError(try ReadOnlyProviderResult(provider: "gemini", reply: invalid))
        }
    }
}
