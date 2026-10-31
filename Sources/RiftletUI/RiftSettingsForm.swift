import AppKit
import RiftletCapture

/// Local preferences only. These values never express upload or retry admission.
public enum RiftSettingsSection: Int, CaseIterable { case status, captureEntry, display, privacy, about }

public struct RiftSettingsDisplay: Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public let uuid: String?
    public init(id: UInt32, name: String, uuid: String? = nil) { self.id = id; self.name = name; self.uuid = uuid }
}

public struct RiftSettingsSnapshot: Equatable, Sendable {
    public var entryAvailable: Bool
    public var entryEnabled: Bool
    public var capturePreferencesSaveFailed: Bool
    public var defaultCaptureMode: ScreenshotMode
    public var arrivalMode: ArrivalMotionMode
    public var hasArrivalSelection: Bool
    public var displays: [RiftSettingsDisplay]
    public var preferredDisplayID: UInt32?
    public var configuration: RiftConfiguration
    public var displayRestoreAvailable: Bool
    public var archiveAfterHours: Double?

    public init(entryAvailable: Bool = false, entryEnabled: Bool = true,
                capturePreferencesSaveFailed: Bool = false,
                defaultCaptureMode: ScreenshotMode = .window, arrivalMode: ArrivalMotionMode = .none,
                hasArrivalSelection: Bool = false, displays: [RiftSettingsDisplay] = [],
                preferredDisplayID: UInt32? = nil, archiveAfterHours: Double? = nil,
                configuration: RiftConfiguration = .init(), displayRestoreAvailable: Bool = false) {
        self.entryAvailable = entryAvailable; self.entryEnabled = entryEnabled
        self.capturePreferencesSaveFailed = capturePreferencesSaveFailed
        self.defaultCaptureMode = defaultCaptureMode; self.arrivalMode = arrivalMode
        self.hasArrivalSelection = hasArrivalSelection; self.displays = displays
        self.preferredDisplayID = preferredDisplayID; self.archiveAfterHours = archiveAfterHours
        self.configuration = configuration; self.displayRestoreAvailable = displayRestoreAvailable
    }
}

public enum RiftSettingsChange: Equatable, Sendable {
    case entryEnabled(Bool), defaultCaptureMode(ScreenshotMode), arrivalMode(ArrivalMotionMode)
    case preferredDisplay(UInt32?), archiveAfterHours(Double?)
    case geometry(hiddenFraction: Double, outerInset: Double, visibleCount: Int)
    case placement(RiftPlacement), restorePreferredDisplay
}

