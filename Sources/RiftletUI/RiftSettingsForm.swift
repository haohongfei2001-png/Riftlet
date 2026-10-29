import AppKit
import RiftletCapture

/// Local preferences only. These values never express upload or retry admission.
public enum RiftSettingsSection: Int, CaseIterable { case status, captureEntry, display, privacy, about }

public struct RiftSettingsDisplay: Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public init(id: UInt32, name: String) { self.id = id; self.name = name }
}

public struct RiftSettingsSnapshot: Equatable, Sendable {
    public var entryAvailable: Bool
    public var entryEnabled: Bool
    public var defaultCaptureMode: ScreenshotMode
    public var arrivalMode: ArrivalMotionMode
    public var hasArrivalSelection: Bool
    public var displays: [RiftSettingsDisplay]
    public var preferredDisplayID: UInt32?
    public var archiveAfterHours: Double?

    public init(entryAvailable: Bool = false, entryEnabled: Bool = true,
                defaultCaptureMode: ScreenshotMode = .window, arrivalMode: ArrivalMotionMode = .none,
                hasArrivalSelection: Bool = false, displays: [RiftSettingsDisplay] = [],
                preferredDisplayID: UInt32? = nil, archiveAfterHours: Double? = nil) {
        self.entryAvailable = entryAvailable; self.entryEnabled = entryEnabled
        self.defaultCaptureMode = defaultCaptureMode; self.arrivalMode = arrivalMode
        self.hasArrivalSelection = hasArrivalSelection; self.displays = displays
        self.preferredDisplayID = preferredDisplayID; self.archiveAfterHours = archiveAfterHours
    }
}

public enum RiftSettingsChange: Equatable, Sendable {
    case entryEnabled(Bool), defaultCaptureMode(ScreenshotMode), arrivalMode(ArrivalMotionMode)
    case preferredDisplay(UInt32?), archiveAfterHours(Double?)
}

/// Embedded settings reuse the existing host persistence. A failed write keeps
/// the previous selection; refreshing never opens a window or starts a capture.
@MainActor
final class RiftSettingsForm: NSObject {
    private(set) var snapshot = RiftSettingsSnapshot()
    private let onChange: (RiftSettingsChange) throws -> RiftSettingsSnapshot
    private let entry = NSButton(checkboxWithTitle: "启用预测式截图入口", target: nil, action: nil)
    private let captureMode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let arrivalMode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let display = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hours = NSTextField(string: "0")
    private let archiveSave = NSButton(title: "保存", target: nil, action: nil)
    private let preview = ArrivalPreviewView(frame: .zero)
    private let motionHint = RiftVisualStyle.label("", role: "secondary")
    private let displayHint = RiftVisualStyle.label("", role: "secondary")
    private let entryHint = RiftVisualStyle.label("", role: "secondary")
    private let message = RiftVisualStyle.label("", role: "secondary")
    private var displayIDs: [UInt32?] = []
    private var accessibilityObserver: NSObjectProtocol?
    private var enabled = false
    private var shownSection: RiftSettingsSection?

