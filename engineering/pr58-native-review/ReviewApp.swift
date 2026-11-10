import AppKit

@main
@MainActor
enum ReviewApp {
    static func main() {
        let app = NSApplication.shared
        let coordinator = ReviewCoordinator()
        app.setActivationPolicy(.regular)
        app.delegate = coordinator
        withExtendedLifetime(coordinator) { app.run() }
    }
}

@MainActor
private final class ReviewCoordinator: NSObject, NSApplicationDelegate {
    private var previousApp: NSRunningApplication?
    private lazy var settings = ReviewSettings()
    private lazy var surfaces = ReviewSurfaces()
    private let isRecording = CommandLine.arguments.contains("--window-receipts")

    func applicationDidFinishLaunching(_ notification: Notification) {
        previousApp = NSWorkspace.shared.frontmostApplication
        settings.onOpenHistory = { [weak self] in
            guard let self else { return }
            _ = self.show(self.settings.prefersHistoryGrid ? "history-grid" : "history-list")
        }
        settings.onOpenFeedback = { [weak self] in _ = self?.show("feedback") }
        settings.onShowGuide = { [weak self] in _ = self?.show("intro-capture") }
        settings.onReviewValueChange = { [weak self] key, value in self?.surfaces.applyReviewValue(key, value) }
        surfaces.onReviewValueChange = { [weak self] key, value in self?.settings.setReviewValue(key, value) }
        for key in ["collection", "hidden", "built-in", "history-style"] {
            surfaces.applyReviewValue(key, settings.reviewValue(key))
        }
        surfaces.onSettings = { [weak self] in _ = self?.show("settings-0") }
        let menu = NSMenu()
        let application = NSMenuItem()
        menu.addItem(application)
        let appMenu = NSMenu()
        application.submenu = appMenu
        appMenu.addItem(withTitle: "退出界面预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let pages = NSMenuItem()
        menu.addItem(pages)
        let pageMenu = NSMenu(title: "窗口")
        pages.submenu = pageMenu
        for (i, name) in ReviewSettings.pageNames.enumerated() {
            add(name, key: "settings-\(i)", to: pageMenu)
        }
        add("保存失败与重试", key: "save-error", to: pageMenu)
        pageMenu.addItem(.separator())
        add("控制中心 · 当前状态", key: "control-current", to: pageMenu)
        let samples = NSMenuItem(title: "场景示例", action: nil, keyEquivalent: "")
        let sampleMenu = NSMenu(title: "场景示例")
        samples.submenu = sampleMenu
        pageMenu.addItem(samples)
        for scene in ReviewSurfaces.scenes {
            add(ReviewSurfaces.title(for: scene), key: scene, to: sampleMenu)
        }
        NSApp.mainMenu = menu
        if isRecording {
            emit(["settings": ReviewSettings.pageNames, "surfaces": ReviewSurfaces.scenes])
            receive()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            _ = show("settings-0")
        }
    }

    private func add(_ title: String, key: String, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: #selector(selectScene(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = key
    }

    @objc private func selectScene(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String { _ = show(key) }
    }

    private func show(_ scene: String) -> NSWindow? {
        surfaces.dismiss()
        if scene == "save-error" {
            settings.showSaveFailurePreview()
            settings.window.makeKeyAndOrderFront(nil)
            return settings.window
        }
        if scene.hasPrefix("settings-"), let i = Int(scene.dropFirst(9)), ReviewSettings.pageNames.indices.contains(i) {
            settings.showPage(i)
            settings.window.makeKeyAndOrderFront(nil)
            return settings.window
        }
        settings.window.orderOut(nil)
        guard scene == "control-current" || ReviewSurfaces.scenes.contains(scene) else { return nil }
        return surfaces.show(scene)
    }

    // Receipts refer only to windows created by this preview executable.
    private func emit(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        FileHandle.standardOutput.write(data + Data([10]))
    }

    func applicationWillTerminate(_ notification: Notification) {
        if isRecording, NSRunningApplication.current.isActive,
           previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
    }

    private func receive() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let command = readLine()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let command, command != "quit" else { NSApp.terminate(nil); return }
                let fields = command.split(separator: " ").map(String.init)
                guard fields.count == 2 else { self.emit(["error": "scene"]); self.receive(); return }
                NSApp.appearance = NSAppearance(named: fields[0] == "dark" ? .darkAqua : .aqua)
                let window = self.show(fields[1])
                NSApp.activate(ignoringOtherApps: true)
                window?.orderFrontRegardless()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    self.emit(["window": window?.windowNumber ?? -1, "visible": window?.isVisible ?? false,
                               "scene": fields[1], "pid": ProcessInfo.processInfo.processIdentifier,
                               "width": window?.frame.width ?? 0, "height": window?.frame.height ?? 0])
                    self.receive()
                }
            }
        }
    }
}
