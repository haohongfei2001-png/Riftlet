import AppKit
import Darwin
import RiftletCore
import RiftletUI

@main
enum AcceptanceMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--help") {
            print("""
            RiftletGUIAcceptance [--self-check]
            GUI: synthetic 2/3/12-image scenes, click/focus observations and delayed reorder.
            JSONL observations go to stdout; typed text is never included.
            --self-check validates fixtures/layout only and does not run GUI acceptance.
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

    func applicationWillTerminate(_ notification: Notification) {
        reorderTask?.cancel()
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
        Synthetic fixtures only. Click the text field, then a thumbnail, then type. The log records the actual key/main window, frontmost app and whether the field still owns focus; it never records typed text.
        The empty area underneath the right-edge panels is the click probe. Test gaps, outer inset, number, image, clear corners and animation edges. A received probe click is an observation, not an inferred hit-test result.
        For held-pointer behavior: arm the 3-second reorder, then hold a lower thumbnail until the first item is marked used. Release and inspect the selected immutable ID.
        This helper's text field is in the same process as its panels. Also repeat focus checks with another app in front; this helper alone cannot certify cross-application focus or fullscreen behavior.
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
        let actions = NSStackView(views: [outcome, button("Arm reorder in 3s", #selector(armReorder)),
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
        let stack = NSStackView(views: [title, guidance, scenes, actions, editor, status, scroll])
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
    }

    func controlTextDidChange(_ notification: Notification) {
        record("probe_text_changed", ["length": editor.stringValue.count])
    }

    private func eventFields(_ event: NSEvent) -> [String: Any] {
        var fields: [String: Any] = ["eventTime": event.timestamp, "window": event.windowNumber]
        // Physical keycodes can reconstruct typing even without event.characters.
        // Record only the occurrence of a key event and focus, never its identity.
        if event.type != .keyDown, let eventWindow = event.window {
            let point = eventWindow.convertPoint(toScreen: event.locationInWindow)
            fields["screenX"] = point.x
            fields["screenY"] = point.y
            fields["clickCount"] = event.clickCount
        }
        return fields
    }

    private func record(_ name: String, _ fields: [String: Any] = [:]) {
        var value = fields
        value["event"] = name
        value["uptime"] = ProcessInfo.processInfo.systemUptime
        value["syntheticOnly"] = true
        value["helperActive"] = NSApp.isActive
        value["keyWindow"] = NSApp.keyWindow?.windowNumber ?? -1
        value["mainWindow"] = NSApp.mainWindow?.windowNumber ?? -1
        value["frontmostBundle"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unidentified"
        value["probeEditorFocused"] = editor.currentEditor() != nil && window?.firstResponder === editor.currentEditor()
        value["underlyingClickCount"] = underlyingClicks
        value["selectionCount"] = selectionCount
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
        outcomeTasks.values.forEach { $0.cancel() }
        outcomeTasks.removeAll()
        do { records = try SyntheticScene.records(from: fixtures, count: count) }
        catch { record("fixture_error"); return }
        rift?.close()
        var configuration = RiftConfiguration()
        configuration.preferredDisplayID = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        rift = RiftPanelController(mediaDirectory: mediaRoot, configuration: configuration) { [weak self] id in
            self?.selected(id)
        }
        rift?.render(records)
        record("scene_reset", ["count": count, "assetIDs": records.map { $0.id.uuidString }])
    }

    private func selected(_ id: UUID) {
        selectionCount += 1
        guard let selected = records.first(where: { $0.id == id }) else {
            record("selection_not_in_scene", ["assetID": id.uuidString])
            return
        }
        record("thumbnail_selected", ["assetID": id.uuidString, "sequence": selected.sequence,
                                       "stateBefore": selected.status.rawValue])
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
    @objc private func showOldest() { rift?.showOldest(); record("show_oldest") }
    @objc private func showLatest() { rift?.showLatest(); record("show_latest") }
    @objc private func focusEditor() { window.makeFirstResponder(editor); record("focus_requested") }

    @objc private func armReorder() {
        guard let first = records.first(where: { $0.status != .used }) else { return }
        reorderTask?.cancel()
        let token = sceneGeneration
        record("reorder_armed", ["assetID": first.id.uuidString, "delaySeconds": 3])
        reorderTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            guard let self, self.sceneGeneration == token else { return }
            self.records = SyntheticScene.displaying(.used, assetID: first.id, in: self.records)
            self.rift?.render(self.records)
            self.record("reorder_requested", ["assetID": first.id.uuidString,
                                               "activeIDs": self.records.filter { $0.status != .used }.map { $0.id.uuidString },
                                               "receiptEvidence": false])
        }
    }
}

@MainActor
private final class ClickProbeView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
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
        if let lastPoint {
            NSColor.systemOrange.setStroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: lastPoint.x - 7, y: lastPoint.y - 7, width: 14, height: 14))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
