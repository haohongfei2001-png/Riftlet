import AppKit
import CryptoKit
import ImageIO
import RiftletCore
import UniformTypeIdentifiers
import XCTest
@testable import RiftletUI

private final class PreviewDecodeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started: [UUID] = []
    private var active = 0
    private(set) var maximumActive = 0
    func begin(_ id: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        started.append(id); active += 1; maximumActive = max(maximumActive, active)
        return started.count
    }
    func end() { lock.lock(); active -= 1; lock.unlock() }
    var identities: [UUID] { lock.lock(); defer { lock.unlock() }; return started }
}

final class HistoryPreviewTests: XCTestCase {
    private func fixture(width: Int = 3840, height: Int = 2160, orientation: Int = 1) throws -> (URL, ImportedAsset) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(red: 0.12, green: 0.2, blue: 0.4, alpha: 1))
        context.setLineWidth(1)
        for y in stride(from: 10, to: height, by: 17) {
            context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: width, y: y))
        }
        context.strokePath()
        let id = UUID(), name = id.uuidString + (orientation == 1 ? ".png" : ".tiff")
        let url = directory.appendingPathComponent(name)
        let type = orientation == 1 ? UTType.png : UTType.tiff
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()),
            [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = try Data(contentsOf: url)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return (directory, ImportedAsset(id: id, sourceKey: "preview-fixture-" + id.uuidString,
            fileName: name, sha256: hash, byteCount: Int64(bytes.count), pixelWidth: width, pixelHeight: height,
            mediaType: type.preferredMIMEType ?? "image/png", firstSeenAt: Date(timeIntervalSince1970: 1_700_000_000), origin: .synthetic))
    }

    func testActualViewportDecodeUsesRequestedBackingAndLeavesOriginalBytesUnchanged() throws {
        let (directory, asset) = try fixture()
        let original = try Data(contentsOf: directory.appendingPathComponent(asset.fileName))
        for (backing, width, height) in [(CGFloat(1), 640, 360), (CGFloat(2), 1280, 720)] {
            let loaded = try HistoryPreviewDecode.load(.init(asset: asset, directory: directory,
                viewport: CGSize(width: 640, height: 480), backing: backing), cancellation: .init())
            XCTAssertEqual(loaded.image.width, width); XCTAssertEqual(loaded.image.height, height)
            XCTAssertTrue(HistoryPreviewPlan.accepts(loaded.image))
            XCTAssertLessThanOrEqual(loaded.image.bytesPerRow * loaded.image.height, HistoryPreviewPlan.maximumBytes)
            XCTAssertTrue(loaded.identity.matches(loaded.url))
        }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(asset.fileName)), original)
    }

    func testTallSmallAndOrientedImagesPreserveFitWithoutUpsampling() throws {
        for (width, height, orientation, expectedWidth, expectedHeight) in [
            (96, 1200, 1, 32, 400), (80, 40, 1, 80, 40), (1200, 600, 6, 200, 400)
        ] {
            let (directory, asset) = try fixture(width: width, height: height, orientation: orientation)
            let loaded = try HistoryPreviewDecode.load(.init(asset: asset, directory: directory,
                viewport: CGSize(width: 600, height: 400), backing: 1), cancellation: .init())
            XCTAssertEqual(loaded.image.width, expectedWidth); XCTAssertEqual(loaded.image.height, expectedHeight)
            XCTAssertLessThanOrEqual(loaded.image.width * loaded.image.height, width * height)
        }
        let (directory, small) = try fixture(width: 80, height: 40)
        let retina = try HistoryPreviewDecode.load(.init(asset: small, directory: directory,
            viewport: CGSize(width: 640, height: 480), backing: 2), cancellation: .init())
        XCTAssertEqual(retina.image.width, 80); XCTAssertEqual(retina.image.height, 40)
        XCTAssertEqual(retina.displaySize(backing: 2), CGSize(width: 40, height: 20))
        XCTAssertEqual(retina.displaySize(backing: 2).width * 2, CGFloat(small.pixelWidth))
        XCTAssertEqual(retina.displaySize(backing: 1), CGSize(width: 80, height: 40))
    }

    func testLargeViewportPlansRespectPixelAndHighDepthByteBudgets() throws {
        let ordinary = try HistoryPreviewPlan.make(width: 20_000, height: 20_000,
            viewport: CGSize(width: 10_000, height: 10_000), backing: 2)
        XCTAssertLessThanOrEqual(ordinary.maxPixelSize * ordinary.maxPixelSize, 16_000_000)
        let deep = try HistoryPreviewPlan.make(width: 20_000, height: 20_000, depth: 16,
            viewport: CGSize(width: 10_000, height: 10_000), backing: 2)
        XCTAssertLessThan(deep.maxPixelSize, ordinary.maxPixelSize)
        XCTAssertLessThanOrEqual(deep.maxPixelSize * deep.maxPixelSize * 8, 64 * 1_024 * 1_024)
        XCTAssertThrowsError(try HistoryPreviewPlan.make(width: 20, height: 20,
            viewport: CGSize(width: CGFloat.infinity, height: 10), backing: 1))
    }

    func testMissingChangedAndSymlinkFilesAreRejectedWithoutReturningWrongAssetPixels() throws {
        let (directory, asset) = try fixture(width: 80, height: 40)
        let request = HistoryPreviewRequest(asset: asset, directory: directory, viewport: CGSize(width: 640, height: 480), backing: 2)
        let loaded = try HistoryPreviewDecode.load(request, cancellation: .init())
        let original = try Data(contentsOf: request.url)
        var modified = original; modified[modified.count / 2] ^= 1
        try modified.write(to: request.url)
        XCTAssertFalse(loaded.identity.matches(request.url))
        XCTAssertThrowsError(try HistoryPreviewDecode.load(request, cancellation: .init()))
        try FileManager.default.removeItem(at: request.url)
        XCTAssertThrowsError(try HistoryPreviewDecode.load(request, cancellation: .init()))
        let replacement = directory.appendingPathComponent("replacement.png")
        try original.write(to: replacement)
        try FileManager.default.createSymbolicLink(at: request.url, withDestinationURL: replacement)
        XCTAssertThrowsError(try HistoryPreviewDecode.load(request, cancellation: .init()))
        XCTAssertEqual(try Data(contentsOf: replacement), original)
    }

    @MainActor
    func testSingleFlightCoalescesABAAndDropsCancelledWindowGeneration() async throws {
        let (directory, asset) = try fixture(width: 120, height: 80)
        let (otherDirectory, otherAsset) = try fixture(width: 90, height: 60)
        let firstStarted = expectation(description: "first decoder running")
        let final = expectation(description: "only newest preview completes")
        let release = DispatchSemaphore(value: 0), probe = PreviewDecodeProbe()
        let loader = HistoryPreviewLoader { request, _ in
            let count = probe.begin(request.asset.id); defer { probe.end() }
            if count == 1 {
                firstStarted.fulfill()
                guard release.wait(timeout: .now() + 3) == .success else { throw HistoryPreviewFailure.cancelled }
            }
            // Emulate an ImageIO call that cannot be interrupted mid-decode.
            // Loader ownership must reject it even if decoding itself returns.
            return try HistoryPreviewDecode.load(request, cancellation: .init())
        }
        let owner = UUID()
        let request = HistoryPreviewRequest(asset: asset, directory: directory,
            viewport: CGSize(width: 640, height: 480), backing: 1)
        var completions: [String] = []
        loader.request(owner: owner, request: request, invalidated: {}) { _ in completions.append("old-A") }
        await fulfillment(of: [firstStarted], timeout: 2)
        let requestB = HistoryPreviewRequest(asset: otherAsset, directory: otherDirectory,
            viewport: CGSize(width: 640, height: 480), backing: 1)
        loader.request(owner: owner, request: requestB, invalidated: {}) { _ in completions.append("B") }
        loader.cancel(owner: owner) // Close while the first decode owns its bytes.
        loader.request(owner: owner, request: request, invalidated: {}) { result in
            if case .failure(let error) = result { XCTFail("Newest preview failed: \(error)") }
            completions.append("fresh-A"); final.fulfill()
        }
        release.signal()
        await fulfillment(of: [final], timeout: 3)
        XCTAssertEqual(completions, ["fresh-A"])
        XCTAssertEqual(probe.identities, [asset.id, asset.id], "Superseded middle request must never decode")
        XCTAssertEqual(probe.maximumActive, 1)
        loader.cancel(owner: owner)
    }

    @MainActor
    func testPreviewShellOpensBeforeThumbnailAndTracksSelectedIdentityWithoutQueueActions() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit display unavailable") }
        let (directory, asset) = try fixture(width: 80, height: 40)
        let other = ImportedAsset(sourceKey: "missing-preview-fixture", fileName: "missing.png",
            sha256: String(repeating: "0", count: 64), byteCount: 1,
            pixelWidth: 10, pixelHeight: 10, mediaType: "image/png", firstSeenAt: asset.firstSeenAt.addingTimeInterval(-1), origin: .synthetic)
        var actions = 0
        let controller = RiftHistoryController(mediaDirectory: directory,
            onRestore: { _ in actions += 1 }, onRemove: { _ in actions += 1 }, onReveal: { _ in actions += 1 })
        defer { controller.close() }
        controller.update(entries: [RiftHistoryEntry(record: AssetRecord(image: asset, sequence: 2)),
                                    RiftHistoryEntry(record: AssetRecord(image: other, sequence: 1, status: .unknown))])
        controller.show()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let table = try XCTUnwrap(NSApp.windows.compactMap(\.contentView).flatMap(descendants)
            .compactMap { $0 as? NSTableView }.first { $0.delegate === controller })
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(table.doubleAction), to: table.target, from: table))
        let preview = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible })
        XCTAssertTrue(preview.title.contains(String(asset.id.uuidString.prefix(8))))
        let status = try XCTUnwrap(preview.contentView.map(descendants)?.compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "history.preview.status" })
        XCTAssertTrue(status.stringValue.contains("正在加载"))
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertTrue(preview.title.contains(String(other.id.uuidString.prefix(8))))
        preview.performClose(nil)
        XCTAssertFalse(preview.isVisible); XCTAssertEqual(actions, 0)
    }

    @MainActor
    func testEmptyPreviewViewportLoadsVerifiedImageAndRemainsUsableAtMinimumSize() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit display unavailable") }
        let (directory, asset) = try fixture(width: 1280, height: 720)
        let original = try Data(contentsOf: directory.appendingPathComponent(asset.fileName))
        var actions = 0
        let controller = RiftHistoryController(mediaDirectory: directory,
            onRestore: { _ in actions += 1 }, onRemove: { _ in actions += 1 }, onReveal: { _ in actions += 1 })
        defer { controller.close() }
        controller.update(entries: [RiftHistoryEntry(record: AssetRecord(image: asset, sequence: 1))])
        controller.show()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let table = try XCTUnwrap(NSApp.windows.compactMap(\.contentView).flatMap(descendants)
            .compactMap { $0 as? NSTableView }.first { $0.delegate === controller })
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(table.doubleAction), to: table.target, from: table))
        let preview = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible })
        let content = try XCTUnwrap(preview.contentView)
        let image = try XCTUnwrap(descendants(content).compactMap { $0 as? NSImageView }
            .first { $0.identifier?.rawValue == "history.preview.image" })
        let status = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "history.preview.status" })
        XCTAssertNil(image.image, "The initial shell must not borrow the unverified thumbnail")
        for size in [preview.frame.size, NSSize(width: 360, height: 280)] {
            preview.setFrame(NSRect(origin: preview.frame.origin, size: size), display: true)
            content.layoutSubtreeIfNeeded()
            let emptyViewport = image.bounds.size
            XCTAssertGreaterThan(emptyViewport.width, 0)
            XCTAssertGreaterThan(emptyViewport.height, content.bounds.height / 2,
                "The image viewport, not the footer, must receive the available window height")
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while status.stringValue != "已按窗口显示" && ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(status.stringValue, "已按窗口显示", "viewport=\(image.bounds), visible=\(preview.isVisible)")
            XCTAssertNotNil(image.image)
            content.layoutSubtreeIfNeeded()
            XCTAssertEqual(image.bounds.size, emptyViewport,
                "Decoded bitmap dimensions must not change the viewport used to request it; scroll=\(image.enclosingScrollView?.frame ?? .zero), content=\(image.enclosingScrollView?.contentSize ?? .zero), style=\(image.enclosingScrollView?.scrollerStyle.rawValue ?? -1)")
            let scroll = try XCTUnwrap(image.enclosingScrollView)
            XCTAssertFalse(scroll.hasHorizontalScroller); XCTAssertFalse(scroll.hasVerticalScroller)
            for style in [NSScroller.Style.legacy, .overlay] {
                scroll.scrollerStyle = style; scroll.tile(); content.layoutSubtreeIfNeeded()
                XCTAssertEqual(scroll.contentSize,emptyViewport,"Fit mode cannot acquire a late native gutter")
            }
            XCTAssertTrue(preview.title.contains(String(asset.id.uuidString.prefix(8))))
        }
        XCTAssertEqual(actions, 0)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(asset.fileName)), original)
    }

    @MainActor
    func testValidPNGReplacementNeverAppearsUnderOriginalPreviewIdentity() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit display unavailable") }
        let (directory, assetA) = try fixture(width: 80, height: 40)
        let (otherDirectory, assetB) = try fixture(width: 120, height: 90)
        let bytesB = try Data(contentsOf: otherDirectory.appendingPathComponent(assetB.fileName))
        // A remains the immutable database identity. Its private pathname now
        // contains another valid image, so the old thumbnail cache can show B.
        try bytesB.write(to: directory.appendingPathComponent(assetA.fileName), options: .atomic)
        var actions = 0
        let controller = RiftHistoryController(mediaDirectory: directory,
            onRestore: { _ in actions += 1 }, onRemove: { _ in actions += 1 }, onReveal: { _ in actions += 1 })
        defer { controller.close() }
        controller.update(entries: [RiftHistoryEntry(record: AssetRecord(image: assetA, sequence: 1))])
        controller.show()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let table = try XCTUnwrap(NSApp.windows.compactMap(\.contentView).flatMap(descendants)
            .compactMap { $0 as? NSTableView }.first { $0.delegate === controller })
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let historyContent = try XCTUnwrap(table.window?.contentView)
        let detail = try XCTUnwrap(descendants(historyContent).compactMap { $0 as? NSImageView }
            .first { $0.identifier?.rawValue == "history.detail.image" })
        let thumbnailDeadline = ProcessInfo.processInfo.systemUptime + 2
        while detail.image == nil && ProcessInfo.processInfo.systemUptime < thumbnailDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(detail.image, "Exercise the previously unsafe ready-thumbnail fallback")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(table.doubleAction), to: table.target, from: table))
        let preview = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible })
        let content = try XCTUnwrap(preview.contentView)
        let image = try XCTUnwrap(descendants(content).compactMap { $0 as? NSImageView }
            .first { $0.identifier?.rawValue == "history.preview.image" })
        let status = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "history.preview.status" })
        content.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(image.bounds.width, 0)
        XCTAssertGreaterThan(image.bounds.height, content.bounds.height / 2,
            "A rejected image still needs an empty viewport so validation can start")
        XCTAssertNil(image.image, "An unverified thumbnail must never flash under A's title")
        let decodeDeadline = ProcessInfo.processInfo.systemUptime + 2
        while !status.stringValue.contains("无法加载") && ProcessInfo.processInfo.systemUptime < decodeDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(status.stringValue.contains("无法加载"),
            "status=\(status.stringValue), viewport=\(image.bounds), visible=\(preview.isVisible)")
        XCTAssertNil(image.image, "Rejected replacement must not leave B displayed as A")
        XCTAssertTrue(preview.title.contains(String(assetA.id.uuidString.prefix(8))))
        XCTAssertEqual(actions, 0)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(assetA.fileName)), bytesB)
    }
    @MainActor func testExplicitOriginalOutsideHistoryPageHasZoomAndBalancedFence() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit display unavailable") }
        let (directory,asset) = try fixture(width:1280,height:720)
        var fence:[Bool]=[]; var actions=0
        let controller=RiftHistoryController(mediaDirectory:directory,onRestore:{_ in actions += 1},onRemove:{_ in actions += 1},onReveal:{_ in actions += 1})
        defer {controller.close()}
        controller.onPreviewVisibilityChanged={fence.append($0)}
        controller.update(entries:[])
        controller.openOriginal(entry:.init(record:AssetRecord(image:asset,sequence:1)))
        XCTAssertFalse(controller.isVisible,"Direct original does not require opening or replacing history page")
        let panel=try XCTUnwrap(NSApp.windows.first{$0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible})
        func descendants(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap(descendants)}
        let content=try XCTUnwrap(panel.contentView)
        let zoom=try XCTUnwrap(descendants(content).compactMap{$0 as? NSSegmentedControl}.first{$0.identifier?.rawValue == "history.preview.zoom"})
        let image=try XCTUnwrap(descendants(content).compactMap{$0 as? NSImageView}.first{$0.identifier?.rawValue == "history.preview.image"})
        for segment in [1,2] {
            zoom.selectedSegment=segment;_ = zoom.sendAction(zoom.action,to:zoom.target)
            XCTAssertEqual(image.frame.size,CGSize(width:1280*segment,height:720*segment))
            let scroll = try XCTUnwrap(image.enclosingScrollView)
            XCTAssertTrue(scroll.hasHorizontalScroller); XCTAssertTrue(scroll.hasVerticalScroller)
            let deadline=ProcessInfo.processInfo.systemUptime+2
            while image.image == nil && ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(nanoseconds:20_000_000)}
            XCTAssertNotNil(image.image)
        }
        panel.close();XCTAssertEqual(fence,[true,false]);XCTAssertEqual(actions,0)
    }

}
