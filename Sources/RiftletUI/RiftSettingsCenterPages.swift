import AppKit
import RiftletCapture

@MainActor
extension RiftSettingsCenterController {
    func buildPages() {
        makePage(.general, subtitle: "运行状态与常用偏好。即时开关和需要应用的参数分开保存。", views: generalContent())
        makePage(.display, subtitle: "选择裂缝出现的位置，再按需微调。参数草稿会保留到你应用或放弃。", views: displayContent())
        makePage(.capture, subtitle: "继续使用熟悉的 macOS 截图方式，也可使用 Riftlet 内置截图。", views: captureContent())
        makePage(.motion, subtitle: "选择入缝方式，主动预览。动效不改变点击、附加或上传开始的判断。", views: motionContent())
        makePage(.history, subtitle: "图片与记录保存在本机。收起微图和自动归档都不删除原图。", views: historyContent())
        makePage(.help, subtitle: "每项权限只用于对应功能，可以分别检查。", views: helpContent())
    }

    func makePage(_ page: SettingsPage, subtitle: String, views: [NSView]) {
        let all = [SettingsNativeStyle.label(page.title, role: "title"), SettingsNativeStyle.label(subtitle, role: "secondary")] + views
        let stack = RiftVisualStyle.documentStack(all, spacing: 17)
        stack.identifier = .init("settings.center.page.\(page.rawValue)")
        stack.edgeInsets = NSEdgeInsets(top: 27, left: 31, bottom: 27, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in all { view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -57).isActive = true }
        // Stable legacy gutter prevents an asynchronous scroller-style change
        // from resizing/cancelling the synthetic preview mid-animation.
        let gutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let width = stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -gutter)
        pageWidthConstraints[page] = width
        pages[page] = stack
    }

    func generalContent() -> [NSView] {
        let pause = nativeSwitch("暂停收录", id: "paused") { [weak self] value in self?.dispatch(.settings(.setCollectionPaused(value))) }
        let hidden = nativeSwitch("隐藏裂缝", id: "hidden") { [weak self] value in self?.dispatch(.settings(.setHidden(value))) }
        let status = card([
            namedLabel("status.title", role: "heading"), namedLabel("status.detail", role: "secondary"),
            row("暂停收录", detail: "暂停后不收录新截图，已有图片保留。", control: pause), domainError(.collection),
            row("隐藏裂缝", detail: "只隐藏边缘微图，不改变收录设置。", control: hidden), domainError(.visibility)
        ])
        let login = nativeSwitch("登录后启动 Riftlet", id: "login") { [weak self] value in self?.dispatch(.loginEnabled(value)) }
        let appearance = popup("外观", id: "appearance", titles: SettingsAppearanceChoice.allCases.map(\.title)) { [weak self] popup in
            guard SettingsAppearanceChoice.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.appearance(SettingsAppearanceChoice.allCases[popup.indexOfSelectedItem]))
        }
        let loginButtons = buttonRow([
            makeButton("重试这次选择", id: "login.retry") { [weak self] in self?.dispatch(.retryLogin) },
            makeButton("打开登录项设置…", id: "login.system") { [weak self] in self?.dispatch(.openLoginSettings) }
        ])
        let preferences = card([
            row("登录启动", detail: "由 macOS 管理，只在明确操作时注册或取消。", control: login),
            namedLabel("login.detail", role: "secondary"), loginButtons,
            row("外观", detail: "跟随系统、浅色或深色。", control: appearance),
            namedLabel("appearance.detail", role: "secondary"),
            makeButton("重试保存外观", id: "appearance.retry") { [weak self] in self?.dispatch(.retryAppearance) },
            namedLabel("accessibility", role: "secondary")
        ])
        return [status, preferences, buttonRow([
            makeButton("重新查看使用引导…", id: "guide.general") { [weak self] in self?.dispatch(.openOnboarding) },
            makeButton("反馈与建议…", id: "feedback.general") { [weak self] in self?.dispatch(.openFeedback) }
        ])]
    }

    func displayContent() -> [NSView] {
        geometryPreview.identifier = .init("settings.center.layoutPreview")
        geometryPreview.heightAnchor.constraint(equalToConstant: 151).isActive = true
        let display = popup("显示器", id: "display", titles: []) { [weak self] popup in
            guard let self, let number = popup.selectedItem?.representedObject as? NSNumber else { return }
            dispatch(.settings(.selectDisplay(number.uint32Value)))
        }
        display.menu?.delegate = self
        let positions: [[RiftPlacement]] = [[.leftTop, .rightTop], [.leftMiddle, .rightMiddle], [.leftBottom, .rightBottom]]
        let positionRows = positions.map { pair in
            buttonRow(pair.map { placement in
                let button = makeButton(placement.title, id: "placement.\(placement.rawValue)") { [weak self] in
                    self?.dispatch(.settings(.selectPlacement(placement)))
                }
                button.setButtonType(.toggle)
                button.setAccessibilityLabel(placement.title)
                button.imagePosition = .imageLeading
                button.imageHugsTitle = true
                button.widthAnchor.constraint(equalToConstant: 88).isActive = true
                return button
            })
        }
        let basic = card([
            geometryPreview, namedLabel("layoutPreview.detail", role: "caption"),
            row("显示器", detail: "保存具体显示器；临时回退不会更改你的选择。", control: display),
            namedLabel("display.detail", role: "secondary"), domainError(.display),
            makeButton("回到已选显示器", id: "display.restore") { [weak self] in self?.dispatch(.restorePreferredDisplay) },
            row("边缘位置", detail: "左右两列对应屏幕两侧。", control: SettingsNativeStyle.stack(positionRows, spacing: 6)),
            domainError(.placement), numericRow(.visibleCountPreference, title: "可见数量", unit: "张", range: 1...10, step: 1)
        ])
        let detailed = SettingsNativeStyle.stack([
            numericRow(.hiddenFraction, title: "藏入边缘", unit: "%", range: 0...90),
            numericRow(.outerInset, title: "边缘内缩", unit: "pt", range: 0...256),
            numericRow(.fitWidth, title: "微图最大宽度", unit: "pt"),
            numericRow(.fitHeight, title: "微图最大高度", unit: "pt"),
            numericRow(.rowPitch, title: "微图排列间距", unit: "pt"),
            numericRow(.numberFontSize, title: "编号字号", unit: "pt")
        ], spacing: 13)
        legacyFieldRow = numericRow(.firstCenterFromTop, title: "旧版距顶部位置", unit: "pt")
        let fine = SettingsNativeStyle.stack([
            numericRow(.numberGap, title: "编号与微图间距", unit: "pt"),
            numericRow(.leftPadding, title: "行左侧留白", unit: "pt"),
            numericRow(.minimumHitWidth, title: "最小行宽", unit: "pt"),
            numericRow(.minimumHitHeight, title: "最小行高", unit: "pt"), legacyFieldRow,
            SettingsNativeStyle.label("最小行尺寸用于排列，不代表整个矩形都是点击区域。旧版绝对位置仅在尚未选择六点位置时生效。", role: "caption"),
            SettingsNativeStyle.label("兼容参数仍保留：线宽、延伸长度、空队列线长度、屏幕边距、旧入缝时长、内移距离、旧减少动态时长。当前界面不编辑或重置这些值。", role: "caption")
        ], spacing: 13)
        return [basic, card([disclosure("详细自定义", id: "display.details", content: detailed),
                            disclosure("精细参数", id: "display.fine", content: fine)]),
                layoutSaveArea(for: .display)]
    }

    func captureContent() -> [NSView] {
        let entry = nativeSwitch("启用内置截图", id: "entry") { [weak self] value in self?.dispatch(.settings(.setEntryEnabled(value))) }
        let mode = popup("默认截图方式", id: "captureMode", titles: ["窗口", "区域", "全屏"]) { [weak self] popup in
            let modes: [ScreenshotMode] = [.window, .region, .fullScreen]
            guard modes.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.settings(.setCaptureMode(modes[popup.indexOfSelectedItem])))
        }
        return [card([
            SettingsNativeStyle.label("沿用 macOS 截图习惯", role: "heading"),
            SettingsNativeStyle.label("⇧⌘3  全屏    ⇧⌘4  区域    ⇧⌘5  截图工具栏"),
            SettingsNativeStyle.label("保存到当前系统截图位置的新截图会按收录开关处理；复制到剪贴板不是文件收录。", role: "secondary"),
            namedLabel("source.capture", role: "secondary"), namedLabel("sourcePath.capture", role: "caption"),
            buttonRow([
                makeButton("打开截图位置", id: "source.open.capture") { [weak self] in self?.dispatch(.openSource) },
                makeButton("允许访问此位置…", id: "source.access.capture") { [weak self] in self?.dispatch(.chooseSourceAccess) }
            ])
        ]), card([
            row("启用内置截图", detail: "关闭此入口不影响 macOS 系统截图和截图文件收录。", control: entry), domainError(.entry),
            row("默认方式", detail: "只影响下一次内置截图；当前截图会话保持原选择。", control: mode), domainError(.captureMode),
            namedLabel("screen.capture", role: "secondary"),
            makeButton("开始内置截图…", id: "capture.start") { [weak self] in self?.dispatch(.capture) },
            SettingsNativeStyle.label("延迟、指针等选项属于每次截图会话，不新增全局偏好。", role: "caption")
        ]), makeButton("查看权限与帮助…", id: "permissions.capture") { [weak self] in self?.navigate(to: .help) }]
    }

    func motionContent() -> [NSView] {
        let mode = popup("入缝动效", id: "arrival", titles: ArrivalMotionMode.allCases.map(\.title)) { [weak self] popup in
            guard ArrivalMotionMode.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.settings(.setArrival(ArrivalMotionMode.allCases[popup.indexOfSelectedItem])))
        }
        arrivalPreview.identifier = .init("settings.center.arrivalPreview")
        swallowPreview.identifier = .init("settings.center.swallowPreview")
        [arrivalPreview, swallowPreview].forEach { $0.heightAnchor.constraint(equalToConstant: 116).isActive = true }
        let fine = SettingsNativeStyle.stack([
            numericRow(.pressDuration, title: "轻按反馈", unit: "ms"),
            numericRow(.swallowDuration, title: "快速吞噬", unit: "ms"),
            numericRow(.shiftDuration, title: "队列移位", unit: "ms"),
            numericRow(.returnDuration, title: "失败回归", unit: "ms"),
            SettingsNativeStyle.label("范围 0–3000 ms。这里只调整呈现时间，不修改附加、上传开始、完成或重试规则。", role: "caption")
        ], spacing: 13)
        return [card([
            row("截图到达边缘时", detail: "选择立即保存；只在点击预览后播放示意动画。", control: mode), domainError(.arrival),
            namedLabel("motion.detail", role: "secondary"), arrivalPreview,
            makeButton("预览入缝", id: "arrival.preview") { [weak self] in self?.playArrival() }
        ]), card([
            SettingsNativeStyle.label("上传开始后的快速吞噬", role: "heading"),
            SettingsNativeStyle.label("与入缝偏好独立。此处使用绘制的示意图，不读取或附加任何截图。", role: "secondary"),
            swallowPreview, makeButton("预览吞噬", id: "swallow.preview") { [weak self] in self?.playSwallow() },
            namedLabel("motion.effective", role: "caption"), disclosure("精细参数", id: "motion.fine", content: fine)
        ]), layoutSaveArea(for: .motion)]
    }

    func historyContent() -> [NSView] {
        let preset = popup("自动归档时限", id: "archive.preset", titles: ["不自动归档", "1 小时", "8 小时", "24 小时", "72 小时", "自定义…"]) { [weak self] popup in
            guard let self else { return }
            let values = ["0", "1", "8", "24", "72"]
            archiveCustom = popup.indexOfSelectedItem == 5
            if values.indices.contains(popup.indexOfSelectedItem) { model.setArchiveDraftText(values[popup.indexOfSelectedItem]) }
            refreshDraftPresentation()
            window.recalculateKeyViewLoop()
            if archiveCustom { window.makeFirstResponder(archiveField) }
        }
        archiveField = textField(id: "archive.hours", accessibility: "自定义归档小时数")
        archiveCustomRow = row("自定义时限", detail: "支持小数小时，0 表示不自动归档。", control: buttonRow([archiveField, SettingsNativeStyle.label("小时", role: "secondary")]))
        let archive = card([
            row("长时间未使用的微图", detail: "鼠标悬停、按住、选中或动画期间，会等待交互结束。", control: preset),
            archiveCustomRow, namedLabel("archive.detail", role: "secondary"), domainError(.archive),
            buttonRow([
                makeButton("保存归档时限", id: "archive.save") { [weak self] in self?.flushEditor(); self?.dispatch(.settings(.applyArchive)) },
                makeButton("放弃更改", id: "archive.discard") { [weak self] in self?.replaceDrafts(.discardArchive) }
            ])
        ])
        return [card([
            SettingsNativeStyle.label("本地历史", role: "heading"), namedLabel("history.detail", role: "secondary"),
            makeButton("打开历史…", id: "history.open") { [weak self] in self?.dispatch(.openHistory) }
        ]), archive, card([
            SettingsNativeStyle.label("存储用量", role: "heading"), namedLabel("storage", role: "secondary"),
            makeButton("检查用量", id: "storage.check") { [weak self] in self?.dispatch(.checkStorage) },
            SettingsNativeStyle.label("收起与归档只影响 Riftlet 中的显示；不会删除原截图、本地副本或聊天附件。", role: "caption"),
            // Main owns the single shared confirmation for every entry point.
            makeButton("收起全部微图…", id: "history.clear") { [weak self] in self?.dispatch(.clearVisible) }
        ])]
    }

    func helpContent() -> [NSView] {
        let diagnostic = SettingsNativeStyle.stack([
            namedLabel("diagnostics", role: "caption"),
            SettingsNativeStyle.label("这里只展示设置与能力摘要；不读取图片、聊天内容或浏览器会话。反馈中的诊断由你主动选择。", role: "caption"),
            buttonRow([
                makeButton("重新读取配置", id: "configuration.reload") { [weak self] in self?.dispatch(.reloadConfiguration) },
                makeButton("打开配置文件…", id: "configuration.open") { [weak self] in self?.dispatch(.openConfiguration) }
            ])
        ])
        return [card([
            SettingsNativeStyle.label("截图保存位置", role: "heading"), namedLabel("source.help", role: "secondary"), namedLabel("sourcePath.help", role: "caption"),
            buttonRow([
                makeButton("允许访问此位置…", id: "source.access.help") { [weak self] in self?.dispatch(.chooseSourceAccess) },
                makeButton("文件访问设置…", id: "source.privacy") { [weak self] in self?.dispatch(.openFilePrivacy) }
            ])
        ]), card([
            SettingsNativeStyle.label("Chrome 自动化与 JavaScript", role: "heading"), namedLabel("automation", role: "secondary"),
            SettingsNativeStyle.label("另需在 Chrome 菜单「视图 → 开发者」中允许来自 Apple 事件的 JavaScript。macOS 自动化授权不代表该项已开启，也不代表当前附件目标可用。", role: "secondary"),
            namedLabel("attachment", role: "secondary"),
            makeButton("检查 Chrome 权限…", id: "automation.request") { [weak self] in self?.dispatch(.requestAutomation) }
        ]), card([
            SettingsNativeStyle.label("内置截图的屏幕录制权限", role: "heading"), namedLabel("screen.help", role: "secondary"),
            SettingsNativeStyle.label("只影响内置截图；不会因此阻止系统截图文件的收录。", role: "caption"),
            buttonRow([
                makeButton("屏幕录制设置…", id: "screen.privacy") { [weak self] in self?.dispatch(.openScreenRecordingPrivacy) },
                makeButton("重新检查", id: "recheck") { [weak self] in self?.dispatch(.recheck) }
            ])
        ]), card([
            SettingsNativeStyle.label("关于 Riftlet", role: "heading"), namedLabel("version", role: "secondary"), namedLabel("support", role: "secondary"),
            buttonRow([
                makeButton("使用引导…", id: "guide.help") { [weak self] in self?.dispatch(.openOnboarding) },
                makeButton("反馈与建议…", id: "feedback.help") { [weak self] in self?.dispatch(.openFeedback) }
            ]), disclosure("诊断与配置", id: "diagnostics", content: diagnostic)
        ])]
    }

    func layoutSaveArea(for page: SettingsDraftPage) -> NSView {
        let suffix = page == .display ? "display" : "motion"
        return card([
            namedLabel("layout.detail.\(suffix)", role: "secondary"),
            // Both pages project the same domain without sharing a view parent.
            page == .display ? domainError(.layout) : alternateLayoutError(),
            buttonRow([
                makeButton("恢复本页默认值", id: "layout.defaults.\(suffix)") { [weak self] in self?.replaceDrafts(.restoreDefaults(page)) },
                makeButton("放弃参数更改", id: "layout.discard.\(suffix)") { [weak self] in self?.replaceDrafts(.discardLayout) },
                makeButton("应用参数", id: "layout.apply.\(suffix)") { [weak self] in self?.flushEditor(); self?.dispatch(.settings(.applyLayout)) }
            ])
        ])
    }

    func alternateLayoutError() -> NSView {
        let label = namedLabel("layout.error.motion", role: "secondary")
        label.textColor = SettingsNativeStyle.color(.warning)
        let retry = makeButton("重试保存这次参数", id: "layout.retry.motion") { [weak self] in self?.dispatch(.settings(.retry(.layout))) }
        let stack = SettingsNativeStyle.stack([label, retry], spacing: 7)
        stack.identifier = .init("settings.center.layout.error.motion")
        return stack
    }
}

