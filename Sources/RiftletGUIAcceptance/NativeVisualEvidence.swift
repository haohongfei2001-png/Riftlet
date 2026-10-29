import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import CryptoKit
import ImageIO
import RiftletCore
import RiftletFeedback
import RiftletFeedbackUI
import RiftletUI
import UniformTypeIdentifiers

/// WindowServer produces immutable CGImages. This handoff contains only those
/// already captured self-owned pixels, never an NSWindow or a mutable UI object.
private struct NativePNGImages: @unchecked Sendable {
    let image: CGImage
    let background: CGImage?
}

private struct NativePNGResult: Sendable {
    let bytes: Int
    let sha256: String
    let productDifferencePixels: Int?
    let processedOnMainThread: Bool
}

/// A helper-only recorder. It captures only the WindowServer IDs of windows
/// owned by this process. It never captures a display, another process, an
/// existing screenshot, or a production data directory, and never asks for TCC.
/// Capturing a synthetic native projection is not real input/upload acceptance.
@MainActor
final class NativeVisualEvidence {
    enum Failure: String, Error, Sendable { case unsafeRequest, existingOutput, missingWindow, missingProductPixels, encoding }

    // Only these fixed values may leave the export catch. Underlying framework
    // errors can contain paths or other process details and are never printed.
    enum ExportStage: String, Sendable {
        case staticPreparation, supplementalPreparation, ownedWindowSelection, ownedWindowCapture
        case backdropCapture, pngProcessing, pngPixelComparison, pngDestination, pngFinalize, pngRead
        case timelinePreparation, timelineWait, movieFinish, manifestEncoding, manifestWrite
    }

    struct FailureDiagnostic: Sendable {
        let stage: ExportStage
        let failure: Failure?
        var failureCase: String { failure?.rawValue ?? "unclassified" }
    }

    private struct ExportFailure: Error {
        let diagnostic: FailureDiagnostic
    }

    static var requested: Bool { CommandLine.arguments.contains("--export-native-evidence") }

    /// Read the actual AppKit policy. This never writes system preferences or
    /// changes how product controllers honor accessibility settings.
    static func systemAccessibilitySnapshot() -> [String: Bool] {
        let workspace = NSWorkspace.shared
        return ["reduceMotion": workspace.accessibilityDisplayShouldReduceMotion,
                "increaseContrast": workspace.accessibilityDisplayShouldIncreaseContrast,
                "reduceTransparency": workspace.accessibilityDisplayShouldReduceTransparency]
    }

    private let directory: URL
    private let source: String
    private let checkout: String
    private let singleWindow: Bool
    private let accessibilityAtStart: [String: Bool]
    private weak var backdrop: NSWindow?
    private weak var supplementalRift: RiftPanelController?
    private weak var supplementalEntry: ScreenshotEntryController?
    private let supplementalCase: String?
    private var supplementalPrepared = false
    private var supplementalDirectory: URL?
    private var supplementalHistory: RiftHistoryController?
    private var supplementalFeedback: FeedbackWindowController?
    private var supplementalUnexpectedAction = false
    private var supplementalStage = "notStarted"
    private var exportStage: ExportStage = .staticPreparation
    private var frames: [[String: Any]] = []
    private var events: [[String: Any]] = []
    private var captureUnavailable = false
    private var movieReport: [String: Any]?
    private let start = ProcessInfo.processInfo.systemUptime

    private struct NativeFrame {
        let image: CGImage
        let rect: CGRect
        let quartzRect: CGRect
        let backingScale: CGFloat
        let windowCount: Int
        let windowNumbers: [Int]
        let started: TimeInterval
        let ended: TimeInterval
    }