/// Embedded settings reuse the existing host persistence. A failed write keeps
/// the actual effective state, including an immediate unsaved disable. Refreshing
/// never opens a window or starts a capture.
@MainActor
final class RiftSettingsForm: NSObject {
    private(set) var snapshot = RiftSettingsSnapshot()
    private let onChange: (RiftSettingsChange) throws -> RiftSettingsSnapshot
    private let entry = NSButton(checkboxWithTitle: "启用内置截图", target: nil, action: nil)
    private let captureMode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let arrivalMode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let display = NSPopUpButton(frame: .zero, pullsDown: false)
    private let occlusion = NSTextField(string: "25")
    private let inset = NSTextField(string: "6")
    private let count = NSTextField(string: "3")
    private let occlusionSlider = RiftPreferenceSlider(value: 25, minValue: 0, maxValue: 90, target: nil, action: nil)
    private let insetSlider = RiftPreferenceSlider(value: 6, minValue: 0, maxValue: 256, target: nil, action: nil)
    private let countSlider = RiftPreferenceSlider(value: 3, minValue: 1, maxValue: 10, target: nil, action: nil)
    private let geometrySave = NSButton(title: "保存布局", target: nil, action: nil)
    private let restoreDisplay = NSButton(title: "回到已选显示器", target: nil, action: nil)
    private var placementButtons: [NSButton] = []
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
        entry.setAccessibilityLabel("启用内置截图")
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
        for (field, label) in [(occlusion,"截图遮挡百分比，0 至 90"), (inset,"距屏幕边缘点数，0 至 256"), (count,"常驻截图数量，1 至 10，不限制收录") ] {
            field.font = RiftVisualStyle.bodyFont; field.widthAnchor.constraint(equalToConstant: 64).isActive = true
            field.alignment = .right; field.setAccessibilityLabel(label)
            field.target = self; field.action = #selector(saveGeometry); field.cell?.sendsActionOnEndEditing = false
        }
        occlusion.identifier = .init("settings.occlusion"); inset.identifier = .init("settings.inset"); count.identifier = .init("settings.visibleCount")
        geometrySave.identifier = .init("settings.geometrySave"); restoreDisplay.identifier = .init("settings.restoreDisplay")
        for (slider, label, id) in [(occlusionSlider,"截图遮挡百分比","occlusion"),(insetSlider,"距屏幕边缘点数","inset"),(countSlider,"常驻截图数量","visibleCount")] {
            slider.isContinuous = false; slider.target = self; slider.action = #selector(sliderChanged(_:))
            slider.setAccessibilityLabel(label); slider.identifier = .init("settings.slider." + id)
            slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        }
        countSlider.numberOfTickMarks = 10; countSlider.allowsTickMarkValuesOnly = true
        geometrySave.target = self; geometrySave.action = #selector(saveGeometry); RiftVisualStyle.style(geometrySave)
        restoreDisplay.target = self; restoreDisplay.action = #selector(restorePreferred); RiftVisualStyle.style(restoreDisplay)
        placementButtons = RiftPlacement.allCases.enumerated().map { index, placement in
            let button = NSButton(title: placement.title, target: self, action: #selector(selectPlacement(_:)))
            button.tag = index; button.identifier = .init("settings.placement." + placement.rawValue); button.setButtonType(.pushOnPushOff); button.bezelStyle = .rounded
            button.setAccessibilityLabel("裂缝位置：" + placement.title); return button
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
        let uuidMatches = value.configuration.preferredDisplayUUID.map { uuid in value.displays.filter { $0.uuid == uuid } } ?? []
        let selectedDisplayID = uuidMatches.count == 1 ? uuidMatches.first?.id : value.preferredDisplayID
        if old.displays != value.displays || old.preferredDisplayID != value.preferredDisplayID || old.configuration.preferredDisplayUUID != value.configuration.preferredDisplayUUID || display.numberOfItems == 0 {
            display.removeAllItems(); displayIDs = [nil]
            display.addItem(withTitle: "使用主显示器")
            for choice in value.displays { display.addItem(withTitle: choice.name); displayIDs.append(choice.id) }
            if let selected = selectedDisplayID, !value.displays.contains(where: { $0.id == selected }) {
                display.addItem(withTitle: "已选显示器（未连接）"); displayIDs.append(selected)
            }
        }
        // Selection is restored even when the menu's item list is unchanged.
        // In particular, a failed host write must not display the unsaved item.
        display.selectItem(at: displayIDs.firstIndex(where: { $0 == selectedDisplayID }) ?? 0)
        display.isEnabled = enabled
        let disconnected = selectedDisplayID.map { selected in !value.displays.contains { $0.id == selected } } ?? false
        displayHint.stringValue = disconnected ? "已选显示器暂未连接，当前使用可用主屏；连接后可明确恢复原选择。" : "选择会保留。显示器断开时，临时使用可用主屏。"
        restoreDisplay.isHidden = !value.displayRestoreAvailable; restoreDisplay.isEnabled = enabled
        if occlusion.currentEditor() == nil { occlusion.stringValue = String(format:"%.6g",value.configuration.hiddenFraction * 100) }
        if inset.currentEditor() == nil { inset.stringValue = String(format:"%.6g",value.configuration.outerInset) }
        if count.currentEditor() == nil { count.stringValue = String(value.configuration.visibleCountPreference) }
        for (slider, saved) in [(occlusionSlider,value.configuration.hiddenFraction * 100),(insetSlider,value.configuration.outerInset),(countSlider,Double(value.configuration.visibleCountPreference))] {
            if !slider.isTrackingPreference { slider.doubleValue = saved }; slider.isEnabled = enabled
        }
        for field in [occlusion,inset,count] { field.isEnabled = enabled }; geometrySave.isEnabled = enabled
        for (index, button) in placementButtons.enumerated() { button.isEnabled = enabled; button.state = value.configuration.placement == RiftPlacement.allCases[index] ? .on : .off }
        entryHint.stringValue = value.entryAvailable ? "默认方式在下一次入口会话生效；当前截图模式与槽位保持。关闭内置截图仍可收录系统截图。" : "此运行模式未启用截图入口；已有本地截图和历史保持可用。"
        if value.capturePreferencesSaveFailed {
            entryHint.stringValue = Self.captureSaveFailureMessage(value)
        }
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
            let positions = NSStackView(views: (0..<3).map { NSStackView(views: [placementButtons[$0], placementButtons[$0 + 3]]) })
            positions.orientation = .vertical; positions.spacing = 4
            return [card([row("裂缝所在显示器", display), displayHint, restoreDisplay, row("位置", positions),
                row("遮挡（%）", NSStackView(views:[occlusionSlider,occlusion])), row("距边（pt）", NSStackView(views:[insetSlider,inset])), row("常驻数量", NSStackView(views:[countSlider,count])), geometrySave,
                RiftVisualStyle.label("常驻数量只改变当前显示，不限制截图收录。新图不会自动翻页。", role: "secondary")]),
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
            switch change {
            case .entryEnabled, .defaultCaptureMode:
                message.stringValue = saved.capturePreferencesSaveFailed ? Self.captureSaveFailureMessage(saved) : "已保存"
                message.textColor = saved.capturePreferencesSaveFailed ? .systemOrange : RiftVisualStyle.secondary
            default:
                message.stringValue = "已保存"; message.textColor = RiftVisualStyle.secondary
            }
        } catch {
            update(snapshot, enabled: enabled)
            if case .geometry = change {
                occlusion.stringValue = String(format: "%.6g", snapshot.configuration.hiddenFraction * 100)
                inset.stringValue = String(format: "%.6g", snapshot.configuration.outerInset)
                count.stringValue = String(snapshot.configuration.visibleCountPreference)
            }
            message.stringValue = "未能保存，仍保留原来的设置。请稍后重试。"; message.textColor = .systemOrange
        }
        message.isHidden = false; RiftVisualStyle.applyTextStyle(message)
    }

    private static func captureSaveFailureMessage(_ value: RiftSettingsSnapshot) -> String {
        value.entryEnabled
            ? "设置未能保存；继续使用当前生效的内置截图设置。请检查可用存储空间后重试。"
            : "内置截图当前已关闭；设置尚未保存，重启可能恢复先前设置。请检查可用存储空间后重试。"
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
    @objc private func selectPlacement(_ sender: NSButton) {
        guard enabled, RiftPlacement.allCases.indices.contains(sender.tag) else { return }
        apply(.placement(RiftPlacement.allCases[sender.tag]))
    }
    @objc private func restorePreferred() { guard enabled else { return }; apply(.restorePreferredDisplay) }
    @objc private func sliderChanged(_ slider: NSSlider) {
        guard enabled else { return }
        var c = snapshot.configuration
        if slider === occlusionSlider { c.hiddenFraction = slider.doubleValue / 100 }
        else if slider === insetSlider { c.outerInset = slider.doubleValue }
        else if slider === countSlider { c.visibleCountPreference = Int(slider.doubleValue.rounded()) }
        apply(.geometry(hiddenFraction:c.hiddenFraction,outerInset:c.outerInset,visibleCount:c.visibleCountPreference))
        // A failed host write restores the slider even during its final tracking callback.
        occlusionSlider.doubleValue = snapshot.configuration.hiddenFraction * 100
        insetSlider.doubleValue = snapshot.configuration.outerInset
        countSlider.doubleValue = Double(snapshot.configuration.visibleCountPreference)
    }
    @objc private func saveGeometry() {
        func number(_ field: NSTextField) -> Double? {
            let s = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
            guard s.range(of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options:.regularExpression) != nil,
                  let n = Double(s), n.isFinite else { return nil }; return n
        }
        guard enabled, let h = number(occlusion), (0...90).contains(h),
              let d = number(inset), (0...256).contains(d), let n = number(count), (1...10).contains(n), n.rounded() == n else {
            message.stringValue = "请输入遮挡 0–90%、距边 0–256 pt、常驻 1–10 张整数。"
            message.textColor = .systemOrange; message.isHidden = false; return
        }
        apply(.geometry(hiddenFraction:h / 100,outerInset:d,visibleCount:Int(n)))
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

@MainActor private final class RiftPreferenceSlider: NSSlider {
    private(set) var isTrackingPreference = false
    override func mouseDown(with event: NSEvent) {
        isTrackingPreference = true
        defer { isTrackingPreference = false }
        super.mouseDown(with: event)
    }
}
