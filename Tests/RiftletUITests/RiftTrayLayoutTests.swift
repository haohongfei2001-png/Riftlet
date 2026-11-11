import AppKit
import RiftletCapture
import RiftletCore
import XCTest
@testable import RiftletUI

final class RiftTrayLayoutTests: XCTestCase {
    @MainActor func testTintChangesOnlyGlassDecorationAndKeepsPresetOpacityAndContrast() throws {
        let source = NSColor(srgbRed: 0.600, green: 0.477, blue: 0.980, alpha: 0.53)
        XCTAssertTrue(RiftTrayColors.violetGlass.tint(source) === source)
        XCTAssertTrue(RiftTrayColors.system.tint(source) === source)
        let gray = try XCTUnwrap(RiftTrayColors.custom(hue: 120, strength: 0).tint(source).usingColorSpace(.sRGB))
        XCTAssertEqual(gray.redComponent, gray.greenComponent, accuracy: 0.0001)
        XCTAssertEqual(gray.greenComponent, gray.blueComponent, accuracy: 0.0001)
        let half = RiftTrayColors.custom(hue: 120, strength: 0.5).tint(source)
        let full = RiftTrayColors.custom(hue: 120, strength: 1).tint(source)
        XCTAssertGreaterThan(half.greenComponent, half.redComponent)
        XCTAssertGreaterThan(full.greenComponent - full.redComponent, half.greenComponent - half.redComponent)
        XCTAssertEqual(full.alphaComponent, source.alphaComponent)
        func luminance(_ color: NSColor) -> CGFloat {
            func linear(_ x: CGFloat) -> CGFloat { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return linear(color.redComponent) * 0.2126 + linear(color.greenComponent) * 0.7152 + linear(color.blueComponent) * 0.0722
        }
        for color in [gray, half, full] { XCTAssertEqual(luminance(color), luminance(source), accuracy: 0.0001) }
        XCTAssertGreaterThan(RiftTrayColors.custom(hue: 0, strength: 1).tint(source).redComponent, full.redComponent)

        for style in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: style))
            for clear in [true, false] {
                let preset = RiftTrayGlassPalette(colors: .violetGlass, appearance: appearance, clearGlass: clear)
                let custom = RiftTrayGlassPalette(colors: .custom(hue: 180, strength: 1), appearance: appearance, clearGlass: clear)
                XCTAssertEqual(custom.blurOpacity, preset.blurOpacity)
                XCTAssertEqual(custom.material.alphaComponent, preset.material.alphaComponent)
                XCTAssertEqual(custom.key.alphaComponent, preset.key.alphaComponent)
                XCTAssertEqual(custom.keyFoot.alphaComponent, preset.keyFoot.alphaComponent)
                XCTAssertEqual(custom.rim, preset.rim)
                XCTAssertEqual(custom.keyRim, preset.keyRim)
                // Some macOS versions resolve an explicit contrast name to Aqua when the system setting is off.
                if preset.ink == .labelColor {
                    XCTAssertEqual(custom.ink, .labelColor)
                }
            }
        }
    }

    private let display = CGRect(x: -1280, y: 40, width: 1280, height: 800)
    private func assets(_ count: Int) -> [AssetRecord] {
        let sizes = [(1200, 800), (9, 12), (5, 4000), (12000, 4)]
        return (0..<count).map { n in
            let id = UUID(), size = sizes[n % sizes.count]
            return AssetRecord(image: ImportedAsset(id: id, sourceKey: "tray-\(id)", fileName: "\(id).png",
                sha256: String(repeating: "d", count: 64), byteCount: 80, pixelWidth: size.0,
                pixelHeight: size.1, mediaType: "image/png", origin: .synthetic), sequence: Int64(n+1))
        }
    }
    private func layout(_ assets: [AssetRecord], capture: Bool = true, menu: RiftTrayMenuState? = nil, first: Int = 0,
                        configuration: RiftConfiguration = .init(), scale: Double = 2) -> RiftLayoutResult {
        RiftTrayLayout.make(records: assets, visibleFrame: display, configuration: configuration,
                            firstVisibleIndex: first, backingScale: scale, captureEnabled: capture, menu: menu)
    }
    func testCountMatrixStableBoundsQueueOrderAndMenuExclusion() {
        let compact = layout([]).surfaceFrame
        let full = layout(assets(3)).surfaceFrame
        XCTAssertEqual(full.width, display.width / 8, accuracy: 0.5)
        XCTAssertEqual(compact.width, full.width)
        XCTAssertEqual(full.height / full.width, 212 / 246.0, accuracy: 0.005)
        XCTAssertEqual(compact.height / full.width, 115 / 246.0, accuracy: 0.005)
        XCTAssertEqual(compact.minY, full.minY)
        let openPageOrdinals: [(Int, [Int])] = [(0, []), (1, []), (2, [1, 2]), (3, [2, 3]),
                                                (4, [3, 4]), (5, [4, 5]), (10, [9, 10])]
        for (count, ordinals) in openPageOrdinals {
            let records = assets(count)
            for enabled in [true, false] {
                let closed = layout(records, capture: enabled)
                XCTAssertEqual(closed.rows.map(\.assetID), records.prefix(3).map(\.id))
                XCTAssertTrue(closed.captureMenuFrame.isEmpty)
                XCTAssertEqual(!closed.captureSlot.isEmpty, enabled && count <= 3)
                if count == 0 && !enabled { XCTAssertTrue(closed.surfaceFrame.isEmpty); continue }
                XCTAssertEqual(closed.surfaceFrame, count >= 2 ? full : compact)
                for row in closed.rows {
                    XCTAssertTrue(closed.surfaceFrame.contains(row.frame))
                    XCTAssertFalse(row.frame.intersects(closed.captureSlot))
                }
            }
            // The camera can only open on a page where it actually has a slot.
            let tail = layout(records, first: Int.max)
            XCTAssertFalse(tail.captureSlot.isEmpty)
            let menu = RiftTrayMenuState(openingLayout: tail)
            let open = layout(records, menu: menu, first: tail.firstVisibleIndex)
            XCTAssertEqual(open.surfaceFrame, tail.surfaceFrame)
            XCTAssertTrue(open.captureSlot.isEmpty)
            XCTAssertFalse(open.captureMenuFrame.isEmpty)
            XCTAssertEqual(open.firstVisibleIndex, tail.firstVisibleIndex)
            XCTAssertEqual(open.rows.map(\.assetID), ordinals.map { records[$0 - 1].id })
            XCTAssertEqual(open.rows.map(\.ordinal), ordinals)
            for row in open.rows {
                XCTAssertTrue(open.surfaceFrame.contains(row.frame))
                XCTAssertGreaterThan(row.frame.minY, open.captureMenuFrame.maxY)
                XCTAssertGreaterThan(open.captureMenuFrame.width, 2 * row.frame.width)
            }
            XCTAssertEqual(layout(records, first: open.firstVisibleIndex), tail)
            let disabled = layout(records, capture: false, menu: menu, first: tail.firstVisibleIndex)
            XCTAssertEqual(disabled, layout(records, capture: false, first: tail.firstVisibleIndex))
        }
    }

    func testTrayUsesFullTargetDisplayOnBothSidesAndBackingScales() {
        let records = assets(3)
        for width: CGFloat in [768, 1441, 1920, 2560] {
            let display = CGRect(x: -width, y: 300, width: width, height: 900)
            let visible = display.insetBy(dx: 35, dy: 20)
            for scale: CGFloat in [1, 2] {
                for placement in [RiftPlacement.leftMiddle, .rightMiddle] {
                    var configuration = RiftConfiguration()
                    configuration.placement = placement
                    let layout = RiftTrayLayout.make(records: records, visibleFrame: visible,
                        configuration: configuration, firstVisibleIndex: 0, backingScale: scale,
                        captureEnabled: true, menu: nil, displayFrame: display)
                    XCTAssertEqual(layout.surfaceFrame.width, width / 8, accuracy: 0.5 / scale)
                    XCTAssertTrue(visible.contains(layout.surfaceFrame))
                    XCTAssertEqual(layout.rows.count, 3)
                    XCTAssertTrue(layout.surfaceFrame.contains(layout.captureSlot))
                }
            }
        }
    }

    func testReferenceGeometryAndSingleImageFillMotionAtBothScales() throws {
        let records = assets(3)
        var c = RiftConfiguration()
        c.placement = .rightMiddle
        c.outerInset = 16
        // At 1968 pt the native one-eighth rule reproduces the reference’s 246-unit interior.
        let frame = CGRect(x: 0, y: 0, width: 1968, height: 910)
        for scale in [1.0, 2.0] {
            func measure(_ count: Int, menu: RiftTrayMenuState? = nil) -> RiftLayoutResult {
                RiftTrayLayout.make(records: Array(records.prefix(count)), visibleFrame: frame,
                                    configuration: c, firstVisibleIndex: 0, backingScale: scale,
                                    captureEnabled: true, menu: menu,
                                    displayFrame: CGRect(x: 0, y: 0, width: 1968, height: 941))
            }
            let full = measure(3)
            XCTAssertEqual(full.surfaceFrame.minX, 1706)
            XCTAssertEqual(full.surfaceFrame.minY, 308.5, accuracy: 0.5)
            XCTAssertEqual(full.surfaceFrame.size, CGSize(width: 246, height: 212))
            XCTAssertEqual(full.rows[0].frame.width, 113.5, accuracy: 0.5)
            XCTAssertEqual(full.rows[0].frame.height, 80)
            XCTAssertEqual(full.rows[0].frame.minX - full.surfaceFrame.minX, 7)
            XCTAssertEqual(full.rows[1].frame.minX - full.rows[0].frame.maxX, 5, accuracy: 1)
            XCTAssertEqual(full.rows[0].frame.minY - full.rows[2].frame.maxY, 17, accuracy: 1)
            let single = measure(1)
            XCTAssertEqual(single.surfaceFrame.height, 115)
            let openedOverExisting = measure(1, menu: .init(openingLayout: single))
            XCTAssertTrue(openedOverExisting.rows.isEmpty)
            XCTAssertEqual(openedOverExisting.surfaceFrame, single.surfaceFrame)
            XCTAssertEqual(openedOverExisting.captureMenuFrame.width, 232)
            var emptyMenu = RiftTrayMenuState(openingLayout: measure(0))
            let openedOverEmpty = measure(0, menu: emptyMenu)
            XCTAssertEqual(openedOverEmpty.surfaceFrame, single.surfaceFrame)
            emptyMenu.receiveCaptures([records[0].id])
            let arrival = measure(1, menu: emptyMenu)
            let arrivedRow = try XCTUnwrap(arrival.rows.first)
            XCTAssertEqual(arrival.surfaceFrame, full.surfaceFrame)
            XCTAssertEqual(arrival.captureMenuFrame, openedOverEmpty.captureMenuFrame)
            XCTAssertEqual(arrivedRow.assetID, single.rows[0].assetID)
            XCTAssertEqual(arrivedRow.frame.minY - single.rows[0].frame.minY, 97, accuracy: 1)
            for row in full.rows {
                let card = try XCTUnwrap(row.trayCardFrame)
                XCTAssertTrue(card.insetBy(dx: -0.001, dy: -0.001).contains(row.imageFrame))
                let slot = CGRect(origin: .zero, size: row.frame.size).insetBy(dx: -0.001, dy: -0.001)
                XCTAssertTrue(slot.contains(card))
            }
        }
    }

    func testFourthImageAndLastButtonAreBothReachableWithoutChangingIDs() {
        var c = RiftConfiguration()
        c.visibleCountPreference = 10
        for count in [4,8,10] {
            let records = assets(count)
            let start = layout(records,configuration: c)
            XCTAssertEqual(start.rows.count,4)
            XCTAssertTrue(start.hasLater)
            XCTAssertTrue(start.captureSlot.isEmpty)
            let last = layout(records, first: Int.max, configuration: c)
            XCTAssertEqual(last.rows.map(\.assetID), records.suffix(3).map(\.id))
            XCTAssertFalse(last.captureSlot.isEmpty)
            XCTAssertFalse(last.hasLater)
            let lastWithoutButton = layout(records,capture:false,first:Int.max,configuration:c)
            XCTAssertEqual(lastWithoutButton.rows.map(\.assetID),records.suffix(4).map(\.id))
        }
    }

    func testFitOcclusionEdgesAndSmallImage() {
        var c = RiftConfiguration()
        c.visibleCountPreference = 4
        let records = assets(4)
        for placement in RiftPlacement.allCases {
            c.placement = placement
            for scale in [1.0,2.0] {
                c.trayOcclusion = 0
                let full = layout(records,capture:false,configuration:c,scale:scale)
                XCTAssertTrue(display.contains(full.surfaceFrame))
                for (i,row) in full.rows.enumerated() {
                    let source = records[i].image
                    XCTAssertEqual(row.imageFrame,row.imageClipFrame)
                    XCTAssertLessThanOrEqual(row.imageFrame.width * scale,CGFloat(source.pixelWidth))
                    XCTAssertLessThanOrEqual(row.imageFrame.height * scale,CGFloat(source.pixelHeight))
                    XCTAssertEqual(row.imageFrame.width/row.imageFrame.height,
                                   CGFloat(source.pixelWidth)/CGFloat(source.pixelHeight),accuracy:1e-8)
                }
                c.trayOcclusion = 0.4
                let masked = layout(records,capture:false,configuration:c,scale:scale)
                XCTAssertEqual(masked.rows.map(\.assetID),full.rows.map(\.assetID))
                for row in masked.rows {
                    XCTAssertEqual(row.imageClipFrame.width, 0.6 * row.imageFrame.width, accuracy: 1e-8)
                    XCTAssertTrue(row.containsSelectionPoint(CGPoint(x:row.imageClipFrame.midX,y:row.imageClipFrame.midY)))
                }
            }
        }
    }

    @MainActor func testFourAccessibleControlsRouteFavoritesThenDefaultFromLeftToRightOnBothEdges() throws {
        let records = assets(2)
        func label(_ mode: ScreenshotMode?) -> String {
            switch mode {
            case .window: return "窗口截图"
            case .region: return "区域截图"
            case .fullScreen: return "全屏截图"
            case nil: return "未设置"
            }
        }
        for placement in [RiftPlacement.leftMiddle, .rightMiddle] {
            var configuration = RiftConfiguration()
            configuration.placement = placement
            let closed = layout(records, configuration: configuration)
            XCTAssertEqual(closed.surfaceFrame.midX < display.midX, placement == .leftMiddle)
            let open = layout(records, menu: .init(openingLayout: closed), configuration: configuration)
            let surface = RiftTraySurfaceView(frame: CGRect(origin: .zero, size: closed.surfaceFrame.size))
            var pressed: [ScreenshotMode] = []
            surface.onCapture = { pressed.append($0) }
            for mode in ScreenshotMode.allCases {
                let automatic = configuration.trayFavoriteModes(defaultMode: mode)
                for choices: [ScreenshotMode?] in [automatic, [.region, .window, .region]] {
                    surface.update(layout: closed, colors: .violetGlass, defaultMode: mode, favoriteModes: choices, reduceMotion: true)
                    let camera = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSButton }.first { !$0.isHidden })
                    XCTAssertEqual(camera.accessibilityLabel(), "展开截图方式")
                    XCTAssertEqual(camera.frame, closed.captureSlot.offsetBy(dx: -closed.surfaceFrame.minX, dy: -closed.surfaceFrame.minY))
                    surface.update(layout: open, colors: .violetGlass, defaultMode: mode, favoriteModes: choices, reduceMotion: true)
                    let buttons = surface.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }
                        .sorted { $0.frame.minX < $1.frame.minX }
                    XCTAssertEqual(buttons.count, 4)
                    let favoriteLabels = choices.enumerated().map { "常用截图 \($0.offset + 1)，" + label($0.element) }
                    let expected = favoriteLabels + ["默认截图，" + label(mode)]
                    XCTAssertEqual(buttons.compactMap { $0.accessibilityLabel() }, expected)
                    XCTAssertTrue(buttons.last === camera)
                    XCTAssertTrue(zip(buttons, buttons.dropFirst()).allSatisfy { $0.frame.maxX <= $1.frame.minX && $0.frame.minY == $1.frame.minY })
                    XCTAssertEqual(buttons.map(\.isEnabled), (choices + [mode]).map { $0 != nil })
                    let enabled = buttons.filter(\.isEnabled)
                    for (index, button) in enabled.enumerated() {
                        XCTAssertTrue(button.nextKeyView === enabled[(index + 1) % enabled.count])
                    }
                    pressed.removeAll()
                    for button in buttons { button.performClick(nil) }
                    XCTAssertEqual(pressed, choices.compactMap { $0 } + [mode])
                }
            }
        }
    }

    @MainActor private func settle(_ panel: RiftPanelController, sample: () throws -> Void = {}) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while panel.diagnosticSnapshot.isTransitioning && ProcessInfo.processInfo.systemUptime < deadline {
            try sample()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(panel.diagnosticSnapshot.isTransitioning)
    }

    @MainActor func testOpeningAndClosingPushesTheFirstExistingUUIDThroughTheTopEdge() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer required") }
        var c = RiftConfiguration()
        c.desktopForm = .tray
        c.shiftDuration = 0.65
        for count in [1, 3] {
            var selections: [UUID] = []
            let panel = RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
                                            configuration: c, reduceMotionOverride: { false }, onSelect: { selections.append($0) })
            defer { panel.close() }
            let records = assets(count)
            panel.setTrayCapture(enabled: true, defaultMode: .window)
            panel.render(records)
            let closedRows = panel.diagnosticSnapshot.rows
            XCTAssertEqual(closedRows.map(\.assetID), records.map(\.id))
            let first = try XCTUnwrap(closedRows.first)
            let visual = try XCTUnwrap(NSApp.window(withWindowNumber: first.windowNumber))
            let hit = try XCTUnwrap(NSApp.window(withWindowNumber: first.imageInputWindowNumber))
            let surface = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.contentView is RiftTraySurfaceView })
            let closedFrame = surface.frame

            panel.setTrayExpanded(true)
            var sawClippedExit = false
            try settle(panel) {
                XCTAssertEqual(surface.frame, closedFrame)
                if !sawClippedExit, visual.isVisible, visual.frame.minY > first.frame.minY + 1,
                   visual.frame.height > 1, visual.frame.height < first.frame.height - 1 {
                    XCTAssertLessThanOrEqual(visual.frame.maxY, closedFrame.maxY + 1)
                    XCTAssertFalse(hit.isVisible && !hit.ignoresMouseEvents)
                    XCTAssertFalse(visual.contentView?.accessibilityPerformPress() == true)
                    sawClippedExit = true
                }
            }
            XCTAssertTrue(sawClippedExit, "The displaced thumbnail must visibly cross the top edge")
            let upper = panel.diagnosticSnapshot.rows
            XCTAssertEqual(surface.frame, closedFrame)
            XCTAssertEqual(upper.map(\.assetID), records.dropFirst().map(\.id))
            XCTAssertEqual(upper.map(\.frame), closedRows.prefix(upper.count).map(\.frame))
            XCTAssertFalse(visual.isVisible)

            panel.setTrayExpanded(false)
            var sawClippedReturn = false
            try settle(panel) {
                XCTAssertEqual(surface.frame, closedFrame)
                if !sawClippedReturn, let current = panel.diagnosticSnapshot.rows.first(where: { $0.assetID == first.assetID }),
                   current.frame.minY > first.frame.minY + 1, current.frame.height > 1,
                   current.frame.height < first.frame.height - 1 {
                    XCTAssertLessThanOrEqual(current.frame.maxY, closedFrame.maxY + 1)
                    if let currentHit = NSApp.window(withWindowNumber: current.imageInputWindowNumber),
                       currentHit.isVisible && !currentHit.ignoresMouseEvents {
                        XCTAssertTrue(current.frame.insetBy(dx: -1, dy: -1).contains(currentHit.frame))
                    }
                    sawClippedReturn = true
                }
            }
            XCTAssertTrue(sawClippedReturn, "Closing must bring the displaced thumbnail back through the top edge")
            let restored = panel.diagnosticSnapshot.rows
            XCTAssertEqual(restored.map(\.assetID), closedRows.map(\.assetID))
            XCTAssertEqual(restored.map(\.frame), closedRows.map(\.frame))
            XCTAssertEqual(surface.frame, closedFrame)
            XCTAssertTrue(selections.isEmpty)
            let returned = try XCTUnwrap(restored.first)
            let view = try XCTUnwrap(NSApp.window(withWindowNumber: returned.windowNumber)?.contentView)
            XCTAssertTrue(view.accessibilityPerformPress())
            XCTAssertEqual(selections, [first.assetID])
        }
    }

    @MainActor func testFirstScreenshotArrivingOverOpenMenuReturnsWithTheGlassOnCollapse() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer required") }
        var c = RiftConfiguration()
        c.desktopForm = .tray
        c.shiftDuration = 0.65
        let panel = RiftPanelController(mediaDirectory: FileManager.default.temporaryDirectory,
                                        configuration: c, reduceMotionOverride: { false }, onSelect: { _ in })
        defer { panel.close() }
        let one = assets(1)
        panel.setTrayCapture(enabled: true, defaultMode: .window)
        panel.render([])
        let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.contentView is RiftTraySurfaceView })
        let compactHeight = window.frame.height
        panel.setTrayExpanded(true)
        try settle(panel)
        XCTAssertTrue(panel.diagnosticSnapshot.rows.isEmpty)
        XCTAssertEqual(window.frame.height, compactHeight)
        panel.render(one)
        try settle(panel)
        let fullHeight = window.frame.height
        XCTAssertGreaterThan(fullHeight, compactHeight)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), one.map(\.id))
        panel.setTrayExpanded(false)
        var intermediate = false
        try settle(panel) {
            if window.frame.height > compactHeight + 1 && window.frame.height < fullHeight - 1 {
                let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first)
                XCTAssertEqual(row.assetID, one[0].id)
                XCTAssertTrue(window.frame.insetBy(dx: -1, dy: -1).contains(row.imageInputFrame))
                intermediate = true
            }
        }
        XCTAssertTrue(intermediate, "Glass must follow the moving row before reaching its compact height")
        XCTAssertEqual(window.frame.height, compactHeight)
        XCTAssertEqual(panel.diagnosticSnapshot.rows.map(\.assetID), one.map(\.id))
    }

    func testExpandedArrivalsRetainQueueOrdinalsAndManualPagingReleasesTheirPriority() {
        let records = assets(6)
        let before = layout(Array(records.prefix(2)))
        var menu = RiftTrayMenuState(openingLayout: before)
        menu.receiveCaptures([UUID(), records[2].id, records[2].id])
        let firstArrival = layout(Array(records.prefix(3)), menu: menu)
        XCTAssertEqual(firstArrival.rows.map(\.assetID), [records[2].id, records[0].id])
        XCTAssertEqual(firstArrival.rows.map(\.ordinal), [3, 1])
        menu.receiveCaptures([records[5].id, records[4].id])
        let next = layout(records, menu: menu)
        XCTAssertEqual(next.rows.map(\.ordinal), [6, 5])
        XCTAssertEqual(next.firstVisibleIndex, before.firstVisibleIndex)
        menu.userPaged()
        let paged = layout(records, menu: menu, first: 2)
        XCTAssertEqual(paged.rows.map(\.assetID), [records[2].id, records[3].id])
        XCTAssertEqual(paged.firstVisibleIndex, 2)
        let closed = layout(records, first: paged.firstVisibleIndex)
        XCTAssertEqual(closed.rows.map(\.ordinal), [3, 4, 5])
        XCTAssertEqual(closed.rows.map(\.assetID), records[2...4].map(\.id))
    }

    func testExplicitRecoveryCanRevealItsOwnUUIDInAnEmptyMenuWithoutBecomingACapture() {
        let records = assets(1)
        let empty = layout([])
        var menu = RiftTrayMenuState(openingLayout: empty)
        menu.prioritize([UUID()])
        let unrelated = layout(records, menu: menu)
        XCTAssertEqual(unrelated.surfaceFrame, empty.surfaceFrame)
        XCTAssertTrue(unrelated.rows.isEmpty)
        menu.prioritize([records[0].id])
        let recovered = layout(records, menu: menu)
        XCTAssertFalse(menu.receivedCapture)
        XCTAssertEqual(recovered.captureMenuFrame, unrelated.captureMenuFrame)
        XCTAssertGreaterThan(recovered.surfaceFrame.height, empty.surfaceFrame.height)
        XCTAssertEqual(recovered.rows.map(\.assetID), [records[0].id])
        XCTAssertEqual(recovered.rows.map(\.ordinal), [1])
    }
}
