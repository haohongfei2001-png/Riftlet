import XCTest
import RiftletCore
@testable import RiftletAdapters

@MainActor private final class RecordingClickAdapter: ConversationClickAdapter {
    let applicationID: String
    var calls = 0
    init(_ id: String) { applicationID = id }
    func targetForClick() throws -> Task<TargetLease, Error> {
        calls += 1
        return Task { throw WebAdapterError.invalidTarget }
    }
}

final class ConversationClickRouterTests: XCTestCase {
    @MainActor func testMouseDownInvokesExactlyOneAdmittedForegroundHostSynchronously() throws {
        let chrome = RecordingClickAdapter("com.google.Chrome"), edge = RecordingClickAdapter("com.microsoft.edgemac")
        var current: String? = edge.applicationID
        let router = ConversationClickRouter(adapters: [chrome, edge], foreground: { current })
        let first = try router.targetForClick()
        XCTAssertEqual(edge.calls, 1)
        current = chrome.applicationID
        let next = try router.targetForClick()
        XCTAssertEqual(chrome.calls, 1)
        for missing in [nil, "other.app"] as [String?] {
            current = missing
            XCTAssertThrowsError(try router.targetForClick())
        }
        let duplicate = ConversationClickRouter(adapters: [edge, edge], foreground: { edge.applicationID })
        XCTAssertThrowsError(try duplicate.targetForClick())
        XCTAssertEqual(edge.calls, 1)
        XCTAssertEqual(chrome.calls, 1)
        first.cancel()
        next.cancel()
    }
}
