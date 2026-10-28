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
            RiftletGUIAcceptance [--self-check | --software-pointer-probes | --software-hold-probe | --software-double-probe]
            GUI: synthetic 2/3/12-image scenes, click/focus observations and delayed reorder.
            JSONL observations go to stdout; typed text is never included.
            --software-pointer-probes runs one bounded IMAGE/NUMBER/CLEAR/GAP CGEvent batch
              on fresh helper-only synthetic scenes; existing posting permission, no prompt.
              Physical-human acceptance remains NOT_RUN. No real App upload is invoked.
              Acceptance-only geometry: --probe-compact or --probe-large, --probe-display-id ID.
            --software-hold-probe runs one helper-only CGEvent hold/reorder/release case;
              it is mutually exclusive with --software-pointer-probes. Physical NOT_RUN.
            --software-double-probe runs at most two helper-only down/up pairs, testing
              CGEvent-supplied clickState=2 after synthetic replacement. Physical NOT_RUN.
              All software probe modes are mutually exclusive; one batch per process.
            --self-check validates fixtures/layout only and does not run GUI acceptance.
            --press-acceptance-asset UUID --app-pid PID --app-path /exact/Riftlet.app
              One bounded AXPress on one exact synthetic identifier; existing AX permission only.
            """)
            return
        }
        if CommandLine.arguments.contains("--self-check") {
            do {
                try SyntheticScene.selfCheck()
                try SoftwarePointerProbe.selfCheck()
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
    private var softwareProbeAligned = false
    private var softwareProbeTask: Task<Void, Never>?
    private var softwareProbeBatchUsed = false
    private var softwareProbeReceipt: SoftwarePointerProbe.Receipt?
    private var softwareProbeRelease: CGEvent?
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
            let modes = ["--software-pointer-probes", "--software-hold-probe", "--software-double-probe"]
                .filter { CommandLine.arguments.contains($0) }
            if modes.count > 1 {
                record("software_probe_refused", ["reason": "mutuallyExclusiveModes", "eventsPosted": false])
            } else if modes.first == "--software-double-probe" { runSoftwareDoubleProbe()
            } else if modes.first == "--software-hold-probe" { runSoftwareHoldProbe()
            } else if CommandLine.arguments.contains("--software-pointer-probes") { runSoftwarePointerProbes() }
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
        releaseSoftwarePointer()
        reorderTask?.cancel()
        softwareProbeTask?.cancel()
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
            if let receipt = self.softwareProbeReceipt, receipt.matches(event) { receipt.probeDownCount += 1 }
            self.record("underlying_probe_down", self.eventFields(event))
        }
        probe.onMouseUp = { [weak self] event in
            guard let self else { return }
            if let receipt = self.softwareProbeReceipt, receipt.matches(event) { receipt.probeUpCount += 1 }
            self.record("underlying_probe_up", self.eventFields(event))
        }
        window.contentView = probe

        let title = NSTextField(wrappingLabelWithString: "N04 / N05 / N07 · Native input observations")
        title.font = .boldSystemFont(ofSize: 18)
        let guidance = NSTextField(wrappingLabelWithString: """
        请用真实鼠标/键盘连续完成：①点文本框，再分别单击右侧 IMAGE 图片和 NUMBER 数字，各输入一个测试字符；②点击 GAP 间隙、CLEAR 透明角（可补 OUTER 外侧）；③点“准备按住补位”，按住 HOLD 第二张，看到“可以松开”后释放；④待补位完成后双击剩余图片。第④步只验证普通双击；替换窗口后的防误选仍需独立证据。
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
        let dump = NSMenuItem(title: "Dump Coordinates", action: #selector(dumpCoordinates), keyEquivalent: "")
        dump.target = self; appMenu.addItem(dump)
        let run = NSMenuItem(title: "Run Software Pointer Probes (once)", action: #selector(runSoftwarePointerProbes), keyEquivalent: "")
        run.target = self; appMenu.addItem(run)
        let hold = NSMenuItem(title: "Run Software Hold Probe (once)", action: #selector(runSoftwareHoldProbe), keyEquivalent: "")
        hold.target = self; appMenu.addItem(hold)
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
            if let receipt = self.softwareProbeReceipt { receipt.observe(event) }
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
            if let receipt = softwareProbeReceipt, receipt.matches(event) {
                fields["inputOrigin"] = "CGEvent"; fields["physical"] = false
                fields["softwareProbeToken"] = receipt.token; fields["softwareProbeCase"] = receipt.name
            } else { fields["inputOrigin"] = "unattributedNSEvent" }
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
                if let row = snapshot.rows.first(where: { [$0.windowNumber, $0.imageInputWindowNumber, $0.numberInputWindowNumber].contains(event.windowNumber) }) {
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
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--probe-display-id"), index + 1 < arguments.count,
           let id = UInt32(arguments[index + 1]), NSScreen.screens.contains(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
           }) { configuration.preferredDisplayID = id }
        if arguments.contains("--probe-compact") { configuration.fitWidth = 48; configuration.fitHeight = 32 }
        if arguments.contains("--probe-large") { configuration.fitWidth = 128; configuration.fitHeight = 96; configuration.rowPitch = 100 }
        rift = RiftPanelController(mediaDirectory: mediaRoot, configuration: configuration,
            onSelectionBoundary: { [weak self] boundary in self?.recordPress(boundary) }) { [weak self] id in
            self?.selected(id)
        }
        rift?.render(records)
        record("scene_reset", ["count": count, "assetIDs": records.map { $0.id.uuidString },
            "fitWidth": configuration.fitWidth, "fitHeight": configuration.fitHeight,
            "preferredDisplayID": configuration.preferredDisplayID ?? 0])
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
        if boundary.source == .mouse, let receipt = softwareProbeReceipt,
           let down = receipt.downIdentity, down.time == boundary.eventUptime,
           down.number == boundary.eventNumber, down.window == boundary.windowNumber {
            receipt.acceptedAssets.append(boundary.assetID)
            fields["inputOrigin"] = "CGEvent"; fields["physical"] = false
            fields["softwareProbeToken"] = receipt.token; fields["softwareProbeCase"] = receipt.name
        }
        record("thumbnail_press", fields)
        if boundary.source == .mouse { beginHeldReorder(boundary.assetID) }
    }

    private func selected(_ id: UUID) {
        selectionCount += 1
        if let receipt = softwareProbeReceipt { receipt.selectedAssets.append(id) }
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

    private func actualRowScreen(_ snapshot: RiftDiagnosticSnapshot) -> NSScreen? {
        guard let row = snapshot.rows.first else { return nil }
        if let rowWindow = NSApp.windows.first(where: { $0.windowNumber == row.windowNumber }),
           let screen = rowWindow.screen, screen.frame.intersects(row.frame) { return screen }
        return NSScreen.screens.first { $0.frame.contains(CGPoint(x: row.frame.midX, y: row.frame.midY)) }
    }

    private func alignProbeControlToActualRows() {
        guard let window, let snapshot = rift?.diagnosticSnapshot,
              !snapshot.isHolding, !snapshot.isTransitioning, let screen = actualRowScreen(snapshot) else { return }
        let before = window.frame
        let proposed = SoftwarePointerProbe.probeControlFrame(current: before, visibleScreen: screen.visibleFrame)
        window.setFrame(proposed, display: true)
        record("probe_control_alignment", ["before": rectFields(before), "requested": rectFields(proposed),
            "immediateActual": rectFields(window.frame), "rowScreenFrame": rectFields(screen.frame),
            "rowScreenID": (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
            "productPanelsMoved": false, "focusRequested": false, "eventsPosted": false,
            "acceptanceOnly": true])
    }

    @objc private func dumpCoordinates() { refreshTargets() }

    private func quartzFields(_ point: CGPoint) -> [String: CGFloat] {
        guard let primary = NSScreen.screens.first else { return [:] }
        let converted = SoftwarePointerProbe.quartzPoint(point, primaryFrame: primary.frame)
        return ["x": converted.x, "y": converted.y]
    }

    private func softwareProbeUnavailable() -> String? {
        guard CGPreflightPostEventAccess() else { return "postEventPermissionUnavailable" }
        guard !CGEventSource.buttonState(.combinedSessionState, button: .left),
              !CGEventSource.buttonState(.combinedSessionState, button: .right),
              CGEventSource.flagsState(.combinedSessionState).intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty
              else { return "pointerOrModifierAlreadyHeld" }
        guard let window, window.isVisible, !window.isMiniaturized, window.isOnActiveSpace,
              window.occlusionState.contains(.visible) else { return "controlWindowUnavailable" }
        guard NSApp.isActive, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
              window.isKeyWindow else { return "helperNotForegroundKey" }
        guard let snapshot = rift?.diagnosticSnapshot, !snapshot.isHolding, !snapshot.isTransitioning,
              snapshot.rows == targetRows, snapshot.rows.count >= 2 else { return "geometryUnavailable" }
        guard records.allSatisfy({ $0.image.origin == .synthetic }) else { return "nonSyntheticScene" }
        return nil
    }

    @objc private func runSoftwarePointerProbes() {
        guard !softwareProbeBatchUsed else {
            record("software_probe_refused", ["reason": "oneBatchPerProcess", "physical": false]); return
        }
        softwareProbeBatchUsed = true
        softwareProbeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var results: [String: String] = [:]
            defer { self.softwareProbeReceipt = nil; self.softwareProbeTask = nil }
            self.record("software_probe_batch_started", ["inputOrigin": "CGEvent", "physical": false,
                "physicalVerdict": "NOT_RUN", "cases": SoftwarePointerProbe.names, "maximumClickPairs": 4])
            do { try await Task.sleep(nanoseconds: 1_200_000_000) } catch { return }
            for name in SoftwarePointerProbe.names {
                guard !Task.isCancelled else { return }
                // A fresh existing helper scene for every case: never reuse old
                // panel coordinates after selection, swallow or reflow.
                self.outcome.selectItem(at: 0)
                self.resetScene(count: 3)
                let scene = self.sceneGeneration
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                // One explicit helper-window alignment per batch, based on the
                // real row screen. Never move a Riftlet row to fit this probe.
                if !self.softwareProbeAligned {
                    self.softwareProbeAligned = true
                    self.alignProbeControlToActualRows()
                    do { try await Task.sleep(nanoseconds: 650_000_000) } catch { return }
                }
                self.refreshTargets()
                if let reason = self.softwareProbeUnavailable() {
                    results[name] = "NOT_RUN"
                    self.record("software_probe_case", ["case": name, "result": "NOT_RUN", "reason": reason,
                        "inputOrigin": "CGEvent", "physical": false, "eventsPosted": false])
                    break
                }
                guard let snapshot = self.rift?.diagnosticSnapshot, let row = snapshot.rows.first,
                      let target = self.probe.targets.first(where: { $0.name.hasPrefix(name + " ") }),
                      let primary = NSScreen.screens.first else {
                    results[name] = "NOT_RUN"
                    self.record("software_probe_case", ["case": name, "result": "NOT_RUN", "reason": "targetMissing", "eventsPosted": false])
                    break
                }
                guard let stack = self.ownedProbeStack(at: target.screenPoint, snapshot: snapshot),
                      snapshot.rows == self.rift?.diagnosticSnapshot.rows, scene == self.sceneGeneration else {
                    results[name] = "NOT_RUN"
                    self.record("software_probe_case", ["case": name, "result": "NOT_RUN", "reason": "nonHelperSurfaceOrChangedGeometry", "eventsPosted": false])
                    break
                }
                let expectedWindow = name == "IMAGE" ? row.imageInputWindowNumber
                    : name == "NUMBER" ? row.numberInputWindowNumber : self.window.windowNumber
                let receipt = SoftwarePointerProbe.Receipt(name: name, expectedAsset: row.assetID,
                    expectedWindow: expectedWindow, expectedPoint: target.screenPoint, radius: target.radius)
                let point = SoftwarePointerProbe.quartzPoint(target.screenPoint, primaryFrame: primary.frame)
                guard let source = CGEventSource(stateID: .privateState),
                      let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
                      let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
                    results[name] = "NOT_RUN"
                    self.record("software_probe_case", ["case": name, "result": "NOT_RUN", "reason": "eventAllocationFailed", "eventsPosted": false])
                    break
                }
                for event in [down, up] {
                    event.setIntegerValueField(.eventSourceUserData, value: receipt.token)
                    event.setIntegerValueField(.mouseEventClickState, value: 1)
                }
                let beforePID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
                let beforeKey = NSApp.keyWindow?.windowNumber ?? -1
                let beforeEditor = self.editor.currentEditor() != nil && self.window.firstResponder === self.editor.currentEditor()
                self.softwareProbeReceipt = receipt
                self.record("software_probe_post", ["case": name, "softwareProbeToken": receipt.token,
                    "inputOrigin": "CGEvent", "physical": false, "expectedAssetID": row.assetID.uuidString,
                    "expectedWindow": expectedWindow, "queriedOwnedWindowStack": stack, "appKitPoint": ["x": target.screenPoint.x, "y": target.screenPoint.y],
                    "quartzPoint": ["x": point.x, "y": point.y], "expectedRows": snapshot.rows.map { $0.assetID.uuidString },
                    "eventsPosted": true])
                // One adjacent down/up pair, globally routed by WindowServer.
                // No AX, direct view action, post-to-PID, focus call or retry.
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
                do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
                let afterEditor = self.editor.currentEditor() != nil && self.window.firstResponder === self.editor.currentEditor()
                let focusStable = beforePID == NSWorkspace.shared.frontmostApplication?.processIdentifier
                    && beforeKey == NSApp.keyWindow?.windowNumber && beforeEditor == afterEditor
                let geometryStable = snapshot.rows == self.rift?.diagnosticSnapshot.rows
                let result = scene == self.sceneGeneration && geometryStable ? receipt.verdict(focusStable: focusStable) : "INCONCLUSIVE"
                results[name] = result
                self.record("software_probe_case", ["case": name, "result": result, "inputOrigin": "CGEvent",
                    "physical": false, "physicalVerdict": "NOT_RUN", "softwareProbeToken": receipt.token,
                    "expectedAssetID": row.assetID.uuidString, "expectedWindow": expectedWindow,
                    "receivedWindows": receipt.receivedWindows, "downCount": receipt.downCount, "upCount": receipt.upCount,
                    "underlyingDownCount": receipt.probeDownCount, "underlyingUpCount": receipt.probeUpCount,
                    "acceptedAssets": receipt.acceptedAssets.map { $0.uuidString }, "selectedAssets": receipt.selectedAssets.map { $0.uuidString },
                    "coordinatesMatch": receipt.coordinatesMatch, "interference": receipt.interference,
                    "focusEndpointsStable": focusStable, "geometryStable": geometryStable, "eventsPosted": true])
                self.softwareProbeReceipt = nil
                if result == "INCONCLUSIVE" || !focusStable { break }
            }
            for name in SoftwarePointerProbe.names where results[name] == nil { results[name] = "NOT_RUN" }
            self.record("software_probe_batch_finished", ["results": results,
                "passCount": results.values.filter { $0 == "PASS_SOFTWARE_ROUTING" }.count,
                "failCount": results.values.filter { $0 == "FAIL" }.count,
                "inconclusiveCount": results.values.filter { $0 == "INCONCLUSIVE" }.count,
                "notRunCount": results.values.filter { $0 == "NOT_RUN" }.count,
                "physicalVerdict": "NOT_RUN", "crossApplicationFocusVerdict": "NOT_RUN",
                "inputOrigin": "CGEvent", "physical": false])
        }
    }

    /// Pair the already posted down exactly once, including task cancellation
    /// or app termination. Never create another down, retry, or post-to-PID.
    private func releaseSoftwarePointer(observation: String = "software_hold_up_posted") {
        guard let release = softwareProbeRelease else { return }
        softwareProbeRelease = nil
        release.post(tap: .cghidEventTap)
        record(observation, ["inputOrigin": "CGEvent", "physical": false,
            "softwareProbeToken": release.getIntegerValueField(.eventSourceUserData),
            "originalReleasePoint": true])
    }

    @objc private func runSoftwareHoldProbe() {
        guard !softwareProbeBatchUsed else {
            record("software_probe_refused", ["reason": "oneBatchPerProcess", "physical": false]); return
        }
        softwareProbeBatchUsed = true
        softwareProbeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.releaseSoftwarePointer()
                self.softwareProbeReceipt = nil; self.softwareProbeTask = nil
            }
            self.record("software_hold_started", ["inputOrigin": "CGEvent", "physical": false,
                "maximumClickPairs": 1, "reorderDelaySeconds": 1.5, "physicalVerdict": "NOT_RUN"])
            do { try await Task.sleep(nanoseconds: 1_200_000_000) } catch { return }
            self.outcome.selectItem(at: 0); self.resetScene(count: 3)
            let scene = self.sceneGeneration
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            self.alignProbeControlToActualRows()
            do { try await Task.sleep(nanoseconds: 650_000_000) } catch { return }
            self.refreshTargets()
            if let reason = self.softwareProbeUnavailable() {
                self.record("software_hold_case", ["result": "NOT_RUN", "reason": reason, "eventsPosted": false]); return
            }
            guard let snapshot = self.rift?.diagnosticSnapshot, snapshot.rows.count == 3,
                  let target = self.probe.targets.first(where: { $0.name.hasPrefix("HOLD ") }),
                  let primary = NSScreen.screens.first,
                  let stack = self.ownedProbeStack(at: target.screenPoint, snapshot: snapshot),
                  snapshot.rows == self.rift?.diagnosticSnapshot.rows, scene == self.sceneGeneration else {
                self.record("software_hold_case", ["result": "NOT_RUN", "reason": "nonHelperSurfaceOrChangedGeometry", "eventsPosted": false]); return
            }
            let row = snapshot.rows[1], other = snapshot.rows[0]
            guard row.imageClipFrame.contains(target.screenPoint), row.imageInputFrame.contains(target.screenPoint),
                  row.assetID != other.assetID else {
                self.record("software_hold_case", ["result": "NOT_RUN", "reason": "holdTargetMismatch", "eventsPosted": false]); return
            }
            let receipt = SoftwarePointerProbe.Receipt(name: "HOLD", expectedAsset: row.assetID,
                expectedWindow: row.imageInputWindowNumber, expectedPoint: target.screenPoint, radius: target.radius)
            let point = SoftwarePointerProbe.quartzPoint(target.screenPoint, primaryFrame: primary.frame)
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
                self.record("software_hold_case", ["result": "NOT_RUN", "reason": "eventAllocationFailed", "eventsPosted": false]); return
            }
            for event in [down, up] {
                event.setIntegerValueField(.eventSourceUserData, value: receipt.token)
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            let beforePID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
            let beforeKey = NSApp.keyWindow?.windowNumber ?? -1
            let beforeEditor = self.editor.currentEditor() != nil && self.window.firstResponder === self.editor.currentEditor()
            self.armReorder()
            self.softwareProbeReceipt = receipt
            self.softwareProbeRelease = up
            self.record("software_hold_down_post", ["softwareProbeToken": receipt.token, "inputOrigin": "CGEvent", "physical": false,
                "expectedAssetID": row.assetID.uuidString, "removedAssetID": other.assetID.uuidString,
                "expectedWindow": row.imageInputWindowNumber, "queriedOwnedWindowStack": stack,
                "appKitPoint": ["x": target.screenPoint.x, "y": target.screenPoint.y],
                "originalRows": snapshot.rows.map { $0.assetID.uuidString }, "eventsPosted": true])
            down.post(tap: .cghidEventTap)
            do { try await Task.sleep(nanoseconds: 1_950_000_000) } catch {
                self.record("software_hold_case", ["result": "INCONCLUSIVE", "reason": "cancelledAfterDown", "eventsPosted": true]); return
            }
            let heldSnapshot = self.rift?.diagnosticSnapshot
            let heldLayoutStable = heldSnapshot?.rows == snapshot.rows && heldSnapshot?.isHolding == true
                && receipt.selectedAssets.isEmpty
            let reorderObserved = self.records.first(where: { $0.id == other.assetID })?.status == .used
                && self.heldTestAsset == row.assetID && self.reorderTask == nil
            let stillOwned = self.ownedProbeStack(at: target.screenPoint, snapshot: snapshot) != nil
            let helperStillForeground = NSApp.isActive
                && NSWorkspace.shared.frontmostApplication?.processIdentifier == beforePID
                && NSApp.keyWindow?.windowNumber == beforeKey
            self.record("software_hold_before_release", ["softwareProbeToken": receipt.token,
                "expectedAssetID": row.assetID.uuidString, "heldLayoutStable": heldLayoutStable,
                "reorderObserved": reorderObserved, "stillOwned": stillOwned,
                "helperStillForeground": helperStillForeground, "downCount": receipt.downCount,
                "selectedCountBeforeRelease": receipt.selectedAssets.count,
                "rows": heldSnapshot?.rows.map { $0.assetID.uuidString } ?? []])
            // Always balance the original down, even if a guard changed while
            // held. A changed surface makes the verdict inconclusive, not a retry.
            self.releaseSoftwarePointer()
            do { try await Task.sleep(nanoseconds: 650_000_000) } catch { return }
            let after = self.rift?.diagnosticSnapshot
            let afterRow = after?.rows.first(where: { $0.assetID == row.assetID })
            let compactionCorrect = after?.isHolding == false
                && after?.rows.map { $0.assetID } == snapshot.rows.dropFirst().map { $0.assetID }
                && afterRow?.ordinal == 1 && afterRow?.imageInputWindowNumber == row.imageInputWindowNumber
                && (afterRow?.frame.minY ?? row.frame.minY) > row.frame.minY
            let afterEditor = self.editor.currentEditor() != nil && self.window.firstResponder === self.editor.currentEditor()
            let focusStable = helperStillForeground && beforePID == NSWorkspace.shared.frontmostApplication?.processIdentifier
                && beforeKey == NSApp.keyWindow?.windowNumber && beforeEditor == afterEditor
            let result = scene == self.sceneGeneration && stillOwned
                ? receipt.holdVerdict(focusStable: focusStable, heldLayoutStable: heldLayoutStable,
                    reorderObserved: reorderObserved, compactionCorrect: compactionCorrect) : "INCONCLUSIVE"
            self.record("software_hold_case", ["result": result, "inputOrigin": "CGEvent", "physical": false,
                "physicalVerdict": "NOT_RUN", "crossApplicationFocusVerdict": "NOT_RUN", "doubleReplacementVerdict": "NOT_RUN",
                "softwareProbeToken": receipt.token, "expectedAssetID": row.assetID.uuidString,
                "removedAssetID": other.assetID.uuidString, "expectedWindow": row.imageInputWindowNumber,
                "receivedWindows": receipt.receivedWindows, "downCount": receipt.downCount, "upCount": receipt.upCount,
                "acceptedAssets": receipt.acceptedAssets.map { $0.uuidString }, "selectedAssets": receipt.selectedAssets.map { $0.uuidString },
                "underlyingDownCount": receipt.probeDownCount, "underlyingUpCount": receipt.probeUpCount,
                "coordinatesMatch": receipt.coordinatesMatch, "interference": receipt.interference,
                "heldLayoutStable": heldLayoutStable, "reorderObserved": reorderObserved,
                "compactionCorrect": compactionCorrect, "focusEndpointsStable": focusStable, "eventsPosted": true])
        }
    }

    private func postDoublePair(_ receipt: SoftwarePointerProbe.Receipt, point: CGPoint, clickCount: Int) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return false }
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: receipt.token)
            event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        }
        softwareProbeReceipt = receipt; softwareProbeRelease = up
        defer { releaseSoftwarePointer(observation: "software_double_up_posted") }
        record("software_double_post", ["case": receipt.name, "softwareProbeToken": receipt.token,
            "expectedAssetID": receipt.expectedAsset.uuidString, "expectedWindow": receipt.expectedWindow,
            "appKitPoint": ["x": receipt.expectedPoint.x, "y": receipt.expectedPoint.y],
            "suppliedClickState": clickCount, "inputOrigin": "CGEvent", "physical": false])
        down.post(tap: .cghidEventTap)
        return true
    }

    private func runSoftwareDoubleProbe() {
        guard !softwareProbeBatchUsed else {
            record("software_probe_refused", ["reason": "oneBatchPerProcess", "eventsPosted": false]); return
        }
        softwareProbeBatchUsed = true
        softwareProbeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.releaseSoftwarePointer(observation: "software_double_up_posted")
                self.softwareProbeReceipt = nil; self.softwareProbeTask = nil
            }
            self.record("software_double_started", ["maximumClickPairs": 2, "inputOrigin": "CGEvent",
                "physical": false, "physicalVerdict": "NOT_RUN", "osDoubleClickClassification": "NOT_TESTED"])
            do { try await Task.sleep(nanoseconds: 1_200_000_000) } catch { return }
            self.outcome.selectItem(at: 0); self.resetScene(count: 3)
            let scene = self.sceneGeneration
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            self.alignProbeControlToActualRows()
            do { try await Task.sleep(nanoseconds: 650_000_000) } catch { return }
            self.refreshTargets()
            if let reason = self.softwareProbeUnavailable() {
                self.record("software_double_case", ["result": "NOT_RUN", "reason": reason, "pairsPosted": 0]); return
            }
            guard let snapshot = self.rift?.diagnosticSnapshot, snapshot.rows.count == 3,
                  let primary = NSScreen.screens.first else { return }
            let firstRow = snapshot.rows[0], replacement = snapshot.rows[1]
            // Choose a point inside both aspect-fitted images' horizontal span.
            // Actual replacement geometry is checked again before second posting.
            let left = max(firstRow.imageClipFrame.minX, replacement.imageClipFrame.minX)
            let right = min(firstRow.imageClipFrame.maxX, replacement.imageClipFrame.maxX)
            let point = CGPoint(x: (left + right) / 2, y: firstRow.imageClipFrame.midY)
            let probePoint = self.probe.convert(self.window.convertPoint(fromScreen: point), from: nil)
            guard right - left > 4, firstRow.imageInputFrame.contains(point),
                  self.probe.bounds.contains(probePoint),
                  !self.probe.subviews.contains(where: { $0.frame.contains(probePoint) }),
                  self.ownedProbeStack(at: point, snapshot: snapshot) != nil else {
                self.record("software_double_case", ["result": "NOT_RUN", "reason": "noSafeCommonPoint", "pairsPosted": 0]); return
            }
            let first = SoftwarePointerProbe.Receipt(name: "DOUBLE_FIRST", expectedAsset: firstRow.assetID,
                expectedWindow: firstRow.imageInputWindowNumber, expectedPoint: point, radius: 1.5)
            let quartz = SoftwarePointerProbe.quartzPoint(point, primaryFrame: primary.frame)
            let beforePID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
            let beforeKey = NSApp.keyWindow?.windowNumber ?? -1
            let beforeEditor = self.editor.currentEditor() != nil && self.window.firstResponder === self.editor.currentEditor()
            let interval = NSEvent.doubleClickInterval
            guard self.postDoublePair(first, point: quartz, clickCount: 1) else {
                self.record("software_double_case", ["result": "NOT_RUN", "reason": "eventAllocationFailed", "pairsPosted": 0]); return
            }
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch {
                self.record("software_double_case", ["result": "INCONCLUSIVE", "reason": "cancelledAfterFirstPair", "pairsPosted": 1]); return
            }
            guard scene == self.sceneGeneration, first.verdict(focusStable: true) == "PASS_SOFTWARE_ROUTING",
                  let firstDown = first.downIdentity else {
                self.record("software_double_case", ["result": "INCONCLUSIVE", "reason": "firstPairNotConfirmed", "pairsPosted": 1]); return
            }
            // Display-only synthetic completion, using the existing helper path.
            // It cannot fabricate an upload receipt or invoke product transfer.
            self.records = SyntheticScene.displaying(.used, assetID: firstRow.assetID, in: self.records)
            self.rift?.render(self.records)
            self.refreshTargets()
            // AppKit's model frame may precede the WindowServer update. Yield
            // only for read-only samples, under the original first-down deadline.
            let postingDeadline = firstDown.time + interval - 0.02
            var readySnapshot: RiftDiagnosticSnapshot?
            var lastReason = "notSampled"
            var samples = 0
            var reasonCounts: [String: Int] = [:]
            var lastFields: [String: Any] = [:]
            while samples < 64 {
                guard !Task.isCancelled else { lastReason = "cancelled"; break }
                guard ProcessInfo.processInfo.systemUptime < postingDeadline else { lastReason = "originalIntervalExpired"; break }
                samples += 1
                guard scene == self.sceneGeneration else { lastReason = "sceneChanged"; break }
                guard !first.interference else { lastReason = "inputInterference"; break }
                if let unavailable = self.softwareProbeUnavailable() {
                    lastReason = unavailable; break
                }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == beforePID,
                      NSApp.keyWindow?.windowNumber == beforeKey else { lastReason = "focusChanged"; break }
                guard let candidate = self.rift?.diagnosticSnapshot,
                      candidate.rows.map({ $0.assetID }) == snapshot.rows.dropFirst().map({ $0.assetID }),
                      let moved = candidate.rows.first, moved.assetID == replacement.assetID,
                      moved.imageInputWindowNumber == replacement.imageInputWindowNumber else {
                    lastReason = "replacementIdentityChanged"; break
                }
                let nativeFrame = self.nativeInputFrame(windowNumber: moved.imageInputWindowNumber,
                                                        primaryFrame: primary.frame)
                let stack = self.ownedProbeStack(at: point, snapshot: candidate)
                let top = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
                let firstInteractive = stack?.first(where: { number in
                    NSApp.windows.first(where: { $0.windowNumber == number })?.ignoresMouseEvents == false
                })
                lastFields = ["sampleUptime": ProcessInfo.processInfo.systemUptime,
                    "nativeFrame": nativeFrame.map { self.rectFields($0) } ?? [:],
                    "nativeFrameAvailable": nativeFrame != nil,
                    "modelFrame": self.rectFields(moved.imageInputFrame),
                    "queriedTopWindow": top, "queriedOwnedWindowStack": stack ?? [],
                    "firstInteractiveWindow": firstInteractive ?? 0]
                if !moved.imageClipFrame.contains(point) || !moved.imageInputFrame.contains(point) {
                    lastReason = "modelFrameNotAtFrozenPoint"
                } else if nativeFrame == nil {
                    lastReason = "nativeFrameUnavailable"
                } else if nativeFrame?.contains(point) != true {
                    lastReason = "nativeFrameNotAtFrozenPoint"
                } else if stack == nil {
                    lastReason = "nativeOwnedStackUnavailable"
                } else if firstInteractive != moved.imageInputWindowNumber {
                    lastReason = "replacementNotFirstInteractiveWindow"
                } else {
                    lastReason = "ready"; readySnapshot = candidate; break
                }
                reasonCounts[lastReason, default: 0] += 1
                do { try await Task.sleep(nanoseconds: 5_000_000) }
                catch { lastReason = "cancelled"; break }
            }
            let retryableReasons: Set<String> = ["modelFrameNotAtFrozenPoint", "nativeFrameUnavailable",
                "nativeFrameNotAtFrozenPoint", "nativeOwnedStackUnavailable", "replacementNotFirstInteractiveWindow"]
            if samples == 64 && readySnapshot == nil && retryableReasons.contains(lastReason)
                && ProcessInfo.processInfo.systemUptime < postingDeadline {
                lastReason = "nativeSampleLimitReached"
            }
            var waitFields: [String: Any] = ["samples": samples, "reason": lastReason,
                "reasonCounts": reasonCounts, "postingDeadline": postingDeadline,
                "originalFirstDownEventUptime": firstDown.time, "systemDoubleClickInterval": interval,
                "replacementAssetID": replacement.assetID.uuidString,
                "replacementWindow": replacement.imageInputWindowNumber,
                "lastNativeSample": lastFields, "secondPairPosted": false]
            self.record("software_double_replacement_wait", waitFields)
            guard let current = readySnapshot, let moved = current.rows.first,
                  ProcessInfo.processInfo.systemUptime < postingDeadline else {
                if readySnapshot != nil { lastReason = "originalIntervalExpiredAfterSample" }
                waitFields["result"] = "INCONCLUSIVE"; waitFields["reason"] = lastReason
                waitFields["secondPairVerdict"] = "NOT_RUN"; waitFields["pairsPosted"] = 1
                self.record("software_double_case", waitFields); return
            }
            self.record("software_double_replacement", ["removedAssetID": firstRow.assetID.uuidString,
                "replacementAssetID": moved.assetID.uuidString, "replacementWindow": moved.imageInputWindowNumber,
                "originalFirstWindow": firstRow.imageInputWindowNumber, "replacementFrame": self.rectFields(moved.imageInputFrame),
                "systemDoubleClickInterval": interval, "firstDownEventUptime": firstDown.time, "receiptEvidence": false])
            let second = SoftwarePointerProbe.Receipt(name: "DOUBLE_SECOND", expectedAsset: moved.assetID,
                expectedWindow: moved.imageInputWindowNumber, expectedPoint: point, radius: 1.5)
            let finalRefusal: String?
            if ProcessInfo.processInfo.systemUptime >= postingDeadline { finalRefusal = "originalIntervalExpiredBeforePost" }
            else if let unavailable = self.softwareProbeUnavailable() { finalRefusal = unavailable }
            else if first.interference { finalRefusal = "inputInterference" }
            else if scene != self.sceneGeneration { finalRefusal = "sceneChanged" }
            else if self.rift?.diagnosticSnapshot.rows != current.rows { finalRefusal = "geometryChangedBeforePost" }
            else { finalRefusal = nil }
            if let finalRefusal {
                self.record("software_double_case", ["result": "INCONCLUSIVE", "reason": finalRefusal,
                    "secondPairVerdict": "NOT_RUN", "pairsPosted": 1]); return
            }
            guard self.postDoublePair(second, point: quartz, clickCount: 2) else {
                self.record("software_double_case", ["result": "INCONCLUSIVE", "reason": "secondAllocationFailed", "pairsPosted": 1]); return
            }
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            let afterEditor = self.editor.currentEditor() != nil && self.window.firstResponder === self.editor.currentEditor()
            let focusStable = beforePID == NSWorkspace.shared.frontmostApplication?.processIdentifier
                && beforeKey == NSApp.keyWindow?.windowNumber && beforeEditor == afterEditor
            let geometryStable = current.rows == self.rift?.diagnosticSnapshot.rows
            let verdict = scene == self.sceneGeneration && geometryStable
                ? SoftwarePointerProbe.doubleVerdict(first: first, second: second, interval: interval, focusStable: focusStable)
                : "INCONCLUSIVE"
            self.record("software_double_case", ["result": verdict, "pairsPosted": 2, "inputOrigin": "CGEvent", "physical": false,
                "physicalVerdict": "NOT_RUN", "osDoubleClickClassification": "NOT_TESTED", "crossApplicationFocusVerdict": "NOT_RUN",
                "originalAssetID": first.expectedAsset.uuidString, "replacementAssetID": second.expectedAsset.uuidString,
                "firstToken": first.token, "secondToken": second.token, "firstWindow": first.expectedWindow, "secondWindow": second.expectedWindow,
                "firstReceivedWindows": first.receivedWindows, "secondReceivedWindows": second.receivedWindows,
                "firstDownCount": first.downCount, "firstUpCount": first.upCount, "secondDownCount": second.downCount, "secondUpCount": second.upCount,
                "firstAcceptedAssets": first.acceptedAssets.map { $0.uuidString }, "firstSelectedAssets": first.selectedAssets.map { $0.uuidString },
                "secondAcceptedAssets": second.acceptedAssets.map { $0.uuidString }, "secondSelectedAssets": second.selectedAssets.map { $0.uuidString },
                "secondUnderlayDownCount": second.probeDownCount, "secondUnderlayUpCount": second.probeUpCount,
                "secondDownClickCount": second.downClickCount ?? -1,
                "downIntervalSeconds": (second.downIdentity?.time ?? firstDown.time) - firstDown.time,
                "systemDoubleClickInterval": interval, "focusEndpointsStable": focusStable,
                "geometryStable": geometryStable, "coordinatesMatch": first.coordinatesMatch && second.coordinatesMatch,
                "interference": first.interference || second.interference])
        }
    }

    /// WindowServer metadata, not an AppKit model frame and not a screenshot.
    private func nativeInputFrame(windowNumber: Int, primaryFrame: CGRect) -> CGRect? {
        guard windowNumber > 0,
              let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(windowNumber)) as? [[String: Any]],
              let item = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == windowNumber }),
              (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ProcessInfo.processInfo.processIdentifier,
              (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
              let bounds = item[kCGWindowBounds as String] as? [String: Any],
              let quartzFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return SoftwarePointerProbe.appKitFrame(quartzFrame, primaryFrame: primaryFrame)
    }

    /// Query-only safety guard. Walk past this helper's known visual/input
    /// panels to its own probe. NSWindow ordering queries may include windows
    /// with ignoresMouseEvents; this prediction never supplies a routing PASS.
    private func ownedProbeStack(at point: CGPoint, snapshot: RiftDiagnosticSnapshot) -> [Int]? {
        let products = Set(snapshot.rows.flatMap { [$0.windowNumber, $0.imageInputWindowNumber, $0.numberInputWindowNumber] })
        var result: [Int] = [], below = 0
        for _ in 0..<16 {
            let next = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: below)
            guard next > 0, !result.contains(next), NSApp.windows.contains(where: { $0.windowNumber == next }) else { return nil }
            result.append(next)
            if next == window.windowNumber { return result }
            guard products.contains(next) else { return nil }
            below = next
        }
        return nil
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
        guard let rift, let window else { return }
        let snapshot = rift.diagnosticSnapshot
        guard !snapshot.isHolding, !snapshot.isTransitioning else {
            probe.targets = []; probe.needsDisplay = true
            record("probe_targets_unavailable", ["holding": snapshot.isHolding, "transitioning": snapshot.isTransitioning])
            return
        }
        targetRows = snapshot.rows
        let screen = actualRowScreen(snapshot)
        let candidates = screen.map { ProbeTarget.make(snapshot: snapshot, screen: $0.visibleFrame) } ?? []
        func exclusion(_ target: ProbeTarget) -> String? {
            let point = probe.convert(window.convertPoint(fromScreen: target.screenPoint), from: nil)
            if !probe.bounds.contains(point) { return "outsideProbeContent" }
            if probe.subviews.contains(where: { $0.frame.contains(point) }) { return "coveredByControlSubview" }
            return nil
        }
        // Preserve candidate positions even when no underlying probe can receive
        // them. Missing coverage is a helper setup result, not a product verdict.
        probe.targets = candidates.filter { exclusion($0) == nil }
        probe.needsDisplay = true
        record("probe_targets", ["targets": probe.targets.map { target in
            let stack = ownedProbeStack(at: target.screenPoint, snapshot: snapshot)
            let underneath = stack?.last ?? 0
            return ["name": target.name, "x": target.screenPoint.x, "y": target.screenPoint.y,
             "radius": target.radius,
             "quartzPoint": quartzFields(target.screenPoint),
             "predictedUnderlyingWindow": underneath, "queriedOwnedWindowStack": stack ?? [],
             "underlyingProbePredicted": underneath == window.windowNumber,
             "predictedWindow": NSWindow.windowNumber(at: target.screenPoint, belowWindowWithWindowNumber: 0)] as [String: Any]
        }, "candidateTargets": candidates.map { target in
            ["name": target.name, "x": target.screenPoint.x, "y": target.screenPoint.y,
             "quartzPoint": quartzFields(target.screenPoint), "exclusion": exclusion(target) ?? "none"] as [String: Any]
        }, "probeContentFrameOnScreen": rectFields(window.convertToScreen(probe.convert(probe.bounds, to: nil))),
        "screens": NSScreen.screens.map { item in
            let id = (item.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return ["id": id, "frame": rectFields(item.frame), "visibleFrame": rectFields(item.visibleFrame),
                    "backingScaleFactor": item.backingScaleFactor, "rotationDegrees": CGDisplayRotation(id)] as [String: Any]
        }, "rowScreenID": (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
        "rows": snapshot.rows.map { row in
            ["assetID": row.assetID.uuidString, "ordinal": row.ordinal, "window": row.windowNumber,
             "frame": rectFields(row.frame), "image": rectFields(row.imageClipFrame),
             "number": rectFields(row.numberFrame),
             "imageInputWindow": row.imageInputWindowNumber, "numberInputWindow": row.numberInputWindowNumber,
             "imageInputFrame": rectFields(row.imageInputFrame), "numberInputFrame": rectFields(row.numberInputFrame)] as [String: Any]
        }, "coordinateSpace": "AppKit global screen points; Quartz global points, no backing-scale multiplication",
            "primaryScreenFrame": rectFields(NSScreen.screens.first?.frame ?? .zero),
            "predictionIsPassEvidence": false])
    }
}

@MainActor
private final class ClickProbeView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var targets: [ProbeTarget] = []
    private var lastPoint: CGPoint?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
        onMouseDown?(event)
    }

    override func mouseUp(with event: NSEvent) { onMouseUp?(event) }

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
