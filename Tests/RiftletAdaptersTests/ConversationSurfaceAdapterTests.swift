import Foundation
import XCTest
@testable import RiftletAdapters

final class ConversationSurfaceAdapterTests: XCTestCase {
    func testBundledInspectorBuildsACommandForEachService() throws {
        let roots = ["https://chatgpt.com/", "https://claude.ai/new", "https://gemini.google.com/app",
                     "https://perplexity.ai/", "https://poe.com/"]
        for root in roots {
            let adapter = try XCTUnwrap(ConversationSurfaceAdapter(url: try XCTUnwrap(URL(string: root))))
            let bindingID = UUID()
            let expression = try adapter.script(for: .bind, bindingID: bindingID)
            XCTAssertTrue(expression.contains("function inspectConversationSurface("))
            XCTAssertTrue(expression.contains(bindingID.uuidString))
            XCTAssertTrue(expression.contains("'\(adapter.service.rawValue)', 'bind'"))
        }
    }

    func testOnlyServiceConversationRoutesMatch() throws {
        for value in [
            "https://chatgpt.com", "https://chatgpt.com/c/sample", "https://claude.ai/chat/sample",
            "https://gemini.google.com/u/0/app/example", "https://perplexity.ai", "https://poe.com/chat/sample"
        ] {
            XCTAssertNotNil(ConversationSurfaceAdapter(url: try XCTUnwrap(URL(string: value))), value)
        }
        for value in [
            "http://chatgpt.com/", "https://chatgpt.com.evil.invalid/", "https://user@claude.ai/new",
            "https://gemini.google.com:444/app", "https://poe.com/settings", "https://perplexity.ai/search/%2Fother",
            "https://claude.ai/settings", "https://chatgpt.com/share/example"
        ] {
            XCTAssertNil(ConversationSurfaceAdapter(url: try XCTUnwrap(URL(string: value))), value)
        }
    }
}
