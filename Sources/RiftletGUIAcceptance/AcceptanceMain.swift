import AppKit
import Darwin
import RiftletCore
import RiftletUI

@main
enum AcceptanceMain {
    @MainActor static func main() {
        let axFlags = ["--press-acceptance-asset", "--app-pid", "--app-path"]
        if CommandLine.arguments.contains(where: { axFlags.contains($0) }) {
            exit(AcceptanceAXPress.run(Array(CommandLine.arguments.dropFirst())))
        }
        if CommandLine.arguments.contains("--help") {
            print("""
            RiftletGUIAcceptance [--self-check]
            GUI: synthetic 2/3/12-image scenes, click/focus observations and delayed reorder.
            JSONL observations go to stdout; typed text is never included.
            --self-check validates fixtures/layout only and does not run GUI acceptance.
            --press-acceptance-asset UUID --app-pid PID --app-path /exact/Riftlet.app
              One bounded AXPress on one exact synthetic identifier; existing AX permission only.
            """)
            return
        }
        if CommandLine.arguments.contains("--self-check") {
            do {
                try SyntheticScene.selfCheck()
                print("RIFTLET_GUI_HELPER_SELF_CHECK_PASS: 12 synthetic PNGs; scenes 2/3/12; layout/status fixtures; GUI_NOT_RUN")
            } catch {
                fputs("RIFTLET_GUI_HELPER_SELF_CHECK_FAIL: \(error)\n", stderr)
                exit(1)
            }
            return
        }
        // AppKit must own the main loop outside an executing async actor job.
        runApplication()
    }

