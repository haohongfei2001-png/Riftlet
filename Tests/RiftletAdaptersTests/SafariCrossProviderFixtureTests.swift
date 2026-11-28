import Foundation
import JavaScriptCore
import XCTest
@testable import RiftletAdapters

/// Owned JavaScriptCore documents only: never launches Safari or visits these URLs.
final class SafariCrossProviderFixtureTests: XCTestCase {
    func testForeignProviderReplacementDoesNotRunOriginalDispatchOrReceipt() throws {
        let original = try XCTUnwrap(JSContext())
        let foreign = try XCTUnwrap(JSContext())
        let id = UUID(uuidString: "243df900-f586-4daf-a2c9-f3992ff84c37")!
        let otherID = UUID(uuidString: "e70811ac-9091-4003-94b5-12163c815617")!
        let claude = "https://claude.ai/new"
        let gemini = "https://gemini.google.com/app"
        let setup = """
        var top=globalThis,self=globalThis;
        var document={documentElement:{},visibilityState:'visible',hasFocus:()=>true};
        var draft='unaltered user draft', attachments=1, dispatches=0, reads=0, sends=0;
        """
        original.evaluateScript(setup + "var location={href:'\(claude)'};")
        foreign.evaluateScript(setup + "var location={href:'\(gemini)'};")
        let lease = try SafariDocumentBinding.prepare(url: claude, token: id)
        XCTAssertEqual(original.evaluateScript(lease)?.toString(), id.uuidString.lowercased())
        XCTAssertEqual(foreign.evaluateScript(lease)?.toString(), "")
        // The foreign document has its own valid lease, like a tab that moved into the old index.
        let foreignLease = try SafariDocumentBinding.prepare(url: gemini, token: otherID)
        XCTAssertEqual(foreign.evaluateScript(foreignLease)?.toString(), otherID.uuidString.lowercased())

        let append = SafariDocumentBinding.guarded("(++dispatches,++attachments,'submitted')", document: id)
        let read = SafariDocumentBinding.guarded("(++reads,'receipt')", document: id)
        XCTAssertEqual(foreign.evaluateScript(append)?.toString(), SafariDocumentBinding.mismatch)
        XCTAssertEqual(foreign.evaluateScript(read)?.toString(), SafariDocumentBinding.mismatch)
        XCTAssertEqual(original.evaluateScript(append)?.toString(), "submitted")
        XCTAssertEqual(original.evaluateScript(read)?.toString(), "receipt")
        let snapshot = "[draft,attachments,dispatches,reads,sends].join('|')"
        XCTAssertEqual(foreign.evaluateScript(snapshot)?.toString(), "unaltered user draft|1|0|0|0")
        XCTAssertEqual(original.evaluateScript(snapshot)?.toString(), "unaltered user draft|2|1|1|0")
        XCTAssertNil(original.exception)
        XCTAssertNil(foreign.exception)
    }
}
