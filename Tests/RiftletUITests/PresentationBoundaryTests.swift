import AppKit
import XCTest
import RiftletCore
@testable import RiftletUI

/// Real AppKit callbacks in a software window-server session. These tests do
/// not prove rendered pixels, physical input or live ChatGPT attachment state.
final class PresentationBoundaryTests: XCTestCase {
    private func record(_ sequence: Int64 = 1, image: ImportedAsset? = nil,
                        origin: AssetOrigin = .synthetic, status: QueueStatus = .pending,
                        operationID: UUID? = nil, visibility: QueueVisibility = .visible,
                        revision: Int64 = 0, reason: QueueVisibilityReason = .capture) -> AssetRecord {
        let id = UUID()
        let asset = image ?? ImportedAsset(id: id, sourceKey: "presentation-\(id)",
            fileName: "\(id).png", sha256: String(repeating: "d", count: 64),
            byteCount: 80, pixelWidth: 160, pixelHeight: 100,
            mediaType: "image/png", origin: origin)
        return AssetRecord(image: asset, sequence: sequence, status: status,
            activeOperationID: operationID, visibility: visibility,
            visibilityRevision: revision, visibilityReason: reason)
    }

    @MainActor private func controller(
        holdsSelection: Bool = false,
        onBoundary: @escaping (RiftPresentationBoundary) -> Void = { _ in },
        onSelection: @escaping (RiftSelectionBoundary) -> Void = { _ in },
        onSelect: @escaping (UUID) -> Void = { _ in }
    ) throws -> RiftPanelController {
        _ = NSApplication.shared
        guard NSScreen.screens.contains(where: { $0.visibleFrame.height >= 400 }) else {
            throw XCTSkip("No window-server screen for software presentation boundaries; physical GUI remains separate")
        }
        var configuration = RiftConfiguration()
        configuration.arrivalDuration = 0.01
        configuration.pressDuration = 0.01
        configuration.swallowDuration = 0.02
        configuration.shiftDuration = 0.01
        configuration.returnDuration = 0.01
        configuration.reducedMotionDuration = 0.02
        return RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
            configuration: configuration, arrivalMode: .magnet, onSelectionBoundary: onSelection,
            onPresentationBoundary: onBoundary, holdsSelectionUntilFinished: holdsSelection,
            onSelect: onSelect)
    }

    @MainActor private func rowView(_ id: UUID, in panel: RiftPanelController) throws -> NSView {
        let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first { $0.assetID == id })
        let window = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.windowNumber })
        return try XCTUnwrap(window.contentView)
    }

    @MainActor func testWaitingFeedbackIsAccessibleAndStaleClearPreservesNewCancellation() throws {
        var selected = 0
        let panel = try controller(onSelect: { _ in selected += 1 }); defer { panel.close() }
        let asset = record(); panel.render([asset])
        let geometry = panel.diagnosticSnapshot.rows
        let view = try rowView(asset.id, in: panel)
        let waiting = "已接收，正在等待附加；本次尚未上传。"
        let cancelled = "此次附加已取消，图片保留；本次未上传。"
        panel.setFeedback(waiting, for: asset.id)
        XCTAssertTrue(view.accessibilityLabel()?.contains(waiting) == true)
        XCTAssertEqual(view.accessibilityHelp(), waiting)
        panel.setFeedback(cancelled, for: asset.id)
        panel.clearFeedback(matching: waiting, for: asset.id)
        XCTAssertEqual(view.toolTip, cancelled)
        XCTAssertTrue(view.accessibilityLabel()?.contains(cancelled) == true)
        panel.clearFeedback(matching: cancelled, for: asset.id)
        XCTAssertFalse(view.accessibilityLabel()?.contains(cancelled) == true)
        XCTAssertEqual(panel.diagnosticSnapshot.rows, geometry)
        XCTAssertEqual(selected, 0, "Presentation feedback cannot dispatch an input")
    }

    @MainActor func testOriginalStartIdentitySurvivesDeferredReadyAndClosesOnlyOnce() async throws {
        var boundaries: [RiftPresentationBoundary] = []
        let panel = try controller(onBoundary: { boundaries.append($0) })
        defer { panel.close() }
        let first = record(revision: 3), other = record(2), operation = UUID()
        panel.render([first, other])
        panel.render([record(image: first.image, status: .transferring,
                             operationID: operation, revision: 3), other])
        XCTAssertTrue(boundaries.isEmpty, "Click/input-pending state cannot claim visual swallowing")

        let started = record(image: first.image, status: .transferring,
            operationID: operation, visibility: .swallowed, revision: 4, reason: .uploadStarted)
        panel.render([started, other])
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart])
        let ready = record(image: first.image, status: .used,
            operationID: operation, visibility: .swallowed, revision: 4, reason: .uploadStarted)
        // A later committed backend snapshot arrives before the close callback.
        panel.render([ready, other])
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart, .swallowClose])
        XCTAssertTrue(boundaries.allSatisfy { $0.assetID == first.id && $0.operationID == operation
            && $0.visibilityRevision == 4 })
        XCTAssertEqual(Set(boundaries.map(\.generation)).count, 1)
        XCTAssertTrue(boundaries.allSatisfy { $0.uptime.isFinite && $0.uptime > 0 })
        for boundary in boundaries { XCTAssertEqual(boundary.actualDuration, 0.02, accuracy: 0.000_001) }
        for (earlier, later) in zip(boundaries, boundaries.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.uptime, later.uptime)
        }
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), [other.id])
        panel.render([ready, other])
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(boundaries.count, 3, "Final READY must not replay start or close for an already hidden asset")
    }

    @MainActor func testHideCancelsCloseAndHiddenSnapshotsDoNotInventPresentation() async throws {
        var boundaries: [RiftPresentationBoundary] = []
        let panel = try controller(onBoundary: { boundaries.append($0) })
        defer { panel.close() }
        let first = record(), operation = UUID()
        panel.render([first])
        panel.render([record(image: first.image, status: .transferring,
            operationID: operation, visibility: .swallowed, revision: 1, reason: .uploadStarted)])
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart])
        panel.setUserHidden(true)
        let unknown = record(image: first.image, status: .unknown,
            operationID: operation, visibility: .swallowed, revision: 1, reason: .uploadStarted)
        let neverShown = record(2), otherOperation = UUID()
        panel.render([unknown, neverShown])
        panel.render([unknown, record(2, image: neverShown.image, status: .transferring,
            operationID: otherOperation, visibility: .swallowed, revision: 1, reason: .uploadStarted)])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart],
                       "User hiding closes windows, but is not a completed swallow animation")
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        panel.setUserHidden(false)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(boundaries.count, 2, "An upload that started while hidden has no synthetic presentation history")
    }

    @MainActor func testControllerCloseCancelsPendingSwallowCloseCallback() async throws {
        var boundaries: [RiftPresentationBoundary] = []
        let panel = try controller(onBoundary: { boundaries.append($0) })
        defer { panel.close() }
        let first = record(), operation = UUID()
        panel.render([first])
        let started = record(image: first.image, status: .unknown,
            operationID: operation, visibility: .swallowed, revision: 8, reason: .uploadStarted)
        panel.render([started])
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart])
        panel.close()
        panel.render([started])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(boundaries.map(\.phase), [.swallowScheduled, .swallowActualStart])
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
    }

    @MainActor func testSyntheticAXIdentityRequiresVisibleRowAndPreservesSelectionGuard() async throws {
        var selected: [UUID] = [], selections: [RiftSelectionBoundary] = []
        let panel = try controller(holdsSelection: true,
            onSelection: { selections.append($0) }, onSelect: { selected.append($0) })
        defer { panel.close() }
        let synthetic = record(revision: 6)
        let real = record(2, origin: .systemScreenshot, revision: 2)
        let transferring = record(3, status: .transferring, operationID: UUID())
        panel.render([synthetic, real, transferring])
        let syntheticView = try rowView(synthetic.id, in: panel)
        let realView = try rowView(real.id, in: panel)
        let transferringView = try rowView(transferring.id, in: panel)
        XCTAssertEqual(syntheticView.accessibilityIdentifier(), "riftlet-synthetic-\(synthetic.id.uuidString)")
        XCTAssertEqual(realView.accessibilityIdentifier(), "", "A real screenshot cannot expose an acceptance target ID")
        XCTAssertTrue(syntheticView.isAccessibilityEnabled())
        XCTAssertFalse(transferringView.isAccessibilityEnabled())
        XCTAssertFalse(transferringView.accessibilityPerformPress())

        XCTAssertTrue(syntheticView.accessibilityPerformPress())
        XCTAssertFalse(syntheticView.accessibilityPerformPress(), "The AX identifier cannot bypass an in-flight selection")
        XCTAssertEqual(selected, [synthetic.id])
        XCTAssertEqual(panel.selectionRevision(for: synthetic.id), 6)
        XCTAssertEqual(selections.count, 1)
        XCTAssertEqual(selections.first?.source, .accessibility)
        XCTAssertNil(selections.first?.eventNumber)
        XCTAssertNil(selections.first?.windowNumber)
        XCTAssertNil(selections.first?.clickCount)
        panel.finishSelection(synthetic.id)

        // Adding the synthetic selector must not replace the original real-row
        // accessibility selection path. Core/adapter eligibility remains separate.
        XCTAssertTrue(realView.accessibilityPerformPress())
        XCTAssertEqual(selected, [synthetic.id, real.id])
        XCTAssertFalse(realView.accessibilityPerformPress())
        panel.finishSelection(real.id)
        panel.render([record(image: synthetic.image, status: .transferring,
            operationID: UUID(), visibility: .swallowed, revision: 7, reason: .uploadStarted), real, transferring])
        XCTAssertEqual(syntheticView.accessibilityIdentifier(), "")
        XCTAssertFalse(syntheticView.isAccessibilityEnabled())
        XCTAssertFalse(syntheticView.accessibilityPerformPress())

        panel.setUserHidden(true)
        XCTAssertEqual(transferringView.accessibilityIdentifier(), "")
        XCTAssertFalse(transferringView.isAccessibilityEnabled())
        XCTAssertFalse(realView.accessibilityPerformPress())
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(selected, [synthetic.id, real.id])
    }
}
