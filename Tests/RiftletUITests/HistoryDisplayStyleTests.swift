import AppKit
import CryptoKit
import ImageIO
import RiftletCore
import UniformTypeIdentifiers
import XCTest
@testable import RiftletUI

private final class HistoryGridDecodeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID] = []
    private var scaleValues: [CGFloat] = []
    private var active = 0, peak = 0
    func append(_ id: UUID, backing: CGFloat = 0) -> Int {
        lock.lock(); defer { lock.unlock() }; values.append(id); scaleValues.append(backing); return values.count
    }
    var ids: [UUID] { lock.lock(); defer { lock.unlock() }; return values }
    var backings: [CGFloat] { lock.lock(); defer { lock.unlock() }; return scaleValues }
    func begin(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        values.append(id); active += 1; peak = max(peak, active)
    }
    func end() { lock.lock(); active -= 1; lock.unlock() }
    var maximumConcurrentDecodes: Int { lock.lock(); defer { lock.unlock() }; return peak }
}

final class HistoryDisplayStyleTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-history-style-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func asset(in directory: URL, date: Date = Date(), width: Int = 80, height: Int = 40) throws -> ImportedAsset {
        let id = UUID(), name = id.uuidString + ".png"
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return ImportedAsset(id: id, sourceKey: "history-style-fixture-" + id.uuidString,
            fileName: name, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(data.count), pixelWidth: width, pixelHeight: height, mediaType: "image/png", firstSeenAt: date, origin: .synthetic)
    }

    @MainActor private func display() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit display unavailable") }
    }

    @MainActor private func find<T: NSView>(_ id: String, in window: NSWindow, as type: T.Type = T.self) throws -> T {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        return try XCTUnwrap(window.contentView.flatMap { descendants($0).first { $0.identifier?.rawValue == id } } as? T)
    }

    @MainActor private func invoke(_ control: NSControl) throws {
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(control.action), to: control.target, from: control))
    }

    @MainActor private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(predicate(), "The actual native/decoder condition did not settle before the deadline")
    }

    @MainActor
    func testDefaultUsesOriginalTableAndPassiveProjectionDoesNotPresentOrDispatch() throws {
        try display()
        var commands = 0, choices: [HistoryDisplayStyle] = []
        let controller = RiftHistoryController(mediaDirectory: try directory(), onRestore: { _ in commands += 1 },
            onRemove: { _ in commands += 1 }, onReveal: { _ in commands += 1 },
            onNextPage: { commands += 1 }, onPreviousPage: { commands += 1 },
            onDisplayStyleChanged: { choices.append($0) })
        defer { controller.close() }
        let table: NSTableView = try find("history.current.table", in: controller.window)
        XCTAssertEqual(controller.displayStyle, .current)
        XCTAssertEqual(table.tableColumns.map(\.identifier.rawValue), ["preview", "description"])
        XCTAssertEqual(table.tableColumns[0].width, 72)
        XCTAssertEqual(table.rowHeight, 64)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        controller.updateDisplayStyle(.imageGrid); controller.updateDisplayStyle(.current)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost)
        XCTAssertTrue(choices.isEmpty); XCTAssertEqual(commands, 0)
        XCTAssertEqual(table.tableColumns[0].width, 72)
    }

    @MainActor
    func testNativeGridLayoutFitsActualDocumentWidthAndRestoresHiddenSelection() throws {
        try display()
        let dir = try directory()
        let images = try (0..<3).map { index in try asset(in: dir, date: Date().addingTimeInterval(-Double(index))) }
        let entries = images.enumerated().map {
            RiftHistoryEntry(record: AssetRecord(image: $0.element, sequence: Int64(3 - $0.offset)))
        }
        var selections: [UUID?] = []
        let renderer = HistoryGridRenderer(directory: dir, onSelection: { selections.append($0) },
            onPreview: { XCTFail("Geometry must not open an original") }, stateText: { _ in "待附加" }, mayLoad: { false })
        defer { renderer.clear() }
        renderer.scrollView.frame = NSRect(x: 0, y: 0, width: 533, height: 400)
        renderer.setVisible(false)
        renderer.update(entries: entries, selection: images[1].id)
        renderer.collection.setFrameSize(NSSize(width: 0, height: 400))
        renderer.collection.layoutSubtreeIfNeeded()
        XCTAssertEqual(renderer.collection.numberOfSections, 0, "Hidden geometry has no native items, but retains the shared metadata")

        // Exercise real flow-layout attributes when the collection document
        // has not yet caught up with the wider enclosing clip view, followed
        // by normal widths. Checking frames tests AppKit's layout contract,
        // rather than reproducing the renderer's column arithmetic.
        renderer.collection.setFrameSize(NSSize(width: 112, height: 400))
        renderer.setVisible(true)
        let layout = try XCTUnwrap(renderer.collection.collectionViewLayout)
        for width: CGFloat in [112, 260, 533, 385] {
            renderer.collection.setFrameSize(NSSize(width: width, height: 400))
            renderer.resize()
            renderer.collection.layoutSubtreeIfNeeded()
            XCTAssertEqual(renderer.collection.bounds.width, width, accuracy: 1)
            var frames: [NSRect] = []
            for item in entries.indices {
                let attributes = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: item, section: 0)))
                XCTAssertGreaterThan(attributes.frame.width, 0)
                XCTAssertGreaterThanOrEqual(attributes.frame.minX, 0)
                XCTAssertLessThanOrEqual(attributes.frame.maxX, renderer.collection.bounds.width + 1)
                XCTAssertFalse(frames.contains { $0.intersects(attributes.frame) })
                frames.append(attributes.frame)
            }
            XCTAssertEqual(renderer.collection.selectionIndexPaths, [IndexPath(item: 1, section: 0)])
        }
        renderer.setVisible(false)
        renderer.collection.setFrameSize(NSSize(width: 0, height: 400))
        renderer.collection.layoutSubtreeIfNeeded()
        XCTAssertEqual(renderer.collection.numberOfSections, 0)
        renderer.collection.setFrameSize(NSSize(width: 385, height: 400))
        renderer.setVisible(true)
        XCTAssertEqual(renderer.collection.numberOfItems(inSection: 0), entries.count)
        XCTAssertEqual(renderer.collection.selectionIndexPaths, [IndexPath(item: 1, section: 0)])
        XCTAssertTrue(selections.isEmpty, "Hide/show and geometry project the same UUID without selection callbacks")
    }

    @MainActor
    func testUserSelectorRequestsOwnerProjectionWithoutAnIndependentPreference() throws {
        try display()
        var requested: [HistoryDisplayStyle] = []
        let controller = RiftHistoryController(mediaDirectory: try directory(), onRestore: { _ in }, onRemove: { _ in },
            onReveal: { _ in }, onDisplayStyleChanged: { requested.append($0) })
        defer { controller.close() }
        let selector: NSPopUpButton = try find("history.displayStyle", in: controller.window)
        selector.selectItem(at: 1); try invoke(selector)
        XCTAssertEqual(requested, [.imageGrid])
        XCTAssertEqual(controller.displayStyle, .current, "Only the shared owner may project an accepted choice")
        XCTAssertEqual(selector.indexOfSelectedItem, 0)
        controller.updateDisplayStyle(.imageGrid)
        XCTAssertEqual(selector.indexOfSelectedItem, 1)
        XCTAssertEqual(requested, [.imageGrid], "Projection must not emit another user choice")
    }

    @MainActor
    func testStyleRoundTripPreservesQueryFilterPageUUIDDetailAndExactActionTarget() async throws {
        try display()
        let dir = try directory(), image = try asset(in: dir), other = try asset(in: dir, date: Date().addingTimeInterval(-120))
        let selected = RiftHistoryEntry(record: AssetRecord(image: image, sequence: 2, visibility: .archived), canRestore: true)
        var restored: [UUID] = [], revealed: [UUID] = [], paging = 0
        weak var owner: RiftHistoryController?
        let controller = RiftHistoryController(mediaDirectory: dir, onRestore: { restored.append($0) }, onRemove: { _ in XCTFail("Unexpected remove") },
            onReveal: { revealed.append($0) }, onNextPage: { paging += 1 }, onPreviousPage: { paging += 1 },
            onDisplayStyleChanged: { owner?.updateDisplayStyle($0) })
        owner = controller; defer { controller.close() }
        controller.update(entries: [selected, RiftHistoryEntry(record: AssetRecord(image: other, sequence: 1))], pageOffset: 200, hasEarlier: true)
        controller.show()
        let filter: NSButton = try find("history.filter.3", in: controller.window); try invoke(filter)
        let search: NSSearchField = try find("history.search", in: controller.window)
        search.stringValue = image.id.uuidString.prefix(8).description
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        let table: NSTableView = try find("history.current.table", in: controller.window)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let detail: NSImageView = try find("history.detail.image", in: controller.window)
        try await waitUntil { detail.image != nil }
        let bitmap = try XCTUnwrap(detail.image)
        let count: NSTextField = try find("history.count", in: controller.window)
        let beforeCount = count.stringValue
        let selector: NSPopUpButton = try find("history.displayStyle", in: controller.window)
        XCTAssertTrue(controller.window.makeFirstResponder(table))
        selector.selectItem(at: 1); try invoke(selector)
        let grid: NSCollectionView = try find("history.grid", in: controller.window)
        XCTAssertTrue(controller.window.firstResponder === grid)
        XCTAssertEqual(controller.selectedRecordID, image.id)
        XCTAssertTrue(detail.image === bitmap, "Pure style change must not clear/redecode the detail")
        XCTAssertEqual(search.stringValue, image.id.uuidString.prefix(8).description)
        let gridFilter: NSPopUpButton = try find("history.grid.filter", in: controller.window)
        XCTAssertEqual(gridFilter.indexOfSelectedItem, 3)
        XCTAssertEqual(count.stringValue, beforeCount); XCTAssertTrue(count.stringValue.contains("第 2 页"))
        let restore: NSButton = try find("history.restore", in: controller.window); try invoke(restore)
        let reveal: NSButton = try find("history.reveal", in: controller.window); try invoke(reveal)
        XCTAssertEqual(restored, [image.id]); XCTAssertEqual(revealed, [image.id]); XCTAssertEqual(paging, 0)
        selector.selectItem(at: 0); try invoke(selector)
        XCTAssertTrue(controller.window.firstResponder === table)
        XCTAssertEqual(table.selectedRow, 0); XCTAssertEqual(controller.selectedRecordID, image.id)
        XCTAssertTrue(detail.image === bitmap); XCTAssertEqual(count.stringValue, beforeCount)
        let next: NSButton = try find("history.next", in: controller.window); try invoke(next)
        XCTAssertEqual(paging, 1, "Only the explicit paging action may ask the original owner for another page")
        XCTAssertTrue(controller.window.makeFirstResponder(search))
        let editor = try XCTUnwrap(search.currentEditor())
        controller.updateDisplayStyle(.imageGrid)
        XCTAssertTrue(controller.window.firstResponder === editor, "An active search editor keeps its focus and text")
        XCTAssertEqual(search.stringValue, image.id.uuidString.prefix(8).description)
    }

    @MainActor
    func testReloadKeepsSelectedUUIDWhenEarlierRowIsInsertedAndFilteringToEmptyClearsActions() throws {
        try display()
        let dir = try directory(), selected = try asset(in: dir), newer = try asset(in: dir, date: Date().addingTimeInterval(10))
        var revealed: [UUID] = []
        let controller = RiftHistoryController(mediaDirectory: dir, onRestore: { _ in }, onRemove: { _ in }, onReveal: { revealed.append($0) })
        defer { controller.close() }
        let original = RiftHistoryEntry(record: AssetRecord(image: selected, sequence: 1))
        controller.update(entries: [original]); controller.show()
        let table: NSTableView = try find("history.current.table", in: controller.window)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        controller.update(entries: [original, RiftHistoryEntry(record: AssetRecord(image: newer, sequence: 2))])
        XCTAssertEqual(table.selectedRow, 1); XCTAssertEqual(controller.selectedRecordID, selected.id)
        controller.updateDisplayStyle(.imageGrid)
        let reveal: NSButton = try find("history.reveal", in: controller.window); try invoke(reveal)
        XCTAssertEqual(revealed, [selected.id], "Row zero is no longer the selected record")
        let search: NSSearchField = try find("history.search", in: controller.window)
        search.stringValue = "no-history-fixture-matches-this"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        XCTAssertNil(controller.selectedRecordID); XCTAssertFalse(reveal.isEnabled); XCTAssertTrue(reveal.isHidden)
        controller.updateDisplayStyle(.current)
        XCTAssertEqual(table.selectedRow, -1); XCTAssertEqual(table.numberOfRows, 0)
    }

    @MainActor
    func testOriginalWindowIdentityBitmapAndZoomSurviveBothStyleChanges() async throws {
        try display()
        let dir = try directory(), image = try asset(in: dir, width: 120, height: 240)
        let controller = RiftHistoryController(mediaDirectory: dir, onRestore: { _ in }, onRemove: { _ in }, onReveal: { _ in })
        defer { controller.close() }
        controller.update(entries: [RiftHistoryEntry(record: AssetRecord(image: image, sequence: 1))]); controller.show()
        let table: NSTableView = try find("history.current.table", in: controller.window)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        controller.openOriginal(id: image.id)
        let preview = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible })
        let zoom: NSSegmentedControl = try find("history.preview.zoom", in: preview)
        zoom.selectedSegment = 2; try invoke(zoom)
        let view: NSImageView = try find("history.preview.image", in: preview)
        try await waitUntil { view.image != nil }
        let bitmap = try XCTUnwrap(view.image), frame = preview.frame
        controller.updateDisplayStyle(.imageGrid); controller.updateDisplayStyle(.current)
        XCTAssertTrue(preview.isVisible); XCTAssertEqual(zoom.selectedSegment, 2)
        XCTAssertEqual(preview.frame, frame); XCTAssertTrue(view.image === bitmap)
        XCTAssertEqual(controller.selectedRecordID, image.id)
    }

    @MainActor
    func testFirstGridThumbnailsLoadWhileOriginalWindowRetainsBitmapAndZoom() async throws {
        try display()
        let dir = try directory(), original = try asset(in: dir, width: 120, height: 240)
        let other = try asset(in: dir, date: Date().addingTimeInterval(-10), width: 240, height: 120)
        let controller = RiftHistoryController(mediaDirectory: dir, onRestore: { _ in }, onRemove: { _ in }, onReveal: { _ in })
        defer { controller.close() }
        controller.update(entries: [original, other].enumerated().map {
            RiftHistoryEntry(record: AssetRecord(image: $0.element, sequence: Int64(2 - $0.offset)))
        })
        controller.show()
        let table: NSTableView = try find("history.current.table", in: controller.window)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        controller.openOriginal(id: original.id)
        let preview = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible })
        let zoom: NSSegmentedControl = try find("history.preview.zoom", in: preview)
        zoom.selectedSegment = 2; try invoke(zoom)
        let originalView: NSImageView = try find("history.preview.image", in: preview)
        try await waitUntil { originalView.image != nil }
        let originalBitmap = try XCTUnwrap(originalView.image), originalFrame = preview.frame
        controller.updateDisplayStyle(.imageGrid)
        let collection: NSCollectionView = try find("history.grid", in: controller.window)
        func loadedImages(in view: NSView) -> [NSImageView] {
            (view as? NSImageView).map { $0.image == nil ? [] : [$0] } ?? view.subviews.flatMap(loadedImages)
        }
        let otherPath = IndexPath(item: 1, section: 0)
        try await waitUntil {
            collection.item(at: otherPath).map { !loadedImages(in: $0.view).isEmpty } == true
        }
        XCTAssertTrue(preview.isVisible); XCTAssertEqual(zoom.selectedSegment, 2)
        XCTAssertEqual(preview.frame, originalFrame); XCTAssertTrue(originalView.image === originalBitmap)
        XCTAssertEqual(controller.selectedRecordID, original.id)
        XCTAssertEqual(collection.item(at: otherPath)?.view.accessibilityIdentifier(), "history.grid.item." + other.id.uuidString)
    }

    @MainActor
    func testLoadedLargeDetailDoesNotGrowMinimumWindowAcrossBothStyles() async throws {
        try display()
        let dir = try directory(), image = try asset(in: dir, width: 1200, height: 750)
        let controller = RiftHistoryController(mediaDirectory: dir, onRestore: { _ in }, onRemove: { _ in }, onReveal: { _ in })
        defer { controller.close() }
        controller.update(entries: [RiftHistoryEntry(record: AssetRecord(image: image, sequence: 1))])
        controller.show()
        let table: NSTableView = try find("history.current.table", in: controller.window)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let detail: NSImageView = try find("history.detail.image", in: controller.window)
        try await waitUntil { detail.image != nil }
        let bitmap = try XCTUnwrap(detail.image), minimum = controller.window.minSize
        // The decoded image really exceeds the current-style detail viewport;
        // an empty or tiny fixture would miss the observed intrinsic-size bug.
        XCTAssertGreaterThan(bitmap.size.width, minimum.width - 152 - 260 - 1 - 48)
        controller.window.setFrame(NSRect(origin: controller.window.frame.origin, size: minimum), display: true)
        for style in [HistoryDisplayStyle.current, .imageGrid, .current] {
            controller.updateDisplayStyle(style)
            controller.window.contentView?.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            controller.window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(controller.window.frame.width, minimum.width, accuracy: 1)
            XCTAssertEqual(controller.window.frame.height, minimum.height, accuracy: 1)
            XCTAssertLessThanOrEqual(try XCTUnwrap(controller.window.contentView).fittingSize.width, minimum.width + 1)
            XCTAssertEqual(detail.imageScaling, .scaleProportionallyUpOrDown)
            XCTAssertTrue(detail.image === bitmap, "Style changes must retain the already decoded detail")
            XCTAssertEqual(controller.selectedRecordID, image.id)
        }
    }

    @MainActor
    func testGridNativeDeselectThenSelectKeepsOriginalWindowAndMapsUUIDBackToTable() async throws {
        try display()
        let dir = try directory(), newer = try asset(in: dir), older = try asset(in: dir, date: Date().addingTimeInterval(-10))
        let controller = RiftHistoryController(mediaDirectory: dir, onRestore: { _ in }, onRemove: { _ in },
            onReveal: { _ in }, displayStyle: .imageGrid)
        defer { controller.close() }
        controller.update(entries: [newer, older].enumerated().map {
            RiftHistoryEntry(record: AssetRecord(image: $0.element, sequence: Int64(2 - $0.offset)))
        })
        controller.show()
        let collection: NSCollectionView = try find("history.grid", in: controller.window)
        let renderer = try XCTUnwrap(collection.delegate as? HistoryGridRenderer)
        let first = IndexPath(item: 0, section: 0), second = IndexPath(item: 1, section: 0)
        collection.selectItems(at: [first], scrollPosition: [])
        renderer.collectionView(collection, didSelectItemsAt: [first])
        controller.openOriginal(id: newer.id)
        let preview = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible })
        let zoom: NSSegmentedControl = try find("history.preview.zoom", in: preview)
        zoom.selectedSegment = 2; try invoke(zoom)
        // Exercise the native delegate sequence explicitly; this is not a
        // physical mouse claim, and no history/model state is changed by hand.
        collection.deselectItems(at: [first])
        renderer.collectionView(collection, didDeselectItemsAt: [first])
        collection.selectItems(at: [second], scrollPosition: [])
        renderer.collectionView(collection, didSelectItemsAt: [second])
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertTrue(preview.isVisible); XCTAssertEqual(zoom.selectedSegment, 2)
        XCTAssertTrue(preview.title.contains(String(older.id.uuidString.prefix(8))))
        XCTAssertEqual(controller.selectedRecordID, older.id)
        controller.updateDisplayStyle(.current)
        let table: NSTableView = try find("history.current.table", in: controller.window)
        XCTAssertEqual(table.selectedRow, 1); XCTAssertEqual(controller.selectedRecordID, older.id)
        XCTAssertTrue(preview.isVisible); XCTAssertEqual(zoom.selectedSegment, 2)
        XCTAssertTrue(collection.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(collection.numberOfSections, 0)
        controller.updateDisplayStyle(.imageGrid)
        XCTAssertEqual(collection.selectionIndexPaths, [second])
        XCTAssertEqual(controller.selectedRecordID, older.id)
        XCTAssertTrue(preview.isVisible); XCTAssertEqual(zoom.selectedSegment, 2)
    }

    @MainActor
    func testGridAccessibleCellsExposeIdentityAndSelectTheSameUUIDThroughNativeCollection() async throws {
        try display()
        let dir = try directory(), newer = try asset(in: dir), older = try asset(in: dir, date: Date().addingTimeInterval(-10))
        var revealed: [UUID] = []
        let controller = RiftHistoryController(mediaDirectory: dir, onRestore: { _ in XCTFail("AX selection must not restore") },
            onRemove: { _ in XCTFail("AX selection must not remove") }, onReveal: { revealed.append($0) }, displayStyle: .imageGrid)
        defer { controller.close() }
        controller.update(entries: [newer, older].enumerated().map {
            RiftHistoryEntry(record: AssetRecord(image: $0.element, sequence: Int64(2 - $0.offset)))
        })
        controller.show()
        let collection: NSCollectionView = try find("history.grid", in: controller.window)
        let first = IndexPath(item: 0, section: 0), second = IndexPath(item: 1, section: 0)
        try await waitUntil { collection.item(at: first) != nil && collection.item(at: second) != nil }
        let firstView = try XCTUnwrap(collection.item(at: first)?.view)
        let secondView = try XCTUnwrap(collection.item(at: second)?.view)
        // Read the actual native view's AX properties, not only its ordinary
        // NSUserInterfaceItemIdentifier. External AX/VoiceOver remains a
        // separately recorded candidate acceptance.
        XCTAssertTrue(secondView.isAccessibilityElement())
        XCTAssertEqual(secondView.accessibilityRole(), .cell)
        XCTAssertEqual(secondView.accessibilityIdentifier(), "history.grid.item." + older.id.uuidString)
        XCTAssertTrue(secondView.accessibilityLabel()?.contains(String(older.id.uuidString.prefix(8))) == true)
        XCTAssertTrue(secondView.accessibilityLabel()?.contains("80 × 40") == true)
        XCTAssertTrue(secondView.accessibilityChildren()?.isEmpty == true)
        XCTAssertFalse(secondView.isAccessibilitySelected())
        XCTAssertTrue(secondView.accessibilityPerformPress())
        XCTAssertEqual(controller.selectedRecordID, older.id)
        XCTAssertEqual(collection.selectionIndexPaths, [second])
        XCTAssertTrue(secondView.isAccessibilitySelected()); XCTAssertFalse(firstView.isAccessibilitySelected())
        XCTAssertTrue(revealed.isEmpty, "AX selection is not an image action")
        let reveal: NSButton = try find("history.reveal", in: controller.window)
        try invoke(reveal); XCTAssertEqual(revealed, [older.id])
        secondView.setAccessibilitySelected(false)
        XCTAssertNil(controller.selectedRecordID); XCTAssertTrue(collection.selectionIndexPaths.isEmpty)
        secondView.setAccessibilitySelected(true)
        XCTAssertEqual(controller.selectedRecordID, older.id)
        controller.updateDisplayStyle(.current)
        let table: NSTableView = try find("history.current.table", in: controller.window)
        XCTAssertEqual(table.selectedRow, 1)
        XCTAssertFalse(secondView.accessibilityPerformPress(), "Hidden renderer elements have no selection authority")
        controller.updateDisplayStyle(.imageGrid)
        controller.update(entries: [])
        XCTAssertFalse(secondView.accessibilityPerformPress(), "A removed UUID cannot select its replacement row")
        XCTAssertNil(controller.selectedRecordID)
    }

    func testGroupsUseCaptureDayAndRetainTheSharedOrdering() throws {
        let dir = try directory()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000), today = calendar.startOfDay(for: now)
        let dates = [today.addingTimeInterval(60), today.addingTimeInterval(-60), today.addingTimeInterval(-90_000)]
        let entries = try dates.enumerated().map { index, date in
            RiftHistoryEntry(record: AssetRecord(image: try asset(in: dir, date: date), sequence: Int64(index + 1)))
        }
        let shared = HistoryPresentation.matching(entries)
        let groups = HistoryGridSection.make(shared, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.title), ["今天", "昨天", "更早"])
        XCTAssertEqual(groups.flatMap(\.entries).map(\.id), shared.map(\.id))
        XCTAssertTrue(HistoryGridSection.make([], now: now, calendar: calendar).isEmpty)
    }

    @MainActor
    func testVisibleThumbnailsUseSequentialVerifiedDecodeAndPreserveSourceBytes() async throws {
        let dir = try directory()
        let assets = try (0..<3).map { _ in try asset(in: dir) }
        let before = try assets.map { try Data(contentsOf: dir.appendingPathComponent($0.fileName)) }
        let probe = HistoryGridDecodeProbe()
        let loader = HistoryPreviewLoader { request, cancellation in
            _ = probe.append(request.asset.id)
            return try HistoryPreviewDecode.load(request, cancellation: cancellation)
        }
        var loaded: [UUID] = []
        let thumbnails = HistoryGridThumbnailLoader(directory: dir, loader: loader, mayLoad: { true }, didLoad: { loaded.append($0) })
        defer { thumbnails.clear() }
        let entries = assets.enumerated().map { RiftHistoryEntry(record: AssetRecord(image: $0.element, sequence: Int64($0.offset + 1))) }
        thumbnails.update(visible: entries, backing: 2)
        try await waitUntil { loaded.count == 3 }
        XCTAssertEqual(loaded, assets.map(\.id)); XCTAssertEqual(probe.ids, assets.map(\.id))
        XCTAssertTrue(assets.allSatisfy { thumbnails.image(for: $0) != nil })
        thumbnails.update(visible: entries, backing: 2)
        XCTAssertEqual(thumbnails.requestCount, 3, "Verified cache avoids repeating the same visible requests")
        XCTAssertEqual(try assets.map { try Data(contentsOf: dir.appendingPathComponent($0.fileName)) }, before)
        try Data("replacement".utf8).write(to: dir.appendingPathComponent(assets[0].fileName))
        XCTAssertNil(thumbnails.image(for: assets[0]), "A changed file identity must not reuse cached pixels")
    }

    @MainActor
    func testOriginalOwnerPreemptsThumbnailsAndTheyStaySuspendedUntilPreviewCloses() async throws {
        let dir = try directory(), first = try asset(in: dir), second = try asset(in: dir), original = try asset(in: dir)
        let started = expectation(description: "first thumbnail decoder started")
        let finished = expectation(description: "original preview decoded")
        let release = DispatchSemaphore(value: 0), probe = HistoryGridDecodeProbe()
        let loader = HistoryPreviewLoader { request, cancellation in
            if probe.append(request.asset.id) == 1 {
                started.fulfill()
                guard release.wait(timeout: .now() + 3) == .success else { throw HistoryPreviewFailure.cancelled }
            }
            return try HistoryPreviewDecode.load(request, cancellation: cancellation)
        }
        var previewVisible = false, previewInvalidated = false, thumbnailIDs: [UUID] = []
        let thumbnails = HistoryGridThumbnailLoader(directory: dir, loader: loader,
            mayLoad: { !previewVisible }, didLoad: { thumbnailIDs.append($0) })
        defer { thumbnails.clear() }
        let entries = [first, second].enumerated().map { RiftHistoryEntry(record: AssetRecord(image: $0.element, sequence: Int64($0.offset + 1))) }
        thumbnails.update(visible: entries, backing: 1)
        await fulfillment(of: [started], timeout: 2)
        previewVisible = true
        let previewOwner = UUID()
        loader.request(owner: previewOwner, request: .init(asset: original, directory: dir, viewport: CGSize(width: 640, height: 480), backing: 1),
            invalidated: { previewInvalidated = true }) { result in
                if case .failure(let error) = result { XCTFail("Original preview failed: \(error)") }
                finished.fulfill()
            }
        thumbnails.update(visible: entries, backing: 1)
        release.signal()
        await fulfillment(of: [finished], timeout: 4)
        XCTAssertFalse(previewInvalidated); XCTAssertTrue(thumbnailIDs.isEmpty)
        XCTAssertEqual(probe.ids, [first.id, original.id], "Queued thumbnail must not preempt the original")
        loader.cancel(owner: previewOwner); previewVisible = false
        thumbnails.update(visible: [entries[1]], backing: 1)
        try await waitUntil { thumbnailIDs == [second.id] }
        XCTAssertFalse(previewInvalidated)
    }

    @MainActor
    func testSeparateThumbnailAndOriginalOwnersStillShareOneSerialDecodeLane() async throws {
        let dir = try directory(), first = try asset(in: dir), second = try asset(in: dir), original = try asset(in: dir)
        let started = expectation(description: "first thumbnail entered actual decoder")
        let originalFinished = expectation(description: "separate original owner decoded")
        let release = DispatchSemaphore(value: 0), probe = HistoryGridDecodeProbe()
        let decode: HistoryPreviewLoader.Decoder = { request, cancellation in
            probe.begin(request.asset.id); defer { probe.end() }
            if request.asset.id == first.id {
                started.fulfill()
                guard release.wait(timeout: .now() + 3) == .success else { throw HistoryPreviewFailure.cancelled }
            }
            return try HistoryPreviewDecode.load(request, cancellation: cancellation)
        }
        let thumbnailLoader = HistoryPreviewLoader(decoder: decode)
        let originalLoader = HistoryPreviewLoader(decoder: decode)
        var thumbnailIDs: [UUID] = [], originalInvalidated = false
        let thumbnails = HistoryGridThumbnailLoader(directory: dir, loader: thumbnailLoader,
            mayLoad: { true }, didLoad: { thumbnailIDs.append($0) })
        let originalOwner = UUID()
        defer { release.signal(); thumbnails.clear(); originalLoader.cancel(owner: originalOwner) }
        thumbnails.update(visible: [first, second].enumerated().map {
            RiftHistoryEntry(record: AssetRecord(image: $0.element, sequence: Int64($0.offset + 1)))
        }, backing: 1)
        await fulfillment(of: [started], timeout: 2)
        originalLoader.request(owner: originalOwner,
            request: .init(asset: original, directory: dir, viewport: CGSize(width: 640, height: 480), backing: 1),
            invalidated: { originalInvalidated = true }) { result in
                if case .failure(let error) = result { XCTFail("Original preview failed: \(error)") }
                originalFinished.fulfill()
            }
        release.signal()
        await fulfillment(of: [originalFinished], timeout: 4)
        try await waitUntil { thumbnailIDs == [first.id, second.id] }
        XCTAssertEqual(probe.maximumConcurrentDecodes, 1)
        XCTAssertEqual(probe.ids, [first.id, original.id, second.id], "The queued original runs before the next thumbnail")
        XCTAssertFalse(originalInvalidated)
        XCTAssertNotNil(thumbnails.loadedImage(for: first)); XCTAssertNotNil(thumbnails.loadedImage(for: second))
    }

    @MainActor
    func testBackingChangeRejectsLateOldDecodeAndRequestsNewResolution() async throws {
        let dir = try directory(), image = try asset(in: dir, width: 1200, height: 800)
        let started = expectation(description: "one-times request running")
        let release = DispatchSemaphore(value: 0), probe = HistoryGridDecodeProbe()
        let loader = HistoryPreviewLoader { request, _ in
            if probe.append(request.asset.id, backing: request.backing) == 1 {
                started.fulfill()
                guard release.wait(timeout: .now() + 3) == .success else { throw HistoryPreviewFailure.cancelled }
            }
            // Emulate an already-entered native decode returning after cancel.
            return try HistoryPreviewDecode.load(request, cancellation: .init())
        }
        var deliveries = 0
        let thumbnails = HistoryGridThumbnailLoader(directory: dir, loader: loader, mayLoad: { true }, didLoad: { _ in deliveries += 1 })
        defer { thumbnails.clear() }
        let entries = [RiftHistoryEntry(record: AssetRecord(image: image, sequence: 1))]
        thumbnails.update(visible: entries, backing: 1)
        await fulfillment(of: [started], timeout: 2)
        thumbnails.update(visible: entries, backing: 2); release.signal()
        try await waitUntil { deliveries == 1 }
        XCTAssertEqual(probe.backings, [1, 2]); XCTAssertEqual(deliveries, 1)
        let loaded = try XCTUnwrap(thumbnails.loadedImage(for: image))
        XCTAssertGreaterThan(loaded.image.width, 180, "The completed bitmap must not be the old 1× thumbnail")
        XCTAssertLessThanOrEqual(loaded.image.width, 360)
        XCTAssertGreaterThan(loaded.image.height, 112); XCTAssertLessThanOrEqual(loaded.image.height, 225)
    }

    @MainActor private func resolved(_ color: NSColor, in appearance: NSAppearance) throws -> NSColor {
        var result: NSColor?
        appearance.performAsCurrentDrawingAppearance { result = color.usingColorSpace(.sRGB) }
        return try XCTUnwrap(result)
    }

    private func assertColor(_ actual: NSColor, _ expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.0001, file: file, line: line)
    }

    @MainActor
    func testCachedGridPaletteFollowsRequestedAppearanceAndKeepsFrozenBrand() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua)), dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let matches: [NSAppearance.Name] = [.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua, .aqua, .darkAqua]
        guard light.bestMatch(from: matches) == .aqua, dark.bestMatch(from: matches) == .darkAqua else {
            throw XCTSkip("Ordinary palette NOT_RUN while the system supplies high-contrast matching; no preference changed")
        }
        let colors: [(NSColor, UInt32, UInt32)] = [(HistoryGridStyle.surface, 0xFFFFFF, 0x292D2B),
            (HistoryGridStyle.secondarySurface, 0xFBFAF8, 0x242825), (HistoryGridStyle.ink, 0x282B29, 0xE6E9E5),
            (HistoryGridStyle.secondary, 0x686F69, 0xA3ABA4), (HistoryGridStyle.accent, 0x19B7A4, 0x19B7A4),
            (HistoryGridStyle.deep, 0x087C70, 0x087C70)]
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        for (cached, lightHex, darkHex) in colors {
            assertColor(try resolved(cached, in: light), rgb(lightHex))
            assertColor(try resolved(cached, in: dark), rgb(darkHex))
            assertColor(try resolved(cached, in: light), rgb(lightHex))
        }
    }

    @MainActor
    func testCachedGridTextAndBorderResolveActualHighContrastWithinItsAppearance() throws {
        let actual = NSApplication.shared.effectiveAppearance
        let match = actual.bestMatch(from: [.accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua, .aqua, .darkAqua])
        guard match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua else {
            throw XCTSkip("Actual OS high-contrast appearance unavailable: NOT_RUN; no system preference changed")
        }
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        for (cached, system) in [(HistoryGridStyle.ink, NSColor.labelColor),
                                 (HistoryGridStyle.secondary, NSColor.labelColor),
                                 (HistoryGridStyle.border, NSColor.separatorColor)] {
            let before = try resolved(cached, in: light)
            assertColor(try resolved(cached, in: actual), try resolved(system, in: actual))
            assertColor(try resolved(cached, in: light), before)
        }
    }
}
