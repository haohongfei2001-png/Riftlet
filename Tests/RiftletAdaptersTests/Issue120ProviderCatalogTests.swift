import CryptoKit
import Foundation
import XCTest
@testable import RiftletAdapters

final class Issue120ProviderCatalogTests: XCTestCase {
    let entries = [
        "claude": "https://claude.ai/new", "gemini": "https://gemini.google.com/app",
        "deepseek": "https://chat.deepseek.com/", "kimi": "https://www.kimi.com/",
        "qianwen-cn": "https://www.qianwen.com/", "doubao": "https://www.doubao.com/chat/",
        "perplexity": "https://www.perplexity.ai/", "qwen-international": "https://chat.qwen.ai/",
        "grok": "https://grok.com/"
    ]

    func testBundledProgramMatchesEveryNominatedProfile() throws {
        let catalog = try Issue120ProviderCatalog()
        XCTAssertEqual(catalog.providers.count, entries.count)
        for (id, address) in entries {
            let route = try resolveProvider(XCTUnwrap(URL(string: address)), among: catalog.providers)
            XCTAssertEqual(route.profile.id, id)
            XCTAssertEqual(route.route.mode, "unverified")
            let program = try catalog.program(for: route.profile)
            let digest = SHA256.hash(data: Data(program.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, route.profile.digest)
            XCTAssertEqual(route.profile.revision, 1)
            let other = try ProviderProfile(id: id, revision: 1, program: Data("wrong program".utf8))
            XCTAssertThrowsError(try catalog.program(for: other))
        }
        XCTAssertEqual(Set(catalog.providers.map { $0.profile.digest }).count, entries.count)
    }

    func testLoginProjectAndOtherModesAreNotNominated() throws {
        let catalog = try Issue120ProviderCatalog()
        let excluded = [
            "https://claude.ai/project/x", "https://claude.ai/new?mode=analysis", "https://claude.ai/new#draft",
            "https://accounts.google.com/app", "https://gemini.google.com:444/app",
            "https://gemini.google.com.attacker.invalid/app", "https://user@chat.deepseek.com/",
            "http://chat.deepseek.com/", "https://chat.deepseek.com/sign_in", "https://grok.com/imagine",
            "https://www.kimi.com/agent", "https://chat.qwen.ai/chat/unverified"
        ]
        for address in excluded {
            XCTAssertThrowsError(try resolveProvider(XCTUnwrap(URL(string: address)), among: catalog.providers), address)
        }
    }
}