    @MainActor private static func runApplication() {
        let app = NSApplication.shared
        let delegate = AcceptanceController()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class AcceptanceController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private var window: NSWindow!
    private var rift: RiftPanelController?
    private var probe: ClickProbeView!
    private let editor = NSTextField(string: "Type a test character after clicking a thumbnail")
    private let outcome = NSPopUpButton(frame: .zero, pullsDown: false)
    private let status = NSTextField(wrappingLabelWithString: "No observations yet")
    private let logView = NSTextView(frame: .zero)
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var mediaRoot: URL?
    private var fixtures: [AssetRecord] = []
    private var records: [AssetRecord] = []
    private var observations: [String] = []
    private var sceneGeneration = UUID()
    private var reorderTask: Task<Void, Never>?
    private var outcomeTasks: [UUID: Task<Void, Never>] = [:]
    private var underlyingClicks = 0
    private var selectionCount = 0
    private let batchID = UUID()
    private var targetRefreshTask: Task<Void, Never>?
    private var targetRows: [RiftDiagnosticRow] = []
    private var holdTestArmed = false
    private var heldTestAsset: UUID?
    private let holdStatus = NSTextField(wrappingLabelWithString: "按住补位：尚未准备")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("riftlet-gui-acceptance-\(UUID().uuidString)", isDirectory: true)
            mediaRoot = root
            fixtures = try SyntheticScene.makeMedia(in: root)
            installMenu()
            buildWindow()
            installObservations()
            resetScene(count: 3)
            record("helper_started", ["syntheticOnly": true, "guiVerdict": "NOT_ASSESSED",
                                       "os": ProcessInfo.processInfo.operatingSystemVersionString])
        } catch {
            fputs("GUI acceptance setup failed: \(error)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        reorderTask?.cancel()
        targetRefreshTask?.cancel()
        outcomeTasks.values.forEach { $0.cancel() }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        rift?.close()
        if let mediaRoot { try? FileManager.default.removeItem(at: mediaRoot) }
    }

    private func buildWindow() {
        let frame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_200, height: 800)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Riftlet GUI acceptance — SYNTHETIC ONLY — observations, no automatic PASS"
        window.delegate = self
        window.isReleasedWhenClosed = false
        if #available(macOS 13.0, *) { window.collectionBehavior = [.primary] }
        window.setFrame(frame, display: false)
        probe = ClickProbeView(frame: CGRect(origin: .zero, size: frame.size))
        probe.onMouseDown = { [weak self] event in
            guard let self else { return }
            self.underlyingClicks += 1
            self.record("underlying_probe_down", self.eventFields(event))
        }
        window.contentView = probe

        let title = NSTextField(wrappingLabelWithString: "N04 / N05 / N07 · Native input observations")
        title.font = .boldSystemFont(ofSize: 18)
        let guidance = NSTextField(wrappingLabelWithString: """
        请用真实鼠标/键盘连续完成：①点文本框，再单击右侧 IMAGE 图片，输入一个测试字符；②点击 GAP 间隙、CLEAR 透明角（可补 OUTER 外侧）；③点“准备按住补位”，按住 HOLD 第二张，看到“可以松开”后释放；④待补位完成后双击剩余图片。
        靶点画在底层探针上，不能绕过上层窗口。以底层实际收到的点击判断穿透；图片/数字上的靶心可能被缩略图遮住，请沿标注箭头定位。透明角须点小靶心。
        只有合成素材。日志不记录输入内容或键码，不自动判 PASS。同进程文本框不代表跨应用焦点通过；跨应用/全屏仍须独立验证。
        """)
        guidance.font = .systemFont(ofSize: 12)
        guidance.textColor = .secondaryLabelColor
        let scenes = NSStackView(views: [button("2 images", #selector(scene2)),
                                        button("3 images", #selector(scene3)),
                                        button("12 images", #selector(scene12)),
                                        button("Oldest", #selector(showOldest)),
                                        button("Latest", #selector(showLatest))])
        scenes.orientation = .horizontal
        scenes.spacing = 8
        outcome.addItems(withTitles: ["Keep pending", "Simulate used", "Simulate failure", "Simulate unknown"])
        let actions = NSStackView(views: [outcome, button("准备按住补位", #selector(armReorder)),
                                         button("Focus text field", #selector(focusEditor))])
        actions.orientation = .horizontal
        actions.spacing = 8
        editor.delegate = self
        editor.placeholderString = "Only text length is logged"
        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = true
        scroll.documentView = logView
        let stack = NSStackView(views: [title, guidance, scenes, actions, holdStatus, editor, status, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        probe.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: probe.leadingAnchor, constant: 20),
            stack.topAnchor.constraint(equalTo: probe.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: probe.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: probe.widthAnchor, multiplier: 0.70, constant: -20),
            guidance.widthAnchor.constraint(equalTo: stack.widthAnchor),
            editor.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor)
    }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        let show = NSMenuItem(title: "Show Controls", action: #selector(showControls), keyEquivalent: "0")
        show.target = self
        appMenu.addItem(show)
        appMenu.addItem(withTitle: "Quit Acceptance Helper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private func installObservations() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self else { return event }
            self.record(event.type == .keyDown ? "key_down" : (event.type == .leftMouseDown ? "mouse_down" : "mouse_up"),
                        self.eventFields(event))
            if event.type == .leftMouseUp, let held = self.heldTestAsset {
                if self.reorderTask != nil { self.holdStatus.stringValue = "提前松开：未执行补位；可重新准备。" }
                self.reorderTask?.cancel(); self.reorderTask = nil
                self.heldTestAsset = nil
                self.record("hold_test_release", ["assetID": held.uuidString])
                self.scheduleTargetRefresh()
            }
            return event
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let controller = self else { return }
                let eventName = notification.name.rawValue
                DispatchQueue.main.async { [controller] in controller.record("focus_changed", ["notification": eventName]) }
            }
            observers.append(observer)
        }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.didChangeScreenNotification,
                     NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                let eventName = notification.name.rawValue
                DispatchQueue.main.async { [weak self] in
                    self?.record("control_window_changed", ["notification": eventName])
                    self?.scheduleTargetRefresh()
                }
            }
            observers.append(observer)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        record("probe_text_changed", ["length": editor.stringValue.count])
    }

    private func eventFields(_ event: NSEvent) -> [String: Any] {
        var fields: [String: Any] = ["eventTime": event.timestamp, "window": event.windowNumber]
        // Physical keycodes can reconstruct typing even without event.characters.
        // Record only the occurrence of a key event and focus, never its identity.
        if event.type != .keyDown, let eventWindow = event.window {
            fields["eventNumber"] = event.eventNumber
            fields["eventWindowLocalPoint"] = ["x": event.locationInWindow.x, "y": event.locationInWindow.y]
            fields["eventWindowFrame"] = rectFields(eventWindow.frame)
            fields["eventWindowBackingScaleFactor"] = eventWindow.backingScaleFactor
            if let screen = eventWindow.screen { fields["eventWindowScreenFrame"] = rectFields(screen.frame) }
            if let rawCGPoint = event.cgEvent?.location {
                // Raw coordinate space only: never rescale or substitute it for
                // the original NSEvent location, and never infer physical input.
                fields["rawCGEventLocation"] = ["x": rawCGPoint.x, "y": rawCGPoint.y]
            }
            let point = eventWindow.convertPoint(toScreen: event.locationInWindow)
            fields["pointWithinEventWindow"] = eventWindow.frame.contains(point)
            if let content = eventWindow.contentView {
                fields["eventContentBounds"] = rectFields(content.bounds)
                let contentPoint = content.convert(event.locationInWindow, from: nil)
                fields["eventContentPoint"] = ["x": contentPoint.x, "y": contentPoint.y]
                fields["pointWithinEventContent"] = content.bounds.contains(contentPoint)
            }
            fields["screenX"] = point.x
            fields["screenY"] = point.y
            fields["clickCount"] = event.clickCount
            fields["namedTargets"] = probe.targets.filter { $0.contains(point) }.map(\.name)
            if let snapshot = rift?.diagnosticSnapshot {
                fields["targetGeometryCurrent"] = !snapshot.isTransitioning && snapshot.rows == targetRows
                fields["rowGeometryTransitioning"] = snapshot.isTransitioning
                if let row = snapshot.rows.first(where: { $0.windowNumber == event.windowNumber }) {
                    fields["rowAssetID"] = row.assetID.uuidString
                    // Geometry classification, not a pixel-alpha or physical-origin claim.
                    fields["rowRegion"] = row.imageClipFrame.contains(point) ? "imageRectangle"
                        : row.numberFrame.contains(point) ? "numberRectangle"
                        : row.frame.contains(point) ? "rowPadding" : "outsideRow"
                }
            } else { fields["targetGeometryCurrent"] = false }
        }
        return fields
    }

    private func record(_ name: String, _ fields: [String: Any] = [:]) {
        var value = fields
        value["event"] = name
        value["uptime"] = ProcessInfo.processInfo.systemUptime
        value["syntheticOnly"] = true
        value["batchID"] = batchID.uuidString
        value["sceneID"] = sceneGeneration.uuidString
        value["helperPID"] = ProcessInfo.processInfo.processIdentifier
        value["frontmostPID"] = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        value["helperActive"] = NSApp.isActive
        value["keyWindow"] = NSApp.keyWindow?.windowNumber ?? -1
        value["mainWindow"] = NSApp.mainWindow?.windowNumber ?? -1
        value["frontmostBundle"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unidentified"
        value["probeEditorFocused"] = editor.currentEditor() != nil && window?.firstResponder === editor.currentEditor()
        value["probeKeyInputEligible"] = NSApp.isActive && window?.isKeyWindow == true
            && editor.currentEditor() != nil && window?.firstResponder === editor.currentEditor()
        value["underlyingClickCount"] = underlyingClicks
        value["selectionCount"] = selectionCount
        if let window {
            value["controlWindow"] = ["number": window.windowNumber,
                "visible": window.isVisible, "onActiveSpace": window.isOnActiveSpace,
                "occlusionVisible": window.occlusionState.contains(.visible), "miniaturized": window.isMiniaturized,
                "frame": rectFields(window.frame), "collectionBehavior": window.collectionBehavior.rawValue,
                "screenID": (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0] as [String: Any]
        }
        guard let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let line = String(data: bytes, encoding: .utf8) else { return }
        print(line)
        fflush(stdout)
        observations.append(line)
        if observations.count > 250 { observations.removeFirst(observations.count - 250) }
        logView.string = observations.joined(separator: "\n") + "\n"
        logView.scrollToEndOfDocument(nil)
        status.stringValue = "Observed probe clicks: \(underlyingClicks) · thumbnail selections: \(selectionCount) · GUI verdict: NOT ASSESSED"
    }

    private func resetScene(count: Int) {
        guard let mediaRoot else { return }
        sceneGeneration = UUID()
        reorderTask?.cancel()
        heldTestAsset = nil; holdTestArmed = false
        holdStatus.stringValue = "按住补位：尚未准备"
        outcomeTasks.values.forEach { $0.cancel() }
        outcomeTasks.removeAll()
        do { records = try SyntheticScene.records(from: fixtures, count: count) }
        catch { record("fixture_error"); return }
        rift?.close()
        var configuration = RiftConfiguration()
        configuration.preferredDisplayID = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        rift = RiftPanelController(mediaDirectory: mediaRoot, configuration: configuration,
            onSelectionBoundary: { [weak self] boundary in self?.recordPress(boundary) }) { [weak self] id in
            self?.selected(id)
        }
        rift?.render(records)
        record("scene_reset", ["count": count, "assetIDs": records.map { $0.id.uuidString }])
        scheduleTargetRefresh()
    }

    private func recordPress(_ boundary: RiftSelectionBoundary) {
        // Emit only this fresh accepted boundary. Never retain a press and reuse
        // it for a later selection after a canceled hold, reflow or scene reset.
        // "mouse" identifies AppKit routing, not physical-human provenance.
        var fields: [String: Any] = ["assetID": boundary.assetID.uuidString,
                                    "source": boundary.source.rawValue,
                                    "eventUptime": boundary.eventUptime]
        if let eventNumber = boundary.eventNumber { fields["eventNumber"] = eventNumber }
        if let windowNumber = boundary.windowNumber { fields["windowNumber"] = windowNumber }
        if let clickCount = boundary.clickCount { fields["clickCount"] = clickCount }
        record("thumbnail_press", fields)
        if boundary.source == .mouse { beginHeldReorder(boundary.assetID) }
    }

    private func selected(_ id: UUID) {
        selectionCount += 1
        guard let selected = records.first(where: { $0.id == id }) else {
            record("selection_not_in_scene", ["assetID": id.uuidString])
            return
        }
        record("thumbnail_selected", ["assetID": id.uuidString, "sequence": selected.sequence,
                                       "stateBefore": selected.status.rawValue])
        scheduleTargetRefresh()
        guard selected.status != .unknown, selected.status != .used else {
            record("retained_without_replay", ["assetID": id.uuidString])
            return
        }
        let statuses: [QueueStatus] = [.pending, .used, .failed, .unknown]
        let final = statuses[max(0, min(statuses.count - 1, outcome.indexOfSelectedItem))]
        guard final != .pending else { return }
        let token = sceneGeneration
        records = SyntheticScene.displaying(.transferring, assetID: id, in: records)
        rift?.render(records)
        outcomeTasks[id]?.cancel()
        outcomeTasks[id] = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard let self, self.sceneGeneration == token else { return }
            self.records = SyntheticScene.displaying(final, assetID: id, in: self.records)
            self.rift?.render(self.records)
            self.outcomeTasks.removeValue(forKey: id)
            self.record("synthetic_display_state", ["assetID": id.uuidString, "state": final.rawValue,
                                                     "receiptEvidence": false])
        }
    }

    @objc private func scene2() { resetScene(count: 2) }
    @objc private func scene3() { resetScene(count: 3) }
    @objc private func scene12() { resetScene(count: 12) }
    @objc private func showOldest() { rift?.showOldest(); record("show_oldest"); scheduleTargetRefresh() }
    @objc private func showLatest() { rift?.showLatest(); record("show_latest"); scheduleTargetRefresh() }
    @objc private func focusEditor() { window.makeFirstResponder(editor); record("focus_requested") }

    @objc private func armReorder() {
        reorderTask?.cancel()
        heldTestAsset = nil
        holdTestArmed = true
        outcome.selectItem(at: 0)
        holdStatus.stringValue = "已准备：按住 HOLD 第二张，等待“可以松开”。"
        record("reorder_armed", ["trigger": "next_accepted_mouse_press", "delaySeconds": 1.5])
    }

    private func beginHeldReorder(_ pressedID: UUID) {
        guard holdTestArmed else { return }
        holdTestArmed = false
        guard let other = records.first(where: { $0.status != .used }), other.id != pressedID else {
            holdStatus.stringValue = "需至少两张图片；请选择 3 images 后重试。"
            record("reorder_unavailable"); return
        }
        heldTestAsset = pressedID
        holdStatus.stringValue = "保持按住… 1.5 秒后只更新另一张图片。"
        let token = sceneGeneration
        record("hold_test_started", ["assetID": pressedID.uuidString, "otherAssetID": other.id.uuidString])
        reorderTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
            guard let self, self.sceneGeneration == token, self.heldTestAsset == pressedID,
                  self.rift?.diagnosticSnapshot.isHolding == true else { return }
            self.records = SyntheticScene.displaying(.used, assetID: other.id, in: self.records)
            self.rift?.render(self.records)
            self.reorderTask = nil
            self.holdStatus.stringValue = "可以松开：另一项已请求移除，补位须等释放后发生。"
            self.record("reorder_requested", ["assetID": other.id.uuidString, "heldAssetID": pressedID.uuidString,
                                               "holding": self.rift?.diagnosticSnapshot.isHolding == true,
                                               "activeIDs": self.records.filter { $0.status != .used }.map { $0.id.uuidString },
                                               "receiptEvidence": false])
        }
    }

    @objc private func showControls() {
        guard let window else { return }
        record("show_controls_before")
        window.deminiaturize(nil)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }), let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        record("show_controls_requested")
        scheduleTargetRefresh()
    }

    private func rectFields(_ rect: CGRect) -> [String: CGFloat] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    private func scheduleTargetRefresh() {
        targetRefreshTask?.cancel()
        probe?.targets = []; probe?.needsDisplay = true
        targetRows = []
        targetRefreshTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 650_000_000) } catch { return }
            self?.refreshTargets()
        }
    }

    private func refreshTargets() {
        guard let rift, let window, let screen = window.screen else { return }
        let snapshot = rift.diagnosticSnapshot
        guard !snapshot.isHolding, !snapshot.isTransitioning else {
            probe.targets = []; probe.needsDisplay = true
            record("probe_targets_unavailable", ["holding": snapshot.isHolding, "transitioning": snapshot.isTransitioning])
            return
        }
        targetRows = snapshot.rows
        probe.targets = ProbeTarget.make(snapshot: snapshot, screen: screen.visibleFrame).filter { target in
            let point = probe.convert(window.convertPoint(fromScreen: target.screenPoint), from: nil)
            // Only real empty probe surface can receive an underlying test click.
            return probe.bounds.contains(point) && !probe.subviews.contains { $0.frame.contains(point) }
        }
        probe.needsDisplay = true
        record("probe_targets", ["targets": probe.targets.map { target in
            let rowWindow = snapshot.rows.first(where: { $0.frame.contains(target.screenPoint) })?.windowNumber ?? 0
            let underneath = NSWindow.windowNumber(at: target.screenPoint, belowWindowWithWindowNumber: rowWindow)
            return ["name": target.name, "x": target.screenPoint.x, "y": target.screenPoint.y,
             "radius": target.radius,
             "predictedUnderlyingWindow": underneath,
             "underlyingProbePredicted": underneath == window.windowNumber,
             "predictedWindow": NSWindow.windowNumber(at: target.screenPoint, belowWindowWithWindowNumber: 0)] as [String: Any]
        }, "rows": snapshot.rows.map { row in
            ["assetID": row.assetID.uuidString, "ordinal": row.ordinal, "window": row.windowNumber,
             "frame": rectFields(row.frame), "image": rectFields(row.imageClipFrame),
             "number": rectFields(row.numberFrame)] as [String: Any]
        }, "predictionIsPassEvidence": false])
    }
}

@MainActor
private final class ClickProbeView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var targets: [ProbeTarget] = []
    private var lastPoint: CGPoint?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
        onMouseDown?(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let grid = NSBezierPath()
        for x in stride(from: 0.0, through: Double(bounds.width), by: 40) {
            grid.move(to: CGPoint(x: x, y: 0)); grid.line(to: CGPoint(x: x, y: bounds.height))
        }
        for y in stride(from: 0.0, through: Double(bounds.height), by: 40) {
            grid.move(to: CGPoint(x: 0, y: y)); grid.line(to: CGPoint(x: bounds.width, y: y))
        }
        grid.lineWidth = 0.4
        grid.stroke()
        let label = NSAttributedString(string: "UNDERLYING CLICK PROBE\nClear pixels are measured, not assumed.",
                                      attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        label.draw(in: CGRect(x: bounds.width * 0.72, y: 22, width: bounds.width * 0.26, height: 45))
        if let window {
            for (index, target) in targets.enumerated() {
                let point = convert(window.convertPoint(fromScreen: target.screenPoint), from: nil)
                let labelPoint = CGPoint(x: max(bounds.width * 0.72, point.x - 195), y: 90 + CGFloat(index) * 24)
                NSColor.systemBlue.setStroke()
                let path = NSBezierPath()
                path.move(to: CGPoint(x: point.x - 3, y: point.y)); path.line(to: CGPoint(x: point.x + 3, y: point.y))
                path.move(to: CGPoint(x: point.x, y: point.y - 3)); path.line(to: CGPoint(x: point.x, y: point.y + 3))
                path.move(to: CGPoint(x: labelPoint.x + 105, y: labelPoint.y + 7)); path.line(to: point)
                path.lineWidth = 0.7; path.stroke()
                NSAttributedString(string: target.name, attributes: [.font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.labelColor]).draw(at: labelPoint)
            }
        }
        if let lastPoint {
            NSColor.systemOrange.setStroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: lastPoint.x - 7, y: lastPoint.y - 7, width: 14, height: 14))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