    init(onChange: @escaping (RiftSettingsChange) throws -> RiftSettingsSnapshot) {
        self.onChange = onChange
        super.init()
        entry.target = self; entry.action = #selector(toggleEntry)
        entry.identifier = .init("settings.entryEnabled")
        captureMode.addItems(withTitles: ["窗口", "区域", "全屏"])
        captureMode.target = self; captureMode.action = #selector(selectCaptureMode)
        captureMode.identifier = .init("settings.captureMode"); captureMode.setAccessibilityLabel("默认截图方式")
        arrivalMode.addItems(withTitles: ArrivalMotionMode.allCases.map(\.title))
        arrivalMode.target = self; arrivalMode.action = #selector(selectArrivalMode)
        arrivalMode.identifier = .init("settings.arrivalMode"); arrivalMode.setAccessibilityLabel("入缝动效")
        display.target = self; display.action = #selector(selectDisplay)
        display.identifier = .init("settings.display"); display.setAccessibilityLabel("裂缝所在显示器")
        for control in [captureMode, arrivalMode, display] {
            control.font = RiftVisualStyle.bodyFont
            control.widthAnchor.constraint(equalToConstant: 190).isActive = true
        }
        entry.font = RiftVisualStyle.bodyFont
        hours.font = RiftVisualStyle.bodyFont; hours.alignment = .right
        hours.target = self; hours.action = #selector(saveArchive)
        // Save is deliberate: Return or the Save button, never a focus change.
        hours.cell?.sendsActionOnEndEditing = false
        hours.identifier = .init("settings.archiveHours"); hours.setAccessibilityLabel("闲置归档小时数，0 表示关闭")
        hours.widthAnchor.constraint(equalToConstant: 68).isActive = true
        archiveSave.target = self; archiveSave.action = #selector(saveArchive)
        archiveSave.identifier = .init("settings.archiveSave"); RiftVisualStyle.style(archiveSave)
        message.identifier = .init("settings.saveStatus"); message.isHidden = true
        preview.identifier = .init("settings.motionPreviewImage")
        preview.heightAnchor.constraint(equalToConstant: 104).isActive = true
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.preview.recordDiagnostic("accessibility.notification")
                    self.refreshMotion(play: false)
                }
            }
    }

    deinit { if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) } }

    func update(_ value: RiftSettingsSnapshot, enabled: Bool) {
        let old = snapshot
        snapshot = value; self.enabled = enabled
        entry.state = value.entryEnabled ? .on : .off
        entry.isEnabled = enabled && value.entryAvailable
        captureMode.selectItem(at: Self.captureModes.firstIndex(of: value.defaultCaptureMode) ?? 0)
        captureMode.isEnabled = enabled && value.entryAvailable
        arrivalMode.selectItem(at: ArrivalMotionMode.allCases.firstIndex(of: value.arrivalMode) ?? 0)
        arrivalMode.isEnabled = enabled
        if old.displays != value.displays || old.preferredDisplayID != value.preferredDisplayID || display.numberOfItems == 0 {
            display.removeAllItems(); displayIDs = [nil]
            display.addItem(withTitle: "跟随主显示器")
            for choice in value.displays { display.addItem(withTitle: choice.name); displayIDs.append(choice.id) }
            if let selected = value.preferredDisplayID, !value.displays.contains(where: { $0.id == selected }) {
                display.addItem(withTitle: "已选显示器（未连接）"); displayIDs.append(selected)
            }
        }
        // Selection is restored even when the menu's item list is unchanged.
        // In particular, a failed host write must not display the unsaved item.
        display.selectItem(at: displayIDs.firstIndex(where: { $0 == value.preferredDisplayID }) ?? 0)
        display.isEnabled = enabled
        let disconnected = value.preferredDisplayID.map { selected in !value.displays.contains { $0.id == selected } } ?? false
        displayHint.stringValue = disconnected ? "已选显示器暂未连接，当前使用可用主屏；连接恢复后自动回到原选择。" : "选择会保留。显示器断开时，临时使用可用主屏。"
        entryHint.stringValue = value.entryAvailable ? "默认方式下次打开入口时生效；当前模式与槽位保持。关闭入口仍可收录系统截图。" : "此运行模式未启用截图入口；已有本地截图和历史保持可用。"
        if hours.currentEditor() == nil { hours.stringValue = value.archiveAfterHours.map { String(format: "%.6g", $0) } ?? "0" }
        if hours.isEnabled != enabled { hours.isEnabled = enabled }
        archiveSave.isEnabled = enabled
        for field in [displayHint, entryHint] { RiftVisualStyle.applyTextStyle(field) }
        refreshMotion(play: false, redraw: old.arrivalMode != value.arrivalMode)
    }

    func content(for section: RiftSettingsSection) -> [NSView] {
        preview.stop(reason: "form.content section=\(section.rawValue)"); shownSection = section
        message.isHidden = true
        refreshMotion(play: false)
        switch section {
        case .captureEntry:
            return [card([entry, row("默认截图方式", captureMode), entryHint]), message]
        case .display:
            let replay = NSButton(title: "预览动效", target: self, action: #selector(replay))
            replay.identifier = .init("settings.motionPreview"); RiftVisualStyle.style(replay)
            let previewActions = NSStackView(views: [RiftVisualStyle.label("示意图 · 不会截图或上传", role: "secondary"), NSView(), replay])
            previewActions.spacing = 8
            return [card([row("裂缝所在显示器", display), displayHint]),
                card([row("入缝动效", arrivalMode), preview, previewActions, motionHint]), message]
        case .privacy:
            let input = NSStackView(views: [hours, RiftVisualStyle.label("小时"), archiveSave]); input.spacing = 8
            return [card([row("闲置后归档", input),
                RiftVisualStyle.label("输入 0 关闭。只收起长时间未用的截图，保留原件和本地历史；不会移除聊天附件。", role: "secondary")]), message]
        default: return []
        }
    }

    func stop() { preview.stop(reason: "form.stop"); shownSection = nil }

    private func card(_ views: [NSView]) -> NSView {
        let card = RiftVisualStyle.card(views)
        if let stack = card.subviews.first as? NSStackView {
            for view in views where !(view is NSTextField) {
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        return card
    }

    private static let captureModes: [ScreenshotMode] = [.window, .region, .fullScreen]
    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = RiftVisualStyle.label(title)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, control]); row.spacing = 12; row.alignment = .centerY
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func apply(_ change: RiftSettingsChange) {
        guard enabled else { return }
        do {
            let saved = try onChange(change)
            update(saved, enabled: enabled)
            message.stringValue = "已保存"; message.textColor = RiftVisualStyle.secondary
        } catch {
            update(snapshot, enabled: enabled)
            message.stringValue = "未能保存，仍保留原来的设置。请稍后重试。"; message.textColor = .systemOrange
        }
        message.isHidden = false; RiftVisualStyle.applyTextStyle(message)
    }

    @objc private func toggleEntry() { guard entry.isEnabled else { return }; apply(.entryEnabled(entry.state == .on)) }
    @objc private func selectCaptureMode() {
        guard captureMode.isEnabled, Self.captureModes.indices.contains(captureMode.indexOfSelectedItem) else { return }
        apply(.defaultCaptureMode(Self.captureModes[captureMode.indexOfSelectedItem]))
    }
    @objc private func selectArrivalMode() {
        guard arrivalMode.isEnabled, ArrivalMotionMode.allCases.indices.contains(arrivalMode.indexOfSelectedItem) else { return }
        apply(.arrivalMode(ArrivalMotionMode.allCases[arrivalMode.indexOfSelectedItem])); refreshMotion(play: true)
    }
    @objc private func selectDisplay() {
        guard display.isEnabled, displayIDs.indices.contains(display.indexOfSelectedItem) else { return }
        apply(.preferredDisplay(displayIDs[display.indexOfSelectedItem]))
    }
    @objc private func saveArchive() {
        guard hours.isEnabled else { return }
        let text = hours.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = separator == "." ? text : text.replacingOccurrences(of: separator, with: ".")
        // Parse the whole field; NumberFormatter's prefix parsing would accept
        // a typo such as 1abc and silently save one hour.
        guard normalized.range(of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite, value >= 0, (value * 3600).isFinite else {
            message.stringValue = "请输入有效的非负小时数；0 表示关闭。"; message.textColor = .systemOrange
            message.isHidden = false; RiftVisualStyle.applyTextStyle(message); return
        }
        let requested: Double? = value == 0 ? nil : value
        let persistedHours = requested.map { ($0 * 3600) / 3600 }
        // AppKit can finish editing while an action refreshes its controls.
        // Match the host's seconds-to-hours round trip, including fractional
        // values, so repeated delivery cannot cause another durable write.
        guard persistedHours != snapshot.archiveAfterHours else {
            message.stringValue = "已保存"; message.textColor = RiftVisualStyle.secondary; message.isHidden = false
            RiftVisualStyle.applyTextStyle(message); return
        }
        apply(.archiveAfterHours(requested))
    }
    @objc private func replay() {
        preview.recordDiagnostic("replay.action.enter")
        refreshMotion(play: true)
        preview.recordDiagnostic("replay.action.exit")
    }
    private func refreshMotion(play: Bool, redraw: Bool = true) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        motionHint.stringValue = reduced ? "系统已开启“减少动态效果”，当前直接呈现；保留你的动效选择。"
            : snapshot.hasArrivalSelection ? "只改变新截图到达边缘的过程；上传开始后的快速吞噬保留。"
            : "当前使用“无”。你可以选择磁力吸引，先在这里预览。"
        RiftVisualStyle.applyTextStyle(motionHint)
        guard shownSection == .display, redraw else { return }
        // Finish any pending initial/control layout before installing animation;
        // a subsequent genuine size change still cancels through the view.
        if play { preview.window?.contentView?.layoutSubtreeIfNeeded() }
        preview.show(snapshot.arrivalMode.effective(reduceMotion: reduced), animate: play && preview.window?.isVisible == true,
                     reason: "form.refresh play=\(play) redraw=\(redraw)")
    }
}
