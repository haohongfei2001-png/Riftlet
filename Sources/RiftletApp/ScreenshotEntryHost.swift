import AppKit
import RiftletCore
import RiftletCapture
import RiftletUI

/// Composes capture, presentation and durable collection. It never dispatches
/// attachments or changes admission. A successful capture does not end a session.
@MainActor
final class ScreenshotEntryHost {
    let entry: ScreenshotEntryController
    let capture: InteractiveScreenshotController
    private let rift: RiftPanelController
    private let importer: PrivateAssetImporter
    private let outputDirectory: URL
    private let preferencesURL: URL
    private var preferences: ScreenshotEntryPreferences
    private let onChange: @MainActor () async -> Void
    private let onIssue: (String) -> Void
    private let onPreferencesChange: () -> Void
    private var userHidden = false
    var isEnabled: Bool { preferences.isEnabled }
    var defaultMode: ScreenshotMode { preferences.defaultMode }
    private var menuOpen = false
    private var editor: ScreenshotMarkupController?
    private var cancelling = false
    private var closed = false
    private var screenObserver: NSObjectProtocol?
    private var windowCloseObserver: NSObjectProtocol?
    private var otherSuppressedWindows: [NSWindow] = []
    private var exposureIsSuppressed = false

    init(root: URL, store: QueueStore, rift: RiftPanelController,
         onChange: @escaping @MainActor () async -> Void,
         onIssue: @escaping (String) -> Void, onPreferencesChange: @escaping () -> Void = {}) throws {
        self.rift = rift; self.onChange = onChange; self.onIssue = onIssue
        self.onPreferencesChange = onPreferencesChange
        outputDirectory = root.appendingPathComponent("captures", isDirectory: true)
        preferencesURL = root.appendingPathComponent("capture-entry-settings.json")
        preferences = try ScreenshotEntryPreferences.load(from: preferencesURL)
        let firstInstallation = !FileManager.default.fileExists(atPath: preferencesURL.path)
        if firstInstallation {
            let adjusted = ScreenshotEntryPreferences.initialLayout(rift.configuration)
            if adjusted != rift.configuration {
                try adjusted.validate()
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(adjusted).write(to: root.appendingPathComponent("rift-configuration.json"), options: .atomic)
                try rift.updateConfiguration(adjusted)
            }
            try preferences.save(to: preferencesURL)
        }
        importer = PrivateAssetImporter(privateRoot: root, store: store)
        entry = ScreenshotEntryController(defaultMode: preferences.defaultMode)
        capture = InteractiveScreenshotController(outputDirectory: outputDirectory)
        entry.setHidden(!preferences.isEnabled)
        wireCallbacks()
        rift.onGeometryChange = { [weak self] in self?.configure() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.configure(); self?.onPreferencesChange() }
            }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    self?.otherSuppressedWindows.removeAll { $0 === window }
                }
            }
        configure()
    }

    private func wireCallbacks() {
        entry.onBegin = { [weak self] mode in
            guard let self, !self.closed else { return }
            self.startCapture(mode: mode)
        }
        entry.onMode = { [weak self] mode in
            guard let self, !self.closed else { return }
            if self.capture.isActive { self.capture.updateMode(mode) }
            else { self.startCapture(mode: mode) }
        }
        entry.onCancel = { [weak self] in self?.cancel() }
        entry.onOptions = { [weak self] options in self?.capture.updateOptions(options) }
        entry.onSettings = { [weak self] mode in self?.saveDefault(mode) }
        entry.onMenuVisibility = { [weak self] open in
            guard let self else { return }
            self.menuOpen = open; self.updateSuspension()
        }
        capture.onCancel = { [weak self] in self?.cancel() }
        capture.onError = { [weak self] error in
            self?.onIssue(error.localizedDescription)
        }
        capture.onCaptureVisibilityChanged = { [weak self] hidden in
            self?.setExposureSuppressed(hidden)
        }
        capture.onCapture = { [weak self] image in self?.received(image) }
    }

    func configure() {
        guard !closed else { return }
        guard preferences.isEnabled else {
            rift.setCaptureHeaderAnchor(nil); entry.configure(screen: nil); return
        }
        guard let screen = rift.preferredScreen else {
            entry.configure(screen: nil); return
        }
        let placement = ScreenshotEntryPreferences.placement(in: screen.visibleFrame, configuration: rift.configuration)
        rift.setCaptureHeaderAnchor(placement.queueHeader)
        guard placement.queueHeader != nil else { entry.configure(screen: nil); return }
        let queue = rift.diagnosticSnapshot.rows.flatMap { [$0.imageInputFrame, $0.numberInputFrame] }
        entry.configure(screen: screen, anchor: placement.anchor, queueFrames: queue)
    }

    func beginFromMenu() {
        guard !closed, !entry.isHidden else { return }
        if !entry.isExpanded { entry.setExpanded(true) }
        if !capture.isActive { startCapture(mode: entry.mode) }
    }

    private func startCapture(mode: ScreenshotMode) {
        rift.setCaptureSessionActive(true)
        capture.start(mode: mode, options: entry.options)
        // Permission refusal/no display never creates a capture session. Return
        // to a truthful retryable entry instead of displaying an inactive X.
        if !capture.isActive {
            entry.setExpanded(false)
            rift.setCaptureSessionActive(false)
        }
    }

    func setHidden(_ hidden: Bool) {
        userHidden = hidden
        if hidden { cancel() }
        entry.setHidden(hidden || !preferences.isEnabled)
    }

    func setEnabled(_ enabled: Bool) throws {
        var proposed = preferences; proposed.isEnabled = enabled
        try proposed.save(to: preferencesURL)
        preferences = proposed
        if !enabled { cancel() }
        entry.setHidden(userHidden || !enabled)
        configure(); onPreferencesChange()
    }

    func selectDefaultMode(_ mode: ScreenshotMode) throws {
        var proposed = preferences; proposed.defaultMode = mode
        try proposed.save(to: preferencesURL)
        preferences = proposed
        entry.setDefaultMode(mode)
        onPreferencesChange()
    }

    private func saveDefault(_ mode: ScreenshotMode) {
        do { try selectDefaultMode(mode) }
        catch {
            entry.setDefaultMode(preferences.defaultMode)
            onIssue("默认截图方式未能保存，请稍后重试。")
        }
    }

    private func updateSuspension() {
        capture.setInteractionSuspended(menuOpen || editor != nil)
    }

    private func setExposureSuppressed(_ hidden: Bool) {
        guard !closed, hidden != exposureIsSuppressed else { return }
        exposureIsSuppressed = hidden
        // This is self-exclusion during one exposure, not a UI collapse.
        entry.setCaptureSuppressed(hidden); rift.setCaptureSuppressed(hidden)
        if hidden {
            let selectionIDs = Set(capture.selectionWindowIDs)
            otherSuppressedWindows = NSApp.windows.filter {
                $0.isVisible && $0.alphaValue > 0 && !selectionIDs.contains($0.windowNumber)
            }
            otherSuppressedWindows.forEach { $0.orderOut(nil) }
        } else {
            otherSuppressedWindows.forEach { $0.orderFrontRegardless() }
            otherSuppressedWindows.removeAll()
        }
    }

    private func received(_ result: InteractiveScreenshotCapture) {
        guard !closed else { return }
        if result.options.editAfter, let editor = ScreenshotMarkupController(pngData: result.pngData) {
            self.editor = editor
            entry.setBusy(true); updateSuspension()
            editor.onFinish = { [weak self] editedData in
                guard let self else { return }
                self.editor = nil; self.entry.setBusy(false); self.updateSuspension()
                self.collect(result, editedData: editedData)
            }
            editor.present()
        } else {
            collect(result, editedData: nil)
        }
        // Deliberately no setExpanded(false), cancel(), or mode/order mutation.
    }

    private func collect(_ result: InteractiveScreenshotCapture, editedData: Data?) {
        let importer = self.importer, directory = outputDirectory
        Task { [weak self] in
            do {
                let source: URL
                let origin: AssetOrigin
                if let editedData {
                    source = directory.appendingPathComponent(UUID().uuidString.lowercased() + "-edited.png")
                    try editedData.write(to: source, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
                    origin = .applicationScreenshot
                } else {
                    source = result.sourceURL
                    origin = result.hasSystemScreenshotMetadata ? .systemScreenshot : .applicationScreenshot
                }
                _ = try await importer.importCompletedScreenshot(at: source, origin: origin)
                guard let self, !self.closed else { return }
                await self.onChange()
                self.rift.showLatest(); self.configure()
            } catch {
                self?.onIssue("截图原文件已保留，暂未加入裂缝。请检查可用存储空间后重试。")
            }
        }
    }

    func cancel() {
        guard !closed, !cancelling else { return }
        cancelling = true
        capture.cancel()
        setExposureSuppressed(false)
        editor?.keepOriginalAndClose(); editor = nil
        menuOpen = false
        entry.setCaptureSuppressed(false); entry.setBusy(false)
        entry.setExpanded(false)
        rift.setCaptureSuppressed(false); rift.setCaptureSessionActive(false)
        cancelling = false
    }

    func close() {
        guard !closed else { return }
        cancel(); closed = true
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let windowCloseObserver { NotificationCenter.default.removeObserver(windowCloseObserver) }
        screenObserver = nil
        windowCloseObserver = nil
        rift.onGeometryChange = nil
        entry.close()
    }
}