@MainActor
extension RiftSettingsCenterController {
    func makeButton(_ title: String, id: String, action: @escaping () -> Void) -> NSButton {
        let button = SettingsNativeStyle.button(title)
        configure(button, id: id, action: action)
        button.refusesFirstResponder = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return button
    }
    func configure(_ control: NSControl, id: String, action: @escaping () -> Void) {
        control.identifier = .init("settings.center.\(id)")
        control.target = self; control.action = #selector(invoked(_:))
        controls[id] = control; handlers[ObjectIdentifier(control)] = action
    }
    func nativeSwitch(_ title: String, id: String, action: @escaping (Bool) -> Void) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.setAccessibilityLabel(title)
        configure(toggle, id: id) { [weak toggle] in guard let toggle else { return }; action(toggle.state == .on) }
        toggle.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return toggle
    }
    func popup(_ label: String, id: String, titles: [String], action: @escaping (NSPopUpButton) -> Void) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: titles); popup.font = .systemFont(ofSize: 13)
        popup.setAccessibilityLabel(label)
        configure(popup, id: id) { [weak popup] in guard let popup else { return }; action(popup) }
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 144).isActive = true
        popup.widthAnchor.constraint(lessThanOrEqualToConstant: 228).isActive = true
        popup.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return popup
    }
    func textField(id: String, accessibility: String) -> NSTextField {
        let field = NSTextField(string: "")
        field.identifier = .init("settings.center.\(id)")
        field.delegate = self
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.alignment = .right
        field.setAccessibilityLabel(accessibility)
        field.widthAnchor.constraint(equalToConstant: 84).isActive = true
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        controls[id] = field
        return field
    }
    func namedLabel(_ id: String, role: String = "body") -> NSTextField {
        let label = SettingsNativeStyle.label("", role: role)
        label.identifier = .init("settings.center.\(id)")
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        labels[id] = label
        return label
    }
    func buttonRow(_ views: [NSView]) -> NSStackView { SettingsNativeStyle.stack(views, vertical: false, spacing: 9) }
    func row(_ title: String, detail: String, control: NSView) -> NSStackView {
        let copy = SettingsNativeStyle.stack([SettingsNativeStyle.label(title, role: "rowTitle"),
                                             SettingsNativeStyle.label(detail, role: "caption")], spacing: 3)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = SettingsNativeStyle.stack([copy, control], vertical: false, spacing: 18)
        stack.distribution = .fill
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return stack
    }
    func card(_ views: [NSView]) -> NSView {
        let card = SettingsNativeStyle.card()
        let content = SettingsNativeStyle.stack(views, spacing: 13)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15)
        ])
        for view in views where !(view is NSButton) { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        return card
    }
    func disclosure(_ title: String, id: String, content: NSView) -> NSView {
        let button = makeButton(title, id: "disclosure.\(id)") { [weak self] in
            guard let self, let item = disclosures[id] else { return }
            let expand = item.content.isHidden
            item.content.isHidden = !expand
            item.button.state = expand ? .on : .off
            item.button.image = NSImage(systemSymbolName: expand ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
            item.button.setAccessibilityValue(expand ? "已展开" : "已折叠")
            window.recalculateKeyViewLoop()
        }
        button.bezelStyle = .inline; button.isBordered = false; button.setButtonType(.pushOnPushOff)
        button.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        button.imagePosition = .imageLeading; button.alignment = .left
        button.setAccessibilityLabel(title); button.setAccessibilityValue("已折叠")
        content.isHidden = true
        let stack = SettingsNativeStyle.stack([button, content], spacing: 12)
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        // The disclosure's body owns stable fields even while collapsed.
        if let rows = content as? NSStackView {
            for row in rows.arrangedSubviews where !(row is NSButton) { row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        }
        disclosures[id] = (button, content)
        return stack
    }
    func numericRow(_ key: SettingsField, title: String, unit: String,
                    range: ClosedRange<Double>? = nil, step: Double? = nil) -> NSView {
        let field = textField(id: "field.\(key.rawValue)", accessibility: "\(title)（\(unit)）")
        numericFields[key] = field
        var valueControls: [NSView] = []
        if let range {
            let slider = NSSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
            slider.setAccessibilityLabel(title)
            configure(slider, id: "slider.\(key.rawValue)") { [weak self, weak slider] in
                guard let self, let slider else { return }
                window.makeFirstResponder(slider)
                let value = step.map { (slider.doubleValue / $0).rounded() * $0 } ?? slider.doubleValue
                let text = value.rounded() == value ? String(Int(value)) : String(value)
                model.setDraftText(text, for: key)
                refreshDraftPresentation()
            }
            if step != nil { slider.numberOfTickMarks = Int(range.upperBound - range.lowerBound) + 1; slider.allowsTickMarkValuesOnly = true }
            slider.isContinuous = true
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 85).isActive = true
            slider.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
            numericSliders[key] = slider; valueControls.append(slider)
        }
        valueControls.append(field); valueControls.append(SettingsNativeStyle.label(unit, role: "secondary"))
        return row(title, detail: "", control: buttonRow(valueControls))
    }
    func domainError(_ domain: SettingsDomain) -> NSView {
        let label = SettingsNativeStyle.label("", role: "secondary")
        label.textColor = SettingsNativeStyle.color(.warning)
        label.identifier = .init("settings.center.error.\(domain.rawValue)")
        let retry = makeButton("重试保存这次选择", id: "retry.\(domain.rawValue)") { [weak self] in self?.dispatch(.settings(.retry(domain))) }
        let stack = SettingsNativeStyle.stack([label, retry], spacing: 6)
        stack.isHidden = true
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        errorRows[domain] = stack; errorLabels[domain] = label; retryButtons[domain] = retry
        return stack
    }
}
