import XCTest
@testable import RiftletAdapters
import RiftletCore

final class NativeCaptureProofTests: XCTestCase {
    private func target(window: String = "1", generation: String = "draft") -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
                    sessionID: "pid:launch", windowID: window, tabID: "2", documentID: "document",
                    composerID: "composer", draftGeneration: generation)
    }
    func testNativeCaptureRejectsDifferentContextBeforeTracingACK() throws {
        let bytes = try JSONEncoder().encode(target(window: "3"))
        XCTAssertThrowsError(try NativeCaptureProof.digest(bytes, session: "pid:launch", window: "1", tab: "2"))
        XCTAssertThrowsError(try NativeCaptureProof.digest(Data("{}".utf8), session: "pid:launch", window: "1", tab: "2"))
        XCTAssertThrowsError(try NativeCaptureProof.digest(try JSONEncoder().encode(target(generation: "")), session: "pid:launch", window: "1", tab: "2"))
    }
    func testDigestJoinsSameTargetAndSeparatesDifferentLease() throws {
        let a = try JSONEncoder().encode(target())
        let b = try JSONEncoder().encode(target(generation: "different"))
        let digest = try NativeCaptureProof.digest(a, session: "pid:launch", window: "1", tab: "2")
        XCTAssertEqual(digest.count, 64)
        XCTAssertNotEqual(digest, try NativeCaptureProof.digest(b, session: "pid:launch", window: "1", tab: "2"))
        let pretty = JSONEncoder(); pretty.outputFormatting = [.prettyPrinted]
        XCTAssertEqual(digest, try NativeCaptureProof.digest(pretty.encode(target()), session: "pid:launch", window: "1", tab: "2"))
    }
}