    init(backdrop: NSWindow, rift: RiftPanelController? = nil, entry: ScreenshotEntryController? = nil) throws {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard args.contains("--visual-clean"),
              !args.contains(where: { $0.hasPrefix("--software-") || $0 == "--press-acceptance-asset" }),
              let path = value("--export-native-evidence"), path.hasPrefix("/"),
              let source = value("--evidence-source"), let checkout = value("--evidence-checkout"),
              [source, checkout].allSatisfy({ $0.count == 40 && $0.allSatisfy { "0123456789abcdef".contains($0) } }) else {
            throw Failure.unsafeRequest
        }
        let supplement = value("--visual-supplement")
        if args.contains("--visual-supplement") {
            let windows = ["history-preview-portrait": "history", "history-preview-wide": "history",
                "history-preview-missing": "history", "feedback-save-failure": "feedback"]
            guard args.filter({ $0 == "--visual-supplement" }).count == 1, let supplement,
                  windows[supplement] != nil || supplement == "queue-feedback" || supplement == "entry-countdown",
                  !args.contains("--visual-timeline"), !args.contains("--visual-reduced-motion"),
                  !args.contains("--visual-feedback-records"),
                  value("--visual-window") == windows[supplement],
                  supplement != "queue-feedback" || rift != nil,
                  supplement != "entry-countdown" || (entry != nil && args.contains("--visual-entry-expanded")) else {
                throw Failure.unsafeRequest
            }
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw Failure.unsafeRequest }
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw Failure.existingOutput }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        self.directory = directory; self.source = source; self.checkout = checkout
        self.singleWindow = args.contains("--visual-window")
        self.supplementalCase = supplement
        self.supplementalRift = rift; self.supplementalEntry = entry
        self.accessibilityAtStart = Self.systemAccessibilitySnapshot()
        self.backdrop = backdrop
    }

    func note(_ name: String, fields: [String: Any]) {
        let allowedNames: Set<String> = ["native_arrival_boundary", "native_presentation_boundary",
            "visual_synthetic_start_projection", "visual_synthetic_final_projection",
            "visual_timeline_started", "visual_timeline_finished", "synthetic_asset_ready",
            "synthetic_decoration_cancel", "native_evidence_preview_action", "native_evidence_history_selection",
            "native_evidence_feedback_records", "native_evidence_supplemental", "native_evidence_timeline_prepared"]
        guard allowedNames.contains(name), events.count < 64 else { return }
        let allowedFields: Set<String> = ["phase", "boundaryUptime", "duration", "mode", "reason",
            "readyUptime", "sourceProvided", "physical", "accepted", "fixtureState", "fixtureSequence", "softwareSelection",
            "fixtureRecordCount", "fixtureStates", "bodyAndStateMatched", "expanded", "networkEnabled", "receiptEvidence",
            "fixtureReadyBeforeExpansion", "fixturePreparationSeconds",
            "supplementalCase", "imageLoaded", "imageAbsent", "titleMatches", "failureVisible", "parentOrderedOut",
            "retryEnabled", "copyEnabled", "draftRetained", "savedDraftUnchanged", "recordsEmpty", "persistenceFault",
            "windowWidth", "windowHeight", "fixturePixelWidth", "fixturePixelHeight", "fixedSlotsUnchanged",
            "countdownVisible", "nextModeVisible", "captureExecuted", "noteVisible", "noteAvoidsInputs",
            "entrySettled", "entryExpansion", "entryFrameScheduled", "cancelSlotPosition", "cancelTargetSlot",
            "statusWindowVisible", "statusWindowNumber", "statusAvoidsInputs", "statusWindowAlpha", "statusContentAlpha", "statusLabelAlpha",
            "statusFrame", "statusContentBounds", "statusLabelFrame", "statusLabelScreenFrame", "captureRect", "inputFrames",
            "statusTextFits", "statusDisplayComplete", "displayCommitWaitSeconds",
            "previewDisplayComplete", "previewWindowNumber", "previewViewportPoints",
            "feedbackDisplayComplete", "feedbackFailureState", "feedbackWindowNumber", "feedbackContentBounds",
            "feedbackStatusFrame", "feedbackRecoveryFrames", "feedbackRecoveryAlignmentFrames",
            "feedbackEditorViewportFrame", "feedbackAlphas", "timelineOriginUptime", "timelinePreparationSeconds",
            "backdropWindowNumber", "rowWindowNumbers", "inputWindowNumbers", "ownWindowNumbersFrontToBack",
            "helperActive", "backdropOcclusionVisible", "rowOcclusionVisible", "initialDisplaySubmitted"]
        var event = fields.filter { allowedFields.contains($0.key) }
        event["event"] = name; event["uptime"] = ProcessInfo.processInfo.systemUptime
        events.append(event)
    }

    /// Produces original WindowServer pixels. No resampling, cacheDisplay,
    /// layer.render, synthetic frame painting, or screenshot permission change.
    @discardableResult
    func capture(_ name: String) async throws -> Bool {
        if let supplementalCase, !supplementalPrepared {
            supplementalPrepared = true
            exportStage = .supplementalPreparation
            try await prepareSupplementalScene(supplementalCase)
        }
        guard let frame = try captureOwnedWindows() else {
            recordUnavailableFrame(name)
            return false
        }
        try await writePNG(frame, name: name)
        return true
    }

    // This opt-in path supplements the unchanged full visual suite. Every file
    // fault below belongs to a new helper-owned directory, and every displayed
    // view is a real product controller. No production store, capture engine,
    // attachment adapter, pasteboard or network-capable transport is created.
    private func prepareSupplementalScene(_ name: String) async throws {
        supplementalStage = "prepare"
        if name == "queue-feedback" { try await prepareQueueFeedback(); return }
        if name == "entry-countdown" { try await prepareEntryCountdown(); return }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("riftlet-native-supplement-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        supplementalDirectory = root
        // Retain the ordinary fixture controllers. Closing a history parent
        // would close its preview; orderOut is presentation-only and preserves it.
        for window in NSApp.windows where window !== backdrop && window.styleMask.contains(.titled) {
            window.orderOut(nil)
        }
        if name == "feedback-save-failure" { try await prepareFeedbackFailure(root: root) }
        else { try await prepareHistoryPreview(name, root: root) }
    }

    private func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }

    private func waitForSupplement(_ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard predicate() else { throw Failure.missingWindow }
    }

    private func raiseSupplementalWindow(_ window: NSWindow) {
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func supplementalObservation(_ fields: [String: Any]) {
        var value = fields
        value["supplementalCase"] = supplementalCase
        value["softwareSelection"] = true; value["physical"] = false
        value["networkEnabled"] = false; value["receiptEvidence"] = false
        note("native_evidence_supplemental", fields: value)
        supplementalStage = "ready"
    }

    private func prepareHistoryPreview(_ name: String, root: URL) async throws {
        supplementalStage = "historyFixture"
        let media = root.appendingPathComponent("media", isDirectory: true)
        let fixtures = try SyntheticScene.makeMedia(in: media)
        let fixture = fixtures[name == "history-preview-wide" ? 4 : 3]
        guard fixture.image.origin == .synthetic else { throw Failure.unsafeRequest }
        if name == "history-preview-missing" {
            try FileManager.default.removeItem(at: media.appendingPathComponent(fixture.image.fileName))
        }
        let entry = RiftHistoryEntry(record: fixture)
        let controller = RiftHistoryController(mediaDirectory: media,
            onRestore: { [weak self] _ in self?.supplementalUnexpectedAction = true },
            onRemove: { [weak self] _ in self?.supplementalUnexpectedAction = true },
            onReveal: { [weak self] _ in self?.supplementalUnexpectedAction = true })
        supplementalHistory = controller
        controller.update(entries: [entry]); controller.show()
        guard let table = NSApp.windows.compactMap(\.contentView).flatMap(descendants)
            .compactMap({ $0 as? NSTableView }).first(where: { $0.delegate === controller }),
              table.numberOfRows == 1, let historyWindow = table.window, let action = table.doubleAction else {
            throw Failure.missingWindow
        }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        guard NSApp.sendAction(action, to: table.target, from: table),
              let preview = NSApp.windows.first(where: {
                  $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible
              }), let content = preview.contentView,
              let image = descendants(content).first(where: { $0.identifier?.rawValue == "history.preview.image" }) as? NSImageView,
              let status = descendants(content).first(where: { $0.identifier?.rawValue == "history.preview.status" }) as? NSTextField else {
            throw Failure.missingWindow
        }
        historyWindow.orderOut(nil)
        if name == "history-preview-missing" {
            preview.setFrame(NSRect(origin: preview.frame.origin, size: NSSize(width: 360, height: 280)), display: true)
        }
        raiseSupplementalWindow(preview)
        supplementalStage = "historyDecode"
        let missing = name == "history-preview-missing"
        try await waitForSupplement {
            missing ? status.stringValue == "无法加载清晰预览，图片记录仍保留"
                : image.image != nil && status.stringValue == "已按窗口显示"
        }
        supplementalStage = "historyDisplay"
        // A decoder completion can set NSImage and footer text before either is
        // drawn. Export only after normal AppKit display and a run-loop commit.
        content.layoutSubtreeIfNeeded()
        preview.displayIfNeeded()
        let commitStart = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(nanoseconds: 50_000_000)
        try await waitForSupplement {
            let outcome = missing ? image.image == nil && status.stringValue == "无法加载清晰预览，图片记录仍保留"
                : image.image != nil && status.stringValue == "已按窗口显示"
            return outcome && preview.isVisible && preview.alphaValue >= 0.99
                && [content, image, status].allSatisfy {
                    $0.window === preview && !$0.isHiddenOrHasHiddenAncestor && $0.alphaValue >= 0.99
                        && self.usableRect($0.bounds) && !$0.needsLayout && !$0.needsDisplay
                }
        }
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .medium
        let titleMatches = preview.title.contains(formatter.string(from: HistoryPresentation.captureDate(for: entry)))
            && preview.title.hasSuffix(String(fixture.id.uuidString.prefix(8)))
        guard titleMatches, !historyWindow.isVisible, !supplementalUnexpectedAction,
              missing ? image.image == nil : image.image != nil else { throw Failure.missingWindow }
        if missing {
            guard preview.frame.size == NSSize(width: 360, height: 280) else { throw Failure.missingWindow }
        } else if let display = image.image?.size {
            guard abs(display.width / display.height - CGFloat(fixture.image.pixelWidth) / CGFloat(fixture.image.pixelHeight)) < 0.001 else {
                throw Failure.missingWindow
            }
        }
        supplementalObservation(["fixtureSequence": fixture.sequence, "fixturePixelWidth": fixture.image.pixelWidth,
            "fixturePixelHeight": fixture.image.pixelHeight, "imageLoaded": image.image != nil, "imageAbsent": image.image == nil,
            "titleMatches": titleMatches, "failureVisible": missing, "parentOrderedOut": !historyWindow.isVisible,
            "windowWidth": preview.frame.width, "windowHeight": preview.frame.height,
            "previewDisplayComplete": true, "previewWindowNumber": preview.windowNumber,
            "previewViewportPoints": [image.bounds.width, image.bounds.height],
            "displayCommitWaitSeconds": ProcessInfo.processInfo.systemUptime - commitStart])
    }

    private func prepareFeedbackFailure(root: URL) async throws {
        supplementalStage = "feedbackFixture"
        let sidecar = root.appendingPathComponent("feedback", isDirectory: true)
        let store = try FeedbackStore(directory: sidecar)
        let initial = FeedbackDraft(text: "合成本机草稿：此处不连接云端。", revision: 1)
        try await store.saveDraft(initial)
        let engine = FeedbackEngine(store: store, secrets: MemoryFeedbackSecrets(), transport: DisabledFeedbackTransport())
        let controller = FeedbackWindowController(engine: engine, diagnostics: FeedbackDiagnostics(), appVersion: "0.1.0", demo: true)
        supplementalFeedback = controller
        controller.show()
        guard let window = controller.window, let content = window.contentView,
              let editor = descendants(content).compactMap({ $0 as? NSTextView }).first,
              let close = descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == "保存并关闭" }),
              let retry = descendants(content).first(where: { $0.identifier?.rawValue == "feedback.retrySave" }) as? NSButton,
              let copy = descendants(content).first(where: { $0.identifier?.rawValue == "feedback.copyText" }) as? NSButton else {
            throw Failure.missingWindow
        }
        try await waitForSupplement { controller.currentText == initial.text && editor.isEditable }
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 560, height: 500)), display: true)
        raiseSupplementalWindow(window)
        // DELETE-mode SQLite must create this journal for the next write. An
        // existing directory at that exact fresh fixture path causes a real I/O
        // failure; the controller's normal persistDraft closure is untouched.
        let journal = sidecar.appendingPathComponent("feedback.sqlite-journal", isDirectory: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: false)
        let body = "合成保存失败验收：正文仍保留在这里。\n可以重试保存并关闭，或先复制正文；此操作不会发送反馈。"
        editor.string = body
        controller.textDidChange(Notification(name: NSText.didChangeNotification))
        supplementalStage = "feedbackPersistenceFailure"
        close.performClick(nil)
        let failureText = "未能可靠保存草稿；文字仍在此窗口。可重试保存或复制正文，没有发送。"
        var failureStatus: NSTextField?
        try await waitForSupplement {
            failureStatus = self.descendants(content).compactMap { $0 as? NSTextField }.first { $0.stringValue == failureText }
            return window.isVisible && failureStatus != nil
                && retry.title == "重试保存并关闭" && retry.isEnabled && copy.isEnabled
                && !retry.isHiddenOrHasHiddenAncestor && !copy.isHiddenOrHasHiddenAncestor
        }
        guard let failureStatus, let viewport = editor.enclosingScrollView?.contentView else { throw Failure.missingWindow }
        // Removing only our deliberate obstruction does not retry or close the
        // window. The failure presentation remains until an explicit action.
        try FileManager.default.removeItem(at: journal)
        let saved = try await store.draft(), records = try await store.records()
        guard saved == initial, records.isEmpty, controller.currentText == body, editor.isEditable,
              window.frame.size == NSSize(width: 560, height: 500), !engine.configured else { throw Failure.unsafeRequest }
        await engine.stop()
        supplementalStage = "feedbackFailureDisplay"
        // Enabled recovery buttons can precede their first WindowServer draw.
        // Commit the actual failure footer, then recheck its text and visible
        // controls without retrying, copying, scrolling or changing geometry.
        content.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let commitStart = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(nanoseconds: 50_000_000)
        let views: [NSView] = [content, failureStatus, retry, copy, viewport]
        let footerAndViewport: [NSView] = [failureStatus, retry, copy, viewport]
        try await waitForSupplement {
            window.isVisible && window.alphaValue >= 0.99 && failureStatus.stringValue == failureText
                && retry.title == "重试保存并关闭" && retry.isEnabled && copy.isEnabled
                && controller.currentText == body && editor.isEditable
                && views.allSatisfy {
                    $0.window === window && !$0.isHiddenOrHasHiddenAncestor && $0.alphaValue >= 0.99
                        && self.usableRect($0.bounds) && $0.visibleRect.contains($0.bounds)
                        && !$0.needsLayout && !$0.needsDisplay
                }
                && footerAndViewport.allSatisfy { content.bounds.contains($0.convert($0.bounds, to: content)) }
        }
        // AppKit lays out button content using alignment rectangles; full view
        // frames also contain bezel/shadow outsets. Retain both measurements.
        let recoveryAlignmentFrames = try [retry, copy].map { button -> CGRect in
            guard let parent = button.superview else { throw Failure.missingWindow }
            let alignment = parent.convert(button.alignmentRect(forFrame: button.frame), to: content)
            let fullBounds = button.convert(button.bounds, to: content)
            guard usableRect(alignment), fullBounds.contains(alignment) else { throw Failure.unsafeRequest }
            return alignment
        }
        supplementalObservation(["retryEnabled": retry.isEnabled, "copyEnabled": copy.isEnabled,
            "draftRetained": controller.currentText == body, "savedDraftUnchanged": saved == initial,
            "recordsEmpty": records.isEmpty, "persistenceFault": "ownedSQLiteJournalPathCollision",
            "windowWidth": window.frame.width, "windowHeight": window.frame.height,
            "failureVisible": true, "feedbackFailureState": "draftSaveFailed", "feedbackDisplayComplete": true,
            "feedbackWindowNumber": window.windowNumber, "feedbackContentBounds": rectValues(content.bounds),
            "feedbackStatusFrame": rectValues(failureStatus.convert(failureStatus.bounds, to: content)),
            "feedbackRecoveryFrames": [retry, copy].map { rectValues($0.convert($0.bounds, to: content)) },
            "feedbackRecoveryAlignmentFrames": recoveryAlignmentFrames.map(rectValues),
            "feedbackEditorViewportFrame": rectValues(viewport.convert(viewport.bounds, to: content)),
            "feedbackAlphas": [window.alphaValue] + views.map(\.alphaValue),
            "displayCommitWaitSeconds": ProcessInfo.processInfo.systemUptime - commitStart])
    }

    private func prepareQueueFeedback() async throws {
        supplementalStage = "queueFeedback"
        guard let rift = supplementalRift, let row = rift.diagnosticSnapshot.rows.first else { throw Failure.missingWindow }
        let reason = "请先打开可用的 ChatGPT 草稿，再点击这张图片。"
        rift.setFeedback(reason, for: row.assetID, owner: .selection(UUID()), visibilityRevision: 0, timing: .immediate)
        var noteWindow: NSWindow?
        try await waitForSupplement {
            noteWindow = NSApp.windows.first { window in
                window.isVisible && window.contentView.map(self.descendants)?.contains(where: {
                    ($0 as? NSTextField)?.stringValue == reason && !$0.isHiddenOrHasHiddenAncestor
                }) == true
            }
            return noteWindow != nil
        }
        guard let noteWindow else { throw Failure.missingWindow }
        let avoids = rift.diagnosticSnapshot.rows.allSatisfy {
            !noteWindow.frame.intersects($0.imageInputFrame) && !noteWindow.frame.intersects($0.numberInputFrame)
        }
        guard avoids, noteWindow.ignoresMouseEvents, !noteWindow.canBecomeKey else { throw Failure.unsafeRequest }
        supplementalObservation(["noteVisible": true, "noteAvoidsInputs": avoids, "captureExecuted": false])
    }

    private struct EntryCountdownReadiness {
        let snapshot: ScreenshotEntryDiagnosticSnapshot
        let window: NSWindow
        let content: NSView
        let label: NSTextField
        let labelFrame: CGRect
        let labelScreenFrame: CGRect
        let captureRect: CGRect
        let inputFrames: [CGRect]
        let cancelTargetSlot: Int
    }

    private func usableRect(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }

    private func rectValues(_ rect: CGRect) -> [CGFloat] { [rect.minX, rect.minY, rect.width, rect.height] }

    private func entryCountdownReadiness(_ entry: ScreenshotEntryController,
                                         fixedControls: [ScreenshotEntryControlSnapshot]) -> EntryCountdownReadiness? {
        let snapshot = entry.diagnosticSnapshot
        let cancelControls = snapshot.controls.filter(\.isCancel)
        // The physical slots stay fixed through the mode switch. Only the X's
        // role and its existing 100 ms movement change; neither is forced here.
        guard snapshot.isExpanded, snapshot.mode == .fullScreen, !snapshot.isHidden, !snapshot.isCaptureSuppressed,
              snapshot.expansion == 1, !snapshot.hasScheduledFrame,
              snapshot.controls.count == ScreenshotEntrySlot.allCases.count,
              fixedControls.count == snapshot.controls.count,
              zip(fixedControls, snapshot.controls).allSatisfy({ pair in
                  pair.0.slot == pair.1.slot && pair.0.mode == pair.1.mode
                      && pair.0.frame == pair.1.frame && pair.0.windowNumber == pair.1.windowNumber
              }), cancelControls.count == 1, let cancel = cancelControls.first, cancel.mode == .fullScreen,
              snapshot.cancelSlotPosition == CGFloat(cancel.slot.rawValue),
              let window = NSApp.windows.first(where: { $0.windowNumber == snapshot.captureStatusWindowNumber }),
              window.isVisible, window.alphaValue >= 0.99, window.ignoresMouseEvents, !window.canBecomeKey,
              window.frame == snapshot.captureStatusFrame, usableRect(window.frame),
              let content = window.contentView, content.window === window,
              !content.isHiddenOrHasHiddenAncestor, content.alphaValue >= 0.99, usableRect(content.bounds),
              let backdrop, let rift = supplementalRift,
              usableRect(backdrop.frame), backdrop.frame.contains(window.frame) else { return nil }
        let expected = "已选区域 · 3 秒后拍摄\n下一张：全屏"
        let labels = descendants(content).compactMap { $0 as? NSTextField }.filter { $0.stringValue == expected }
        guard snapshot.captureStatusText == expected, labels.count == 1, let label = labels.first,
              label.window === window, label.superview === content,
              !label.isHiddenOrHasHiddenAncestor, label.alphaValue >= 0.99,
              usableRect(label.bounds), usableRect(label.frame) else { return nil }
        let labelFrame = label.convert(label.bounds, to: content)
        let labelScreenFrame = window.convertToScreen(label.convert(label.bounds, to: nil))
        let measured = label.attributedStringValue.boundingRect(with: CGSize(width: label.bounds.width, height: 120),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let inputFrames = snapshot.controls.map(\.frame) + rift.diagnosticSnapshot.rows.flatMap {
            [$0.imageInputFrame, $0.numberInputFrame]
        }
        guard usableRect(labelFrame), usableRect(labelScreenFrame), usableRect(measured),
              content.bounds.contains(labelFrame), window.frame.contains(labelScreenFrame),
              measured.width <= label.bounds.width + 0.5, measured.height <= label.bounds.height + 0.5,
              inputFrames.allSatisfy({ usableRect($0) && !window.frame.intersects($0) }) else { return nil }
        return EntryCountdownReadiness(snapshot: snapshot, window: window, content: content, label: label,
            labelFrame: labelFrame, labelScreenFrame: labelScreenFrame, captureRect: backdrop.frame,
            inputFrames: inputFrames, cancelTargetSlot: cancel.slot.rawValue)
    }

    private func prepareEntryCountdown() async throws {
        supplementalStage = "entryCountdownSettling"
        guard let entry = supplementalEntry, entry.diagnosticSnapshot.isExpanded else { throw Failure.missingWindow }
        let before = entry.diagnosticSnapshot.controls
        entry.setMode(.fullScreen)
        entry.setCapturePresentation(.init(sessionID: UUID(), requestID: UUID(), confirmedMode: .region,
            nextMode: .fullScreen, state: .countdown(3)))
        var ready: EntryCountdownReadiness?
        try await waitForSupplement {
            ready = self.entryCountdownReadiness(entry, fixedControls: before)
            return ready != nil
        }
        guard let settled = ready else { throw Failure.missingWindow }
        supplementalStage = "entryCountdownDisplay"
        // Showing a window and setting its string are not evidence of a drawn
        // label. Let the real AppKit display work and run-loop transaction finish
        // after the product's own timers have stopped, then re-read all facts.
        settled.content.layoutSubtreeIfNeeded()
        settled.window.displayIfNeeded()
        NSApp.windows.first(where: { $0.windowNumber == settled.snapshot.visualWindowNumber })?.displayIfNeeded()
        let commitStart = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(nanoseconds: 50_000_000)
        try await waitForSupplement {
            ready = self.entryCountdownReadiness(entry, fixedControls: before)
            return ready.map { !$0.content.needsLayout && !$0.content.needsDisplay && !$0.label.needsDisplay } == true
        }
        guard let ready else { throw Failure.missingWindow }
        supplementalObservation(["fixedSlotsUnchanged": true, "countdownVisible": true, "nextModeVisible": true,
            "captureExecuted": false, "mode": "fullScreen", "entrySettled": true, "entryExpansion": ready.snapshot.expansion,
            "entryFrameScheduled": ready.snapshot.hasScheduledFrame, "cancelSlotPosition": ready.snapshot.cancelSlotPosition,
            "cancelTargetSlot": ready.cancelTargetSlot, "statusWindowVisible": ready.window.isVisible,
            "statusWindowNumber": ready.window.windowNumber,
            "statusWindowAlpha": ready.window.alphaValue, "statusContentAlpha": ready.content.alphaValue,
            "statusLabelAlpha": ready.label.alphaValue, "statusAvoidsInputs": true, "statusTextFits": true,
            "statusFrame": rectValues(ready.window.frame), "statusContentBounds": rectValues(ready.content.bounds),
            "statusLabelFrame": rectValues(ready.labelFrame), "statusLabelScreenFrame": rectValues(ready.labelScreenFrame),
            "captureRect": rectValues(ready.captureRect), "inputFrames": ready.inputFrames.map(rectValues),
            "statusDisplayComplete": true, "displayCommitWaitSeconds": ProcessInfo.processInfo.systemUptime - commitStart])
    }

    private func captureOwnedWindows() throws -> NativeFrame? {
        exportStage = .ownedWindowSelection
        guard let backdrop else { throw Failure.missingWindow }
        // orderedWindows is an AppleScript collection that excludes NSPanel.
        // Start with every visible self-owned window, then ask AppKit for its
        // real onscreen order. No other process's metadata or pixels are read.
        let allowed = Set(NSApp.windows.filter { $0.isVisible && $0.windowNumber > 0 }.map(\.windowNumber))
        var owned: [NSWindow] = []
        NSApp.enumerateWindows(options: .orderedFrontToBack) { window, _ in
            if allowed.contains(window.windowNumber) { owned.append(window) }
        }
        guard owned.count == allowed.count, Set(owned.map(\.windowNumber)) == allowed else { throw Failure.missingWindow }
        let selected = singleWindow ? owned.filter { $0 !== backdrop && $0.styleMask.contains(.titled) } : owned
        guard !selected.isEmpty, !singleWindow || selected.count == 1,
              singleWindow || (selected.contains(where: { $0 === backdrop }) && selected.count > 1) else { throw Failure.missingWindow }
        let appKitRect = singleWindow ? selected[0].frame : backdrop.frame
        guard appKitRect.width > 0, appKitRect.height > 0,
              let firstScreen = NSScreen.screens.first else { throw Failure.missingWindow }
        let windowIDs = try windowArray(selected)
        let quartzRect = CGRect(x: appKitRect.minX, y: firstScreen.frame.maxY - appKitRect.maxY,
                                width: appKitRect.width, height: appKitRect.height)
        exportStage = .ownedWindowCapture
        let before = ProcessInfo.processInfo.systemUptime
        guard let image = CGImage(windowListFromArrayScreenBounds: quartzRect, windowArray: windowIDs,
                    imageOption: [.boundsIgnoreFraming, .bestResolution]), image.width > 0, image.height > 0 else {
            captureUnavailable = true
            return nil
        }
        return NativeFrame(image: image, rect: appKitRect, quartzRect: quartzRect,
            backingScale: (singleWindow ? selected[0] : backdrop).backingScaleFactor,
            windowCount: selected.count, windowNumbers: selected.map(\.windowNumber),
            started: before, ended: ProcessInfo.processInfo.systemUptime)
    }

    private func windowArray(_ windows: [NSWindow]) throws -> CFArray {
        guard let windowIDs = CFArrayCreateMutable(kCFAllocatorDefault, 0, nil) else { throw Failure.missingWindow }
        // Quartz expects scalar CGWindowID values in a CFArray with nil
        // callbacks, not CFNumber objects. These encoded values are never
        // dereferenced; every ID comes from this process's selected NSWindow.
        for window in windows {
            guard let windowID = CGWindowID(exactly: window.windowNumber),
                  windowID != kCGNullWindowID,
                  let scalar = UnsafeRawPointer(bitPattern: UInt(windowID)) else { throw Failure.missingWindow }
            CFArrayAppendValue(windowIDs, scalar)
        }
        return windowIDs
    }

    private func captureBackdrop(for frame: NativeFrame) throws -> CGImage {
        guard let backdrop,
              let background = CGImage(windowListFromArrayScreenBounds: frame.quartzRect,
                windowArray: try windowArray([backdrop]), imageOption: [.boundsIgnoreFraming, .bestResolution]) else {
            throw Failure.encoding
        }
        return background
    }

    nonisolated private static func productDifferencePixels(_ image: CGImage, background: CGImage) throws -> Int {
        guard background.width == image.width, background.height == image.height,
              background.bitsPerPixel == 32, image.bitsPerPixel == 32,
              background.bitsPerComponent == 8, image.bitsPerComponent == 8,
              background.bitmapInfo == image.bitmapInfo,
              let actualData = image.dataProvider?.data, let backgroundData = background.dataProvider?.data,
              CFDataGetLength(actualData) >= image.bytesPerRow * image.height,
              CFDataGetLength(backgroundData) >= background.bytesPerRow * background.height,
              let actual = CFDataGetBytePtr(actualData), let baseline = CFDataGetBytePtr(backgroundData) else {
            throw Failure.encoding
        }
        var difference = 0
        // Compare original pixels, without resizing or modifying either image.
        // A little capture dithering cannot turn an empty backdrop into a pass.
        for y in 0..<image.height {
            for x in 0..<image.width {
                let a = y * image.bytesPerRow + x * 4
                let b = y * background.bytesPerRow + x * 4
                if (0..<4).contains(where: { abs(Int(actual[a + $0]) - Int(baseline[b + $0])) > 8 }) {
                    difference += 1
                }
            }
        }
        guard difference >= 64 else { throw Failure.missingProductPixels }
        return difference
    }

    private func recordUnavailableFrame(_ name: String) {
        frames.append(["name": name, "status": "NOT_RUN", "reason": "ownWindowServerCaptureUnavailable",
                       "uptime": ProcessInfo.processInfo.systemUptime, "physicalInput": "NOT_RUN"])
    }

    nonisolated private static func exportStep<T>(_ stage: ExportStage, _ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch is CancellationError { throw CancellationError() }
        catch let failure as ExportFailure { throw failure }
        catch { throw ExportFailure(diagnostic: FailureDiagnostic(stage: stage, failure: error as? Failure)) }
    }

    func failureDiagnostic(for error: Error) -> FailureDiagnostic {
        (error as? ExportFailure)?.diagnostic ?? FailureDiagnostic(stage: exportStage, failure: error as? Failure)
    }

    nonisolated private static func encodePNG(_ images: NativePNGImages, file: URL) throws -> NativePNGResult {
        let onMainThread = Thread.isMainThread
        guard !onMainThread else { throw Failure.unsafeRequest }
        let difference = try exportStep(.pngPixelComparison) {
            try images.background.map { try productDifferencePixels(images.image, background: $0) }
        }
        let target = try exportStep(.pngDestination) {
            guard !FileManager.default.fileExists(atPath: file.path),
                  let target = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw Failure.encoding
            }
            return target
        }
        try exportStep(.pngFinalize) {
            CGImageDestinationAddImage(target, images.image, nil)
            guard CGImageDestinationFinalize(target) else { throw Failure.encoding }
        }
        let bytes = try exportStep(.pngRead) { try Data(contentsOf: file) }
        return NativePNGResult(bytes: bytes.count,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            productDifferencePixels: difference, processedOnMainThread: onMainThread)
    }

    private func writePNG(_ frame: NativeFrame, name: String) async throws {
        let image = frame.image
        let background: CGImage?
        exportStage = .backdropCapture
        if singleWindow { background = nil } else { background = try captureBackdrop(for: frame) }
        let images = NativePNGImages(image: image, background: background)
        let file = directory.appendingPathComponent(name + ".png")
        // Await exactly one background job before capturing the next frame.
        // Heavy original-pixel comparison/PNG encoding/hash work must not block
        // AppKit's run loop or compete with Core Animation completion delivery.
        exportStage = .pngProcessing
        let encoded = try await Task.detached(priority: .utility) {
            try Self.encodePNG(images, file: file)
        }.value
        try Task.checkCancellation()
        var result: [String: Any] = [
            "name": name, "file": file.lastPathComponent, "status": "CAPTURED_NATIVE_WINDOWSERVER",
            "method": "CGImage(windowListFromArrayScreenBounds:windowArray:imageOption:); only NSApp-owned windows",
            "captureStartedUptime": frame.started, "captureEndedUptime": frame.ended,
            "elapsedSeconds": frame.started - start, "pixels": [image.width, image.height],
            "points": [frame.rect.width, frame.rect.height],
            "pixelScaleX": CGFloat(image.width) / frame.rect.width,
            "pixelScaleY": CGFloat(image.height) / frame.rect.height,
            "backingScaleFactor": frame.backingScale,
            "resized": false, "source": source, "checkout": checkout,
            "bytes": encoded.bytes, "sha256": encoded.sha256,
            "pngProcessingOnMainThread": encoded.processedOnMainThread,
            "pngProcessing": "One awaited background task; immutable original self-window image pair",
            "selectedOwnWindowCount": frame.windowCount,
            "ownWindowNumbersFrontToBack": frame.windowNumbers,
            "windowOrdering": "NSApplication.enumerateWindows(orderedFrontToBack)",
            "productWindowCount": frame.windowCount - (singleWindow ? 0 : 1),
            "syntheticOnly": true, "receiptEvidence": false, "physicalInput": "NOT_RUN"
        ]
        if let difference = encoded.productDifferencePixels {
            result["productDifferencePixelCount"] = difference
            result["minimumProductDifferencePixels"] = 64
            result["productPixelComparison"] = "original own-window composite versus original opaque own backdrop; channel delta > 8"
        }
        frames.append(result)
    }

    private func timelineWindowReadiness() -> (windows: [NSWindow], rows: [RiftDiagnosticRow], order: [Int])? {
        guard NSApp.isActive, let backdrop, let rift = supplementalRift,
              backdrop.occlusionState.contains(.visible) else { return nil }
        let snapshot = rift.diagnosticSnapshot
        guard !snapshot.rows.isEmpty, !snapshot.isHolding, !snapshot.isTransitioning else { return nil }
        let rowIDs = snapshot.rows.map(\.windowNumber)
        let inputIDs = snapshot.rows.flatMap { [$0.imageInputWindowNumber, $0.numberInputWindowNumber] }
        let expected = [backdrop.windowNumber] + rowIDs + inputIDs
        guard expected.allSatisfy({ $0 > 0 }), Set(expected).count == expected.count else { return nil }
        let own = NSApp.windows.filter { $0.isVisible && $0.windowNumber > 0 }
        let windows = expected.compactMap { id in own.first(where: { $0.windowNumber == id }) }
        guard windows.count == expected.count, windows.allSatisfy({ window in
            guard window.isOnActiveSpace, !window.isMiniaturized, window.alphaValue >= 0.99,
                  usableRect(window.frame), let content = window.contentView else { return false }
            return content.window === window && !content.isHiddenOrHasHiddenAncestor
                && content.alphaValue >= 0.99 && usableRect(content.bounds)
        }), rowIDs.allSatisfy({ id in
            windows.first(where: { $0.windowNumber == id })?.occlusionState.contains(.visible) == true
        }) else { return nil }
        // Query this application's windows only. Transparent input islands must
        // be ordered correctly, but their occlusion state is not pixel evidence.
        let allowed = Set(own.map(\.windowNumber))
        var order: [Int] = []
        NSApp.enumerateWindows(options: .orderedFrontToBack) { window, _ in
            if allowed.contains(window.windowNumber) { order.append(window.windowNumber) }
        }
        guard order.count == allowed.count, Set(order) == allowed,
              let backgroundIndex = order.firstIndex(of: backdrop.windowNumber),
              (rowIDs + inputIDs).allSatisfy({ id in
                  guard let index = order.firstIndex(of: id) else { return false }
                  return index < backgroundIndex
              }) else { return nil }
        return (windows, snapshot.rows, order)
    }

    /// Preparation observes only the helper's initial native state. No frame is
    /// captured, discarded or retried here; the original pixel gate runs later.
    func prepareTimeline(orderBackdrop: () -> Void) async throws -> TimeInterval {
        exportStage = .timelinePreparation
        guard !singleWindow, supplementalCase == nil, frames.isEmpty, movieReport == nil,
              CommandLine.arguments.contains("--visual-timeline") else { throw Failure.unsafeRequest }
        let began = ProcessInfo.processInfo.systemUptime
        let deadline = began + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            if NSApp.isActive { orderBackdrop() }
            if let before = timelineWindowReadiness() {
                let framesBefore = before.windows.map(\.frame)
                for window in before.windows {
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                }
                let submitted = ProcessInfo.processInfo.systemUptime
                guard submitted + 0.05 < deadline else { break }
                // Yield to the normal AppKit display transaction, then re-read
                // native identities, geometry, ordering and visibility together.
                try await Task.sleep(nanoseconds: 50_000_000)
                if ProcessInfo.processInfo.systemUptime < deadline,
                   let after = timelineWindowReadiness(), after.rows == before.rows,
                   after.order == before.order, after.windows.map(\.frame) == framesBefore,
                   after.windows.allSatisfy({ window in
                       guard let content = window.contentView else { return false }
                       return !content.needsLayout && !content.needsDisplay
                   }), let backdrop {
                    let origin = ProcessInfo.processInfo.systemUptime
                    note("native_evidence_timeline_prepared", fields: [
                        "timelineOriginUptime": origin, "timelinePreparationSeconds": origin - began,
                        "displayCommitWaitSeconds": origin - submitted, "initialDisplaySubmitted": true,
                        "helperActive": NSApp.isActive, "backdropWindowNumber": backdrop.windowNumber,
                        "backdropOcclusionVisible": backdrop.occlusionState.contains(.visible),
                        "rowWindowNumbers": after.rows.map(\.windowNumber),
                        "inputWindowNumbers": after.rows.flatMap { [$0.imageInputWindowNumber, $0.numberInputWindowNumber] },
                        "rowOcclusionVisible": true, "ownWindowNumbersFrontToBack": after.order,
                        "receiptEvidence": false])
                    return origin
                }
            }
            let remaining = min(0.02, deadline - ProcessInfo.processInfo.systemUptime)
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        }
        throw Failure.missingWindow
    }

    func recordTimeline(origin zero: TimeInterval) async throws {
        // Real captured frames at measured times. Capture/PNG overhead is part
        // of this observation and is not a frame-rate or latency benchmark.
        let hasArrival = CommandLine.arguments.contains("--visual-magnet")
            || CommandLine.arguments.contains("--visual-missing-source")
        let swallow: Double = hasArrival ? 4.5 : 3.5
        let times = [0.7, 1.9, 2.04, 2.14, 2.24, 2.34, 2.46, 2.60, 2.85]
            + [swallow - 0.04, swallow + 0.03, swallow + 0.07, swallow + 0.12,
               swallow + 0.22, swallow + 0.45, swallow + 1.82]
        let deadline = zero + min(6.45, (times.last ?? 6.2) + 0.12)
        var nextCapture = zero
        var keyframe = 0
        var captureCount = 0
        var recorder: NativeMovieRecorder?
        // One current CGImage plus a maximum of three pooled encoder buffers.
        // A late deadline is skipped, never filled with an interpolated frame.
        while ProcessInfo.processInfo.systemUptime < deadline && captureCount < 200 {
            exportStage = .timelineWait
            let remaining = nextCapture - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            try Task.checkCancellation()
            if ProcessInfo.processInfo.systemUptime >= deadline { break }
            guard let native = try captureOwnedWindows() else {
                recordUnavailableFrame("timeline")
                break
            }
            captureCount += 1
            if recorder == nil && movieReport == nil {
                do {
                    recorder = try NativeMovieRecorder(directory: directory, first: native.image,
                        firstCaptureUptime: native.started)
                } catch {
                    movieReport = ["status": "NOT_RUN", "reason": "nativeMovieEncoderUnavailable"]
                }
            }
            recorder?.append(native.image, captureUptime: native.started)
            let elapsed = native.started - zero
            if keyframe < times.count && elapsed >= times[keyframe] {
                // Do not duplicate one late capture under multiple timestamps.
                while keyframe + 1 < times.count && elapsed >= times[keyframe + 1] { keyframe += 1 }
                try await writePNG(native, name: String(format: "frame-%02d", keyframe))
                keyframe += 1
            }
            let after = ProcessInfo.processInfo.systemUptime - zero
            nextCapture = zero + (floor(after * 30) + 1) / 30
        }
        if let recorder {
            exportStage = .movieFinish
            movieReport = await recorder.finish()
            if captureUnavailable {
                movieReport = ["status": "NOT_RUN", "reason": "nativeCaptureIntervalIncomplete",
                               "encodedFrameCount": movieReport?["encodedFrameCount"] ?? 0]
            }
            movieReport?["nativeCaptureCount"] = captureCount
            movieReport?["completeCaptureInterval"] = !captureUnavailable
            movieReport?["source"] = source; movieReport?["checkout"] = checkout
        } else if movieReport == nil {
            movieReport = ["status": "NOT_RUN", "reason": "ownWindowServerCaptureUnavailable"]
        }
        try finish()
    }

    func finish(failure: FailureDiagnostic? = nil) throws {
        defer {
            supplementalHistory?.close(); supplementalHistory = nil
            supplementalFeedback?.window?.close(); supplementalFeedback = nil
            if let root = supplementalDirectory { try? FileManager.default.removeItem(at: root) }
            supplementalDirectory = nil
        }
        var report: [String: Any] = [
            "schemaVersion": 1, "status": failure != nil ? "FAIL" : (captureUnavailable ? "NOT_RUN" : "CAPTURED_NATIVE_WINDOWSERVER"),
            "source": source, "checkout": checkout,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "appearance": NSApp.effectiveAppearance.name.rawValue,
            "captureKind": singleWindow ? "single-product-window" : "owned-product-composite",
            "systemAccessibilityAtStart": accessibilityAtStart,
            "systemAccessibilityAtEnd": Self.systemAccessibilitySnapshot(),
            "helperReducedMotionOverride": CommandLine.arguments.contains("--visual-reduced-motion"),
            "syntheticOnly": true, "fixtureLayerIsolation": true,
            "otherApplicationPixelsCaptured": false, "screenCapturePermissionRequested": false,
            "physicalInput": "NOT_RUN", "realScreenshot": "NOT_RUN", "realUpload": "NOT_RUN",
            "crossApplicationFocus": "NOT_RUN", "productionWindowOrder": "NOT_RUN",
            "performanceBenchmark": false, "frameTiming": "Measured capture timestamps; variable cadence; capture overhead included",
            "visualVerdict": "REQUIRES_INDEPENDENT_REVIEW", "frames": frames, "events": events
        ]
        if let movieReport { report["movie"] = movieReport }
        if let supplementalCase { report["supplementalCase"] = supplementalCase; report["supplementalStage"] = supplementalStage }
        if let failure {
            report["failure"] = "nativeEvidenceExportFailed"
            report["failureCase"] = failure.failureCase
            report["failureStage"] = failure.stage.rawValue
        }
        exportStage = .manifestEncoding
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        exportStage = .manifestWrite
        try data.write(to: directory.appendingPathComponent("capture.json"), options: .atomic)
    }
}

