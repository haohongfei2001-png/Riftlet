import XCTest
@testable import RiftletCore

final class EdgeTargetIdentityTests: XCTestCase {
    private func target(application: String = "com.microsoft.edgemac", session: String = "edge-kernel-v1:7:10:1",
                        tab: String = "2", document: String = "original") -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: application,
            sessionID: session, windowID: "1", tabID: tab, documentID: document,
            composerID: "editor", draftGeneration: "draft", clickBindingID: UUID())
    }

    func testDistinctEdgeClickPinsKeepOriginalTabOwnershipConflicts() {
        let first = target(), second = target()
        XCTAssertNotEqual(first.stableKey, second.stableKey)
        XCTAssertEqual(first.serializationKey, second.serializationKey)
        XCTAssertTrue(first.conflictsForDispatch(with: second))
        XCTAssertTrue(first.conflictsForDispatch(with: target(document: "replacement")))
        XCTAssertFalse(first.conflictsForDispatch(with: target(tab: "3")))
        XCTAssertFalse(first.conflictsForDispatch(with: target(session: "edge-kernel-v1:7:11:1")))
        XCTAssertFalse(first.conflictsForDispatch(with: target(application: "com.google.Chrome")))
        XCTAssertFalse(first.sharesContinuationDraft(with: second), "No business-draft evidence is inferred from a native tab")
    }
}
