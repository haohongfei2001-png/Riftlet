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
    private let savePreferences: (ScreenshotEntryPreferences, URL) throws -> Void
    var onPreferencesChanged: (() -> Void)?
    var isEnabled: Bool { preferences.builtInScreenshotEnabled }
    var defaultMode: ScreenshotMode { preferences.defaultMode }
    private(set) var preferenceSaveFailed = false
    private var userHidden = false
    private var menuOpen = false
    private var editor: ScreenshotMarkupController?
    private var editorID: UUID?
    private var cancelling = false
    private var closed = false
    private var screenObserver: NSObjectProtocol?
    private var windowCloseObserver: NSObjectProtocol?
    private var otherSuppressedWindows: [NSWindow] = []
    private var exposureIsSuppressed = false

    init(root: URL, store: QueueStore, rift: RiftPanelController,
         onChange: @escaping @MainActor () async -> Void,
         onIssue: @escaping (String) -> Void,
         captureController: InteractiveScreenshotController? = nil,
         savePreferences: @escaping (ScreenshotEntryPreferences, URL) throws -> Void = { try $0.save(to: $1) }) throws {
        self.rift = rift; self.onChange = onChange; self.onIssue = onIssue
        self.savePreferences = savePreferences
        outputDirectory = root.appendingPathComponent("captures", isDirectory: true)
        preferencesURL = root.appendingPathComponent("capture-entry-settings.json")
        preferences = try ScreenshotEntryPreferences.load(from: preferencesURL)
        let firstInstallation = !FileManager.default.fileExists(atPath: preferencesURL.path)
        if firstInstallation {
            try savePreferences(preferences, preferencesURL)
        }
        importer = PrivateAssetImporter(privateRoot: root, store: store)
        entry = ScreenshotEntryController(defaultMode: preferences.defaultMode,
                                          isEnabled: preferences.builtInScreenshotEnabled)
        capture = captureController ?? InteractiveScreenshotController(outputDirectory: outputDirectory,
            isEnabled: preferences.builtInScreenshotEnabled)
        capture.setEnabled(preferences.builtInScreenshotEnabled)
        wireCallbacks()
        rift.onGeometryChange = { [weak self] in self?.configure() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.configure(); self?.onPreferencesChanged?() }
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
        entry.onGeometryChange = { [weak self] in
            guard let self else { return }
            self.rift.setExtraPreviewExclusions(self.entry.inputFrames)
        }
        entry.onBegin = { [weak self] mode in
            guard let self, !self.closed, self.isEnabled, !self.userHidden else { return }
            self.startCapture(mode: mode)
        }
        entry.onMode = { [weak self] mode in
            guard let self, !self.closed, self.isEnabled, !self.userHidden else { return }
            if self.capture.isActive { self.capture.updateMode(mode) }
            else { self.startCapture(mode: mode) }
            // A pending request keeps the same phase when only the next mode
            // changes, so it intentionally emits no new capture state event.
            self.updateCapturePresentation()
        }
        entry.onCancel = { [weak self] in self?.cancel() }
        entry.onOptions = { [weak self] options in
            guard let self, self.isEnabled, !self.closed else { return }
            self.capture.updateOptions(options)
        }
        entry.onSettings = { [weak self] mode in self?.saveDefault(mode) }
        entry.onMenuVisibility = { [weak self] open in
            guard let self, self.isEnabled, !self.closed else { return }
            self.menuOpen = open; self.updateSuspension()
        }
        capture.onCancel = { [weak self] in self?.cancel() }
        capture.onStateChange = { [weak self] _ in self?.updateCapturePresentation() }
        capture.onError = { [weak self] error in
            guard let self, self.isEnabled, !self.closed else { return }
            self.onIssue(error.localizedDescription)
        }
        capture.onCaptureVisibilityChanged = { [weak self] hidden in
            self?.setExposureSuppressed(hidden)
        }
        capture.onCapture = { [weak self] image in self?.received(image) }
    }

    private func updateCapturePresentation() {
        entry.setCapturePresentation(!closed && isEnabled && !userHidden && !cancelling
            ? capture.presentationSnapshot : nil)
    }

    func configure() {
        guard !closed else { return }
        guard isEnabled else {
            rift.setCaptureHeaderAnchor(nil)
            entry.configure(screen: nil)
            return
        }
        guard let screen = rift.preferredScreen else {
            entry.configure(screen: nil); return
        }
        guard let anchor = rift.screenshotEntryAnchor else { entry.configure(screen: nil); return }
        entry.configure(screen: screen, anchor: anchor, queueFrames: rift.screenshotEntryExclusionFrames)
        rift.setExtraPreviewExclusions(entry.inputFrames)
    }

    func beginFromMenu() {
        guard !closed, isEnabled, !userHidden, !entry.isHidden else { return }
        if !entry.isExpanded { entry.setExpanded(true) }
        if !capture.isActive { startCapture(mode: entry.mode) }
    }

    private func startCapture(mode: ScreenshotMode) {
        guard isEnabled, !closed, !userHidden, !cancelling else { return }
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
        entry.setHidden(hidden)
    }

    /// Disabling is immediate even on a full/read-only disk. Enabling becomes
    /// effective only after persistence succeeds. Neither path touches the
    /// system collector, visibility preference, queue or original files.
    func setEnabled(_ enabled: Bool) {
        guard !closed else { return }
        guard enabled != isEnabled || preferenceSaveFailed else { return }
        var proposed = preferences; proposed.builtInScreenshotEnabled = enabled
        if !enabled {
            preferences.builtInScreenshotEnabled = false
            capture.setEnabled(false)
            cancel()
            entry.setEnabled(false)
            rift.setCaptureHeaderAnchor(nil)
        }
        do {
            try savePreferences(proposed, preferencesURL)
            preferences = proposed; preferenceSaveFailed = false
            capture.setEnabled(enabled)
            entry.setEnabled(enabled)
            entry.setHidden(userHidden)
            configure()
        } catch {
            preferenceSaveFailed = true
            onIssue(enabled ? "内置截图设置未能保存，开关状态未改变。请检查可用存储空间后重试。"
                : "内置截图已关闭，但设置未能保存；重启可能恢复原设置。请检查可用存储空间后重试。")
        }
        onPreferencesChanged?()
    }

    func saveDefault(_ mode: ScreenshotMode) {
        guard !closed else { return }
        var proposed = preferences; proposed.defaultMode = mode
        do {
            try savePreferences(proposed, preferencesURL)
            preferences = proposed; preferenceSaveFailed = false
            entry.setDefaultMode(mode)
        }
        catch {
            preferenceSaveFailed = true
            entry.setDefaultMode(preferences.defaultMode)
            onIssue("默认截图方式未能保存，请稍后重试。")
        }
        onPreferencesChanged?()
    }

    private func updateSuspension() {
        guard !closed, isEnabled, !cancelling else { return }
        capture.setInteractionSuspended(menuOpen || editor != nil)
    }

    private func setExposureSuppressed(_ hidden: Bool) {
        guard !closed, hidden != exposureIsSuppressed, !hidden || (isEnabled && !cancelling) else { return }
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
        guard !closed, isEnabled, !cancelling else { return }
        if result.options.editAfter, let editor = ScreenshotMarkupController(pngData: result.pngData) {
            let owner = UUID(); editorID = owner
            self.editor = editor
            entry.setBusy(true); updateSuspension()
            editor.onFinish = { [weak self] editedData in
                guard let self, !self.closed, self.editorID == owner else { return }
                self.editorID = nil; self.editor = nil
                self.entry.setBusy(false); self.updateSuspension()
                self.collect(result, editedData: editedData)
            }
            editor.present()
        } else {
            collect(result, editedData: nil)
            if result.options.editAfter {
                onIssue("这张截图已按原画质保留；当前轻量标注不支持它的颜色格式。")
            }
        }
        // Deliberately no setExpanded(false), cancel(), or mode/order mutation.
    }

    private func collect(_ result: InteractiveScreenshotCapture, editedData: Data?) {
        let importer = self.importer, directory = outputDirectory
        // A completed exposure owns a saved original. Its durable import may
        // finish after the feature is disabled; it never restarts capture or
        // changes a setting. Unfinished exposures are cancelled by the engine.
        Task { [weak self] in
            do {
                // Origin records who initiated the capture, not which encoder
                // happened to write an xattr. Built-in originals and derivatives
                // must never borrow the system-screenshot admission profile.
                _ = try await importer.importBuiltInScreenshot(original: result.sourceURL,
                    editedPNG: editedData, outputDirectory: directory)
                guard let self, !self.closed else { return }
                await self.onChange()
                self.configure()
            } catch {
                guard let self, !self.closed else { return }
                self.onIssue("截图原文件已保留，暂未加入裂缝。请检查可用存储空间后重试。")
            }
        }
    }

    func cancel() {
        guard !closed, !cancelling else { return }
        cancelling = true
        entry.setCapturePresentation(nil)
        capture.cancel()
        setExposureSuppressed(false)
        editor?.keepOriginalAndClose(); editor = nil
        editorID = nil
        menuOpen = false
        entry.setCaptureSuppressed(false); entry.setBusy(false)
        entry.setExpanded(false)
        rift.setCaptureSuppressed(false); rift.setCaptureSessionActive(false)
        cancelling = false
    }

    func close() {
        guard !closed else { return }
        cancel(); closed = true
        capture.setEnabled(false)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let windowCloseObserver { NotificationCenter.default.removeObserver(windowCloseObserver) }
        screenObserver = nil
        windowCloseObserver = nil
        rift.onGeometryChange = nil
        entry.onGeometryChange = nil
        entry.close()
    }
}
