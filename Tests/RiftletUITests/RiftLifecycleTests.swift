import AppKit
import XCTest
import RiftletCore
@testable import RiftletUI

final class RiftLifecycleTests: XCTestCase {
    private func record(_ index: Int = 1, image: ImportedAsset? = nil,
                        status: QueueStatus = .pending, visibility: QueueVisibility = .visible,
                        reason: QueueVisibilityReason? = nil) -> AssetRecord {
        let id = UUID()
        let asset = image ?? ImportedAsset(id: id, sourceKey: "lifecycle-\(id)", fileName: "\(id).png",
            sha256: String(repeating: "d", count: 64), byteCount: 80,
            pixelWidth: 160, pixelHeight: 100, mediaType: "image/png", origin: .synthetic)
        return AssetRecord(image: asset, sequence: Int64(index), status: status, visibility: visibility, visibilityReason: reason)
    }

    func testVisibilityIsIndependentOfBackendStatusAndOrdinalsStayContinuous() {
        let records = [record(1), record(2, status: .transferring, visibility: .swallowed),
                       record(3, status: .unknown, visibility: .swallowed),
                       record(4, status: .used, visibility: .visible),
                       record(5, status: .failed, visibility: .visible),
                       record(6, visibility: .archived), record(7, visibility: .removed)]
        let layout = RiftLayout.make(records: records,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), configuration: .init())
        XCTAssertEqual(layout.rows.map(\.assetID), [records[0].id, records[3].id, records[4].id])
        XCTAssertEqual(layout.rows.map(\.ordinal), [1, 2, 3])
        XCTAssertEqual(layout.totalCount, 3)
    }

    func testEmptyAndEntirelyHiddenQueuesHaveNoLegacyLine() {
        var configuration = RiftConfiguration()
        configuration.emptyTraceLength = 240
        let frame = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        for records in [[], [record(visibility: .swallowed), record(visibility: .removed), record(visibility: .archived)]] {
            let layout = RiftLayout.make(records: records, visibleFrame: frame, configuration: configuration)
            XCTAssertTrue(layout.rows.isEmpty)
            XCTAssertEqual(layout.lineFrame, .zero)
            XCTAssertEqual(layout.totalCount, 0)
        }
    }

    func testMouseReleaseProtectsSelectionUntilPrepareOrCancellation() {
        var state = RiftInteractionState()
        let id = UUID()
        state.beginSelection(id, held: true)
        let downRevision = state.snapshot.revision
        state.releasePointer(accepted: true)
        XCTAssertFalse(state.snapshot.isHolding)
        XCTAssertTrue(state.snapshot.isSelecting)
        XCTAssertTrue(state.snapshot.blocksAutomaticArchive)
        XCTAssertEqual(state.snapshot.protectedAssetIDs, [id])
        XCTAssertGreaterThan(state.snapshot.revision, downRevision)
        state.finishSelection(id)
        XCTAssertFalse(state.snapshot.blocksAutomaticArchive)
    }

    func testCanceledPressDoesNotLeaveArchiveOrSelectionLocked() {
        var state = RiftInteractionState()
        let id = UUID()
        state.beginSelection(id, held: true)
        state.releasePointer(accepted: false)
        XCTAssertTrue(state.snapshot.protectedAssetIDs.isEmpty)
        XCTAssertFalse(state.snapshot.isSelecting)
        XCTAssertFalse(state.snapshot.blocksAutomaticArchive)
    }

    func testHoverMenuAndOverlappingAnimationsProtectQueueUntilAllHaveEnded() {
        var state = RiftInteractionState()
        let id = UUID(), first = UUID(), second = UUID()
        state.setHovered([id]); state.setMenu(id, open: true)
        state.beginAnimation(first); state.beginAnimation(second)
        state.setHovered([]); state.endAnimation(first)
        XCTAssertTrue(state.snapshot.blocksAutomaticArchive)
        state.setMenu(id, open: false)
        XCTAssertTrue(state.snapshot.blocksAutomaticArchive)
        state.endAnimation(second)
        XCTAssertFalse(state.snapshot.blocksAutomaticArchive)
        let settled = state.snapshot.revision
        state.endAnimation(first)
        XCTAssertEqual(state.snapshot.revision, settled, "An obsolete completion cannot clear later protection")
    }

    func testHideOrReflowDoesNotReleaseAnAcceptedAsynchronousSelection() {
        var state = RiftInteractionState()
        let id = UUID()
        state.beginSelection(id, held: true); state.releasePointer(accepted: true)
        state.setHovered([id]); state.beginAnimation(UUID())
        state.resetPresentation()
        XCTAssertTrue(state.snapshot.isSelecting)
        XCTAssertEqual(state.snapshot.protectedAssetIDs, [id])
        XCTAssertTrue(state.snapshot.blocksAutomaticArchive)
        state.finishSelection(id)
        XCTAssertFalse(state.snapshot.blocksAutomaticArchive)
    }

    @MainActor private func controller() throws -> RiftPanelController {
        _ = NSApplication.shared
        guard NSScreen.screens.contains(where: { $0.visibleFrame.height >= 400 }) else {
            throw XCTSkip("No window-server screen for software panel lifecycle; physical GUI remains separate")
        }
        var configuration = RiftConfiguration()
        configuration.arrivalDuration = 0.015
        configuration.pressDuration = 0.01
        configuration.swallowDuration = 0.015
        configuration.shiftDuration = 0.01
        configuration.returnDuration = 0.01
        return RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
                                   configuration: configuration, arrivalMode: .magnet, onSelect: { _ in })
    }

    /// Introspection of real panels in CI, not a physical pointer/focus trial.
    @MainActor func testHiddenIntentSurvivesNewImagesReflowAndLateAnimations() async throws {
        let panel = try controller()
        defer { panel.close() }
        let first = record(), second = record(2)
        panel.render([first])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.count, 1)
        panel.setUserHidden(true)
        panel.render([first, second])
        panel.showAsset(second.id)
        var configuration = panel.configuration
        configuration.outerInset += 1
        try panel.updateConfiguration(configuration)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(panel.userHidden)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(panel.diagnosticSnapshot.lineFrame, .zero)
        panel.setUserHidden(false)
        XCTAssertEqual(Set(panel.diagnosticSnapshot.rows.map(\.assetID)), [first.id, second.id])
    }

    @MainActor func testSwallowPrecedesReadyAndFailureReturnsAnOrdinaryVisibleRow() async throws {
        let panel = try controller()
        defer { panel.close() }
        let first = record(status: .transferring)
        panel.render([first])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.count, 1)
        panel.render([record(image: first.image, status: .transferring, visibility: .swallowed, reason: .uploadStarted)])
        XCTAssertTrue(panel.diagnosticSnapshot.isTransitioning, "An admitted start, not READY, begins the short exit")
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(panel.diagnosticSnapshot.lineFrame, .zero)
        panel.render([record(image: first.image, status: .unknown, visibility: .swallowed, reason: .uploadStarted)])
        panel.render([record(image: first.image, status: .used, visibility: .swallowed, reason: .uploadStarted)])
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertFalse(panel.diagnosticSnapshot.isTransitioning)
        panel.render([record(image: first.image, status: .failed)])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [first.id])
    }

    @MainActor func testBackendReadyAloneDoesNotTriggerVisualSwallow() async throws {
        let panel = try controller()
        defer { panel.close() }
        let first = record()
        panel.render([first])
        panel.render([record(image: first.image, status: .used, visibility: .visible)])
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [first.id])
        XCTAssertFalse(panel.diagnosticSnapshot.isTransitioning)
    }

    @MainActor func testArchiveSnapshotWaitsForAnActivePressInsteadOfRemovingItsRow() async throws {
        let panel = try controller()
        defer { panel.close() }
        let first = record()
        panel.render([first])
        let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
        let view = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.windowNumber }?.contentView)
        XCTAssertTrue(view.accessibilityPerformPress())
        XCTAssertTrue(panel.interactionSnapshot.isTransitioning)
        panel.render([record(image: first.image, visibility: .archived)])
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [first.id])
        try await Task.sleep(nanoseconds: 80_000_000)
        // The CI cursor may itself be over this real panel. Such a hover must
        // continue protecting it; the pure-state tests cover explicit exit.
        if panel.interactionSnapshot.blocksAutomaticArchive {
            XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [first.id])
        } else {
            XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
            XCTAssertEqual(panel.diagnosticSnapshot.lineFrame, .zero)
        }
    }


    @MainActor func testLegacyCompletionRemovesSilentlyWithoutAReadySwallowAnimation() async throws {
        let panel = try controller()
        defer { panel.close() }
        let first = record()
        panel.render([first])
        panel.render([record(image: first.image, status: .used, visibility: .swallowed, reason: .legacyCompletion)])
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(panel.diagnosticSnapshot.lineFrame, .zero)
        XCTAssertFalse(panel.diagnosticSnapshot.isTransitioning)
    }


    @MainActor func testDelayedPressReleaseCannotReverseAnUploadStartSwallow() async throws {
        let panel = try controller()
        defer { panel.close() }
        var configuration = panel.configuration
        configuration.swallowDuration = 0.15
        try panel.updateConfiguration(configuration)
        let first = record()
        panel.render([first])
        let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
        let window = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.windowNumber })
        let view = try XCTUnwrap(window.contentView)
        let imageLayer = try XCTUnwrap(view.layer?.sublayers?.first?.sublayers?.first)
        // This invokes the actual accessibility callback in software; it is not
        // a physical N1 event or evidence about a live attachment adapter.
        XCTAssertTrue(view.accessibilityPerformPress())
        panel.render([record(image: first.image, status: .transferring,
                             visibility: .swallowed, reason: .uploadStarted)])
        let inwardExit = imageLayer.affineTransform().tx
        XCTAssertGreaterThan(inwardExit, CGFloat(configuration.inwardDistance))
        try await Task.sleep(nanoseconds: 45_000_000)
        XCTAssertEqual(imageLayer.affineTransform().tx, inwardExit,
                       "The older press-release timer must not animate back out of the rift")
    }


    @MainActor func testFailureRebirthDoesNotAutoFollowNewestAndExplicitHistoryRevealFindsAnOldItem() async throws {
        let panel = try controller()
        defer { panel.close() }
        let records = (1...100).map { record($0) }
        var initial = records
        initial[0] = record(image: records[0].image, status: .unknown,
                            visibility: .swallowed, reason: .uploadStarted)
        panel.render(initial)
        var revived = records
        revived[0] = record(image: records[0].image, status: .failed, reason: .safeFailure)
        panel.render(revived)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.first?.assetID, records[0].id,
                       "An old safe failure must not be mistaken for a newly captured last item")
        panel.showAsset(records[99].id)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.contains { $0.assetID == records[99].id })
        panel.showAsset(records[0].id)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.contains { $0.assetID == records[0].id })
    }

}