/// A real-time, bounded native-frame encoder. Presentation timestamps come
/// from actual WindowServer capture calls; missed or backpressured frames are
/// omitted. This records observation overhead, not physical/performance proof.
@MainActor
private final class NativeMovieRecorder {
    enum Failure: Error { case unsupportedEncoder }
    private let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let width: Int
    private let height: Int
    private let contentWidth: Int
    private let contentHeight: Int
    private let origin: TimeInterval
    private var times: [Double] = []
    private var dropped = 0
    private var failure: String?

    init(directory: URL, first: CGImage, firstCaptureUptime: TimeInterval) throws {
        contentWidth = first.width; contentHeight = first.height
        // H.264 encoders require even dimensions. At most one black edge pixel
        // is added; the original image is drawn 1:1 and never resized/cropped.
        width = first.width + first.width % 2; height = first.height + first.height % 2
        origin = firstCaptureUptime
        url = directory.appendingPathComponent("native-motion.mov")
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.unsupportedEncoder }
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(12_000_000, max(2_000_000, width * height * 2)),
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        guard writer.canAdd(input) else { throw Failure.unsupportedEncoder }
        writer.add(input)
        guard writer.startWriting() else { throw Failure.unsupportedEncoder }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage, captureUptime: TimeInterval) {
        guard failure == nil, times.count < 200 else { return }
        guard image.width == contentWidth, image.height == contentHeight else {
            failure = "nativeWindowGeometryChanged"; writer.cancelWriting(); return
        }
        guard writer.status == .writing else { failure = "nativeMovieWriterStopped"; return }
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { dropped += 1; return }
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 3] as CFDictionary
        let allocation = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, attributes, &buffer)
        guard allocation == kCVReturnSuccess, let buffer else { dropped += 1; return }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { dropped += 1; return }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            dropped += 1; return
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        let elapsed = max(0, captureUptime - origin)
        guard times.last.map({ elapsed > $0 }) ?? true else { dropped += 1; return }
        if adaptor.append(buffer, withPresentationTime: CMTime(seconds: elapsed, preferredTimescale: 1_000_000)) {
            times.append(elapsed)
        } else {
            failure = "nativeMovieAppendFailed"; writer.cancelWriting()
        }
    }

    func finish() async -> [String: Any] {
        if failure == nil && !times.isEmpty && writer.status == .writing {
            input.markAsFinished()
            writer.finishWriting { }
            // Encoder completion is bounded separately from the <=6.45s scene.
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while writer.status == .writing && ProcessInfo.processInfo.systemUptime < deadline {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
        }
        guard failure == nil, times.count >= 2, writer.status == .completed else {
            if writer.status == .writing { writer.cancelWriting() }
            return ["status": "NOT_RUN", "reason": failure ?? "nativeMovieDidNotComplete",
                    "encodedFrameCount": times.count, "backpressureOrAllocationDrops": dropped]
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            var size = 0
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                hash.update(data: chunk); size += chunk.count
            }
            return ["status": "RECORDED_NATIVE_WINDOWSERVER", "file": url.lastPathComponent,
                "bytes": size, "sha256": hash.finalize().map { String(format: "%02x", $0) }.joined(),
                "codec": "H.264 in QuickTime MOV; lossy video encoding, original PNGs retained",
                "contentPixels": [contentWidth, contentHeight], "encodedPixels": [width, height],
                "paddingPixels": [width - contentWidth, height - contentHeight], "contentResized": false,
                "targetFrameRate": 30, "encodedFrameCount": times.count,
                "presentationSeconds": times, "firstCaptureUptime": origin,
                "backpressureOrAllocationDrops": dropped, "maximumPoolBuffers": 3,
                "timestamps": "Actual capture monotonic time relative to first capture; no interpolated/duplicate frames",
                "syntheticOnly": true, "receiptEvidence": false, "physicalInput": "NOT_RUN",
                "performanceBenchmark": false]
        } catch {
            return ["status": "NOT_RUN", "reason": "nativeMovieDigestUnavailable"]
        }
    }
}
