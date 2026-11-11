import AppKit
import RiftletCapture

extension RiftTrayFavoriteChoice {
    static let menuChoices: [Self] = [.automatic, .empty] + ScreenshotMode.allCases.map(Self.mode) + [.unsupported]
    var menuTitle: String {
        switch self {
        case .automatic: return "自动"
        case .empty: return "留空"
        case .mode(.window): return "窗口"
        case .mode(.region): return "区域"
        case .mode(.fullScreen): return "全屏"
        case .unsupported: return "当前版本不支持"
        }
    }
}

@MainActor
extension RiftSettingsCenterController {
    func buildPages() {
        makePage(.display, views: displayContent())
        makePage(.capture, views: captureContent())
        makePage(.history, views: historyContent())
        makePage(.help, views: helpContent())
    }

    private func makePage(_ page: SettingsPage, views: [NSView]) {
        let document = RiftVisualStyle.documentStack(views, spacing: 0)
        document.identifier = .init("settings.center.page.\(page.rawValue)")
        document.edgeInsets = NSEdgeInsets(top: 15, left: 30, bottom: 22, right: 30)
        document.translatesAutoresizingMaskIntoConstraints = false
        for view in views { view.widthAnchor.constraint(equalTo: document.widthAnchor, constant: -60).isActive = true }
        pageWidthConstraints[page] = document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        pages[page] = document
    }

    func displayContent() -> [NSView] {
        geometryPreview.identifier = .init("settings.center.layoutPreview")
        geometryPreview.heightAnchor.constraint(equalToConstant: 115).isActive = true
        let forms = RiftDesktopForm.allCases
        let form = segmented("桌面形态", id: "desktopForm", titles: forms.map(\.title)) { [weak self] index in
            guard forms[index].isAvailable else { return }
            self?.dispatch(.settings(.selectDesktopForm(forms[index])))
        }
        for (i, candidate) in forms.enumerated() where !candidate.isAvailable {
            form.setEnabled(false, forSegment: i)
            form.setToolTip("风铃设计待确认", forSegment: i)
        }
        let placement = popup("屏幕边缘", id: "placement", titles: RiftPlacement.allCases.map(\.title)) { [weak self] popup in
            guard RiftPlacement.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.settings(.selectPlacement(RiftPlacement.allCases[popup.indexOfSelectedItem])))
        }
        for (index, option) in RiftPlacement.allCases.enumerated() {
            placement.item(at:index)?.identifier = .init("settings.center.placement." + option.rawValue)
        }
        placement.autoenablesItems = false
        placement.addItem(withTitle: "旧版位置")
        placement.lastItem?.isEnabled = false
        let display = popup("显示器", id: "display", titles: []) { [weak self] popup in
            guard let number = popup.selectedItem?.representedObject as? NSNumber else { return }
            self?.dispatch(.settings(.selectDisplay(number.uint32Value)))
        }
        display.menu?.delegate = self
        let theme = popup("托盘材质", id: "trayTheme", titles: RiftTrayTheme.allCases.map(\.title)) { [weak self] popup in
            guard RiftTrayTheme.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.settings(.selectTrayTheme(RiftTrayTheme.allCases[popup.indexOfSelectedItem])))
        }
        trayTintSettings = group([
            numericRow(.trayTintHue, title: "玻璃色调", unit: "°", range: 0...360, step: 1),
            numericRow(.trayTintStrength, title: "色彩强度", unit: "%", range: 0...100, step: 1)
        ])
        traySettings = group([
            row("托盘材质", control: theme), domainError(.trayTheme), trayTintSettings!,
            numericRow(.trayOcclusion, title: "缩略图遮挡", unit: "%", range: 0...90)
        ])
        let appearance = popup("窗口外观", id: "appearance", titles: SettingsAppearanceChoice.allCases.map(\.title)) { [weak self] popup in
            guard SettingsAppearanceChoice.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.appearance(SettingsAppearanceChoice.allCases[popup.indexOfSelectedItem]))
        }
        let detailed = group([
            numericRow(.hiddenFraction, title: "藏入边缘", unit: "%", range: 0...90),
            numericRow(.outerInset, title: "边缘内缩", unit: "pt", range: 0...256),
            numericRow(.fitWidth, title: "缩略图最大宽度", unit: "pt"),
            numericRow(.fitHeight, title: "缩略图最大高度", unit: "pt"),
            numericRow(.rowPitch, title: "排列间距", unit: "pt"),
            numericRow(.numberFontSize, title: "编号字号", unit: "pt")
        ])
        legacyFieldRow = numericRow(.firstCenterFromTop, title: "旧版距顶部位置", unit: "pt")
        let fine = group([
            numericRow(.numberGap, title: "编号间距", unit: "pt"),
            numericRow(.leftPadding, title: "行内留白", unit: "pt"),
            numericRow(.minimumHitWidth, title: "最小行宽", unit: "pt"),
            numericRow(.minimumHitHeight, title: "最小行高", unit: "pt"), legacyFieldRow!
        ])
        let advanced = group([
            namedLabel("layoutPreview.detail", role: "caption"),
            disclosure("详细自定义", id: "display.details", content: detailed),
            disclosure("精细参数", id: "display.fine", content: fine),
            makeButton("恢复布局默认值", id: "layout.defaults.display") { [weak self] in self?.replaceDrafts(.restoreDefaults(.display)) }
        ] + motionContent() + [namedLabel("accessibility", role:"caption")])
        return [
            geometryPreview,
            row("桌面形态", detail: "风铃设计待确认。", control: form), domainError(.desktopForm),
            row("屏幕边缘", control: placement), domainError(.placement),
            row("显示器", control: display), namedLabel("display.detail", role: "caption"), domainError(.display),
            makeButton("回到已选显示器", id: "display.restore") { [weak self] in self?.dispatch(.restorePreferredDisplay) },
            traySettings!, numericRow(.visibleCountPreference, title: "可见截图", unit: "张", range: 1...10, step: 1),
            row("窗口外观", control: appearance), namedLabel("appearance.detail", role: "caption"),
            makeButton("重试保存外观", id: "appearance.retry") { [weak self] in self?.dispatch(.retryAppearance) },
            disclosure("高级布局与动效", id: "display.advanced", content: advanced), layoutSaveArea(for: .display)
        ]
    }

    private func trayFavoriteSettings() -> NSView {
        var rows: [NSView] = [namedLabel("tray.favorites.detail", role: "caption")]
        let choices = RiftTrayFavoriteChoice.menuChoices
        for slot in RiftTrayFavoriteSlot.allCases {
            let title = "常用键 \(slot.rawValue)"
            let control = popup(title, id: slot.settingsDomain.rawValue, titles: choices.map(\.menuTitle)) { [weak self] popup in
                let index = popup.indexOfSelectedItem
                guard choices.indices.contains(index), choices[index] != .unsupported else { return }
                self?.dispatch(.settings(.selectTrayFavorite(slot, choices[index])))
            }
            control.autoenablesItems = false
            control.lastItem?.isEnabled = false
            rows.append(row(title, control: control))
            rows.append(domainError(slot.settingsDomain))
        }
        return group(rows)
    }

    func captureContent() -> [NSView] {
        let shortcuts = NSStackView()
        shortcuts.distribution = .fillEqually
        for (keys, title) in [("⇧ ⌘ 3","全屏"),("⇧ ⌘ 4","区域"),("⇧ ⌘ 5","截图工具栏")] {
            let keyLabel = NSTextField(labelWithString: keys)
            keyLabel.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
            let column = SettingsNativeStyle.stack([keyLabel,SettingsNativeStyle.label(title, role: "caption")], spacing: 5)
            column.alignment = .centerX
            shortcuts.addArrangedSubview(column)
        }
        shortcuts.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let entry = nativeSwitch("显示内置截图入口", id: "entry") { [weak self] in self?.dispatch(.settings(.setEntryEnabled($0))) }
        let modes: [ScreenshotMode] = [.window, .region, .fullScreen]
        let mode = segmented("默认截图方式", id: "captureMode", titles: ["窗口","区域","全屏"]) { [weak self] in
            self?.dispatch(.settings(.setCaptureMode(modes[$0])))
        }
        trayFavorites = disclosure("自定义三个常用键", id: "tray.favorites", content: trayFavoriteSettings())
        captureOptions = group([
            row("默认截图方式", control: mode), domainError(.captureMode), trayFavorites!,
            disclosure("截图权限与操作", id: "capture.session", content: group([
                namedLabel("screen.capture", role: "caption"),
                makeButton("开始内置截图…", id: "capture.start") { [weak self] in self?.dispatch(.capture) }
            ]))
        ])
        return [section("macOS 系统截图"), shortcuts,
                row("截图保存位置", control: buttonRow([
                    makeButton("打开位置", id: "source.open.capture") { [weak self] in self?.dispatch(.openSource) },
                    makeButton("查看访问状态", id: "permissions.capture") { [weak self] in self?.navigate(to: .help) }
                ])), namedLabel("sourcePath.capture", role:"caption"), namedLabel("source.capture", role:"caption"),
                makeButton("允许访问此位置…", id: "source.access.capture") { [weak self] in self?.dispatch(.chooseSourceAccess) },
                section("Riftlet 内置截图"),
                row("显示截图入口", detail:"在桌面边缘开始窗口、区域或全屏截图。", control: entry),
                domainError(.entry), captureOptions!]
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
        return [group([
            row("截图到达边缘时", detail: "选择立即保存。点击下方按钮预览。", control: mode), domainError(.arrival),
            namedLabel("motion.detail", role: "secondary"), arrivalPreview,
            makeButton("预览入缝", id: "arrival.preview") { [weak self] in self?.playArrival() }
        ]), group([
            SettingsNativeStyle.label("上传开始后的快速吞噬", role: "heading"),
            SettingsNativeStyle.label("独立于入缝偏好；预览只播放示意图，不读取或附加截图。", role: "secondary"),
            swallowPreview, makeButton("预览吞噬", id: "swallow.preview") { [weak self] in self?.playSwallow() },
            namedLabel("motion.effective", role: "caption"), disclosure("调整动效时长", id: "motion.fine", content: fine),
            makeButton("恢复动效默认值", id: "layout.defaults.motion") { [weak self] in self?.replaceDrafts(.restoreDefaults(.motion)) }
        ]), layoutSaveArea(for: .motion)]
    }

    static var archivePresetMinutes: [Int] { [1, Int(QueueArchivePolicy.defaultMinutes), 5, 10] }

    func historyContent() -> [NSView] {
        let collection = nativeSwitch("收录系统截图", id: "paused") { [weak self] in self?.dispatch(.settings(.setCollectionPaused(!$0))) }
        let visibility = nativeSwitch("显示桌面截图", id: "hidden") { [weak self] in self?.dispatch(.settings(.setHidden(!$0))) }
        let login = nativeSwitch("登录时启动 Riftlet", id: "login") { [weak self] in self?.dispatch(.loginEnabled($0)) }
        let displayStyle = segmented("历史样式", id: "history.displayStyle", titles: ["列表","图像网格"]) { [weak self] in
            self?.dispatch(.historyDisplayStyle(HistoryDisplayStyle.allCases[$0]))
        }
        let choices = Self.archivePresetMinutes
        let preset = popup("自动归档时限", id: "archive.preset", titles: ["关闭"] + choices.map { "\($0) 分钟" } + ["自定义…"]) { [weak self] popup in
            guard let self, finishEditingForReplacement() else { return }
            let index = popup.indexOfSelectedItem
            archiveCustom = index == choices.count + 1
            if index == 0 {
                model.setArchiveDraftText(nil)
            } else if choices.indices.contains(index - 1) {
                model.setArchiveDraftText(String(choices[index - 1]))
            } else if archiveCustom && model.archiveIsDisabled {
                model.setArchiveDraftText(String(QueueArchivePolicy.defaultMinutes))
            }
            refreshDraftPresentation()
            window.recalculateKeyViewLoop()
            if archiveCustom { window.makeFirstResponder(archiveField) }
        }
        archiveField = textField(id: "archive.minutes", accessibility: "自定义归档分钟数")
        archiveCustomRow = row("自定义时限", detail: "可输入 1–10 分钟，支持小数。", control: buttonRow([archiveField, SettingsNativeStyle.label("分钟", role: "secondary")]))
        let archive = group([
            row("闲置后归档", control:preset),
            archiveCustomRow, namedLabel("archive.detail", role: "secondary"), domainError(.archive),
            buttonRow([
                makeButton("保存归档时限", id: "archive.save") { [weak self] in self?.flushEditor(); self?.dispatch(.settings(.applyArchive)) },
                makeButton("放弃更改", id: "archive.discard") { [weak self] in self?.replaceDrafts(.discardArchive) }
            ])
        ])
        let storage = group([
            namedLabel("storage", role: "secondary"), buttonRow([
                makeButton("检查用量", id: "storage.check") { [weak self] in self?.dispatch(.checkStorage) },
                makeButton("在 Finder 中显示", id: "storage.reveal") { [weak self] in self?.dispatch(.revealDataFolder) },
                makeButton("收起全部微图…", id: "history.clear") { [weak self] in self?.dispatch(.clearVisible) }
            ]), namedLabel("history.detail", role: "caption")
        ])
        return [section("日常使用"),
                row("收录系统截图", detail:"暂停收录后，已收录的截图仍可使用。", control:collection), domainError(.collection),
                row("显示桌面截图", detail:"隐藏桌面截图时，仍按收录设置工作。", control:visibility), domainError(.visibility),
                namedLabel("status.title", role:"rowTitle"), namedLabel("status.detail", role:"caption"),
                row("登录时启动 Riftlet", control:login), namedLabel("login.detail", role:"caption"),
                buttonRow([makeButton("重试这次选择", id:"login.retry") { [weak self] in self?.dispatch(.retryLogin) },
                           makeButton("打开登录项设置…", id:"login.system") { [weak self] in self?.dispatch(.openLoginSettings) }]),
                section("本机历史"),
                row("浏览历史", detail:"预览、还原或移除已有截图。", control:makeButton("打开历史…", id:"history.open") { [weak self] in self?.dispatch(.openHistory) }),
                row("历史样式", control:displayStyle), archive, disclosure("存储与恢复",id:"restore-info",content:storage)]
    }

    func helpContent() -> [NSView] {
        let folder = group([
            namedLabel("source.help", role:"secondary"), namedLabel("sourcePath.help", role:"caption"),
            buttonRow([
                makeButton("允许访问此位置…", id:"source.access.help") { [weak self] in self?.dispatch(.chooseSourceAccess) },
                makeButton("文件访问设置…", id:"source.privacy") { [weak self] in self?.dispatch(.openFilePrivacy) }
            ])
        ])
        let chrome = group([
            namedLabel("automation", role:"secondary"), namedLabel("attachment", role:"secondary"),
            makeButton("检查 Chrome 权限…", id:"automation.request") { [weak self] in self?.dispatch(.requestAutomation) }
        ])
        let screen = group([
            namedLabel("screen.help", role:"secondary"),
            makeButton("屏幕录制设置…", id:"screen.privacy") { [weak self] in self?.dispatch(.openScreenRecordingPrivacy) }
        ])
        let about = group([
            namedLabel("version", role:"secondary"), namedLabel("support", role:"caption"),
            namedLabel("diagnostics", role:"caption"),
            buttonRow([
                makeButton("重新读取配置", id:"configuration.reload") { [weak self] in self?.dispatch(.reloadConfiguration) },
                makeButton("打开配置文件…", id:"configuration.open") { [weak self] in self?.dispatch(.openConfiguration) },
                makeButton("反馈与建议…", id:"feedback.help") { [weak self] in self?.dispatch(.openFeedback) }
            ])
        ])
        let recheck = makeButton("重新检查", id:"recheck") { [weak self] in self?.dispatch(.recheck) }
        recheck.bezelStyle = .inline
        return [section("访问权限", trailing: recheck),
            accessRow("截图文件夹", symbol:"folder", detail:"收录保存到系统截图目录的图片。", id:"folder", content:folder),
            accessRow("Chrome 自动化", symbol:"globe", detail:"点击桌面截图时，附加到当前 ChatGPT 草稿。", id:"chrome", content:chrome),
            accessRow("屏幕录制", symbol:"rectangle.dashed", detail:"用于 Riftlet 的窗口、区域和全屏截图。", id:"screen", content:screen),
            section("使用帮助"),
            row("开始使用", detail:"从截取第一张图片到点击附加。", control:makeButton("查看引导…", id:"guide.help") { [weak self] in self?.dispatch(.openOnboarding) }),
            disclosure("关于与诊断", id:"diagnostics", content:about)]
    }

    private func accessRow(_ title:String, symbol:String, detail:String, id:String, content:NSView) -> NSView {
        let image = NSImageView(image:NSImage(systemSymbolName:symbol,accessibilityDescription:nil) ?? NSImage())
        image.contentTintColor = SettingsNativeStyle.color(.accentInk)
        image.widthAnchor.constraint(equalToConstant: 19).isActive = true
        let state = namedLabel("access." + id, role:"caption")
        let button = makeButton("查看",id:"access." + id) { [weak self, weak content] in
            guard let content else { return }
            content.isHidden.toggle()
            (self?.controls["access." + id] as? NSButton)?.title = content.isHidden ? "查看":"收起"
            self?.window.recalculateKeyViewLoop()
        }
        button.bezelStyle = .inline
        button.setAccessibilityLabel("查看" + title + "详情")
        let line = row(title,detail:detail,control:buttonRow([state,button]))
        let combined = SettingsNativeStyle.stack([image,line], vertical:false, spacing:12)
        content.isHidden = true
        return group([combined,content])
    }

    func layoutSaveArea(for page: SettingsDraftPage) -> NSView {
        let suffix = page == .display ? "display" : "motion"
        return group([
            namedLabel("layout.detail.\(suffix)", role: "secondary"),
            // Both pages project the same domain without sharing a view parent.
            page == .display ? domainError(.layout) : alternateLayoutError(),
            buttonRow([
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
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
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
    func row(_ title: String, detail: String = "", control: NSView) -> NSStackView {
        var copyViews = [SettingsNativeStyle.label(title, role: "rowTitle")]
        if !detail.isEmpty { copyViews.append(SettingsNativeStyle.label(detail, role: "caption")) }
        let copy = SettingsNativeStyle.stack(copyViews, spacing: 3)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = SettingsNativeStyle.stack([copy, NSView(), control], vertical: false, spacing: 8)
        stack.distribution = .fill
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: detail.isEmpty ? 36 : 48).isActive = true
        let divider = NSBox()
        divider.boxType = .separator
        let outer = SettingsNativeStyle.stack([stack,divider], spacing: 0)
        stack.widthAnchor.constraint(equalTo:outer.widthAnchor).isActive = true
        divider.widthAnchor.constraint(equalTo:outer.widthAnchor).isActive = true
        divider.heightAnchor.constraint(equalToConstant:1).isActive = true
        return outer
    }
    func group(_ views: [NSView]) -> NSStackView {
        let group = SettingsNativeStyle.stack(views, spacing: 2)
        for view in views where !(view is NSButton) {
            view.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        }
        return group
    }
    func section(_ title:String, trailing:NSView? = nil) -> NSView {
        let label = SettingsNativeStyle.label(title,role:"rowTitle")
        label.textColor = SettingsNativeStyle.color(.accentInk)
        label.font = .systemFont(ofSize:12,weight:.semibold)
        let group = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:group.leadingAnchor), label.bottomAnchor.constraint(equalTo:group.bottomAnchor,constant:-6),
                                     group.heightAnchor.constraint(equalToConstant:34)])
        if let trailing {
            trailing.translatesAutoresizingMaskIntoConstraints = false
            group.addSubview(trailing)
            NSLayoutConstraint.activate([trailing.trailingAnchor.constraint(equalTo:group.trailingAnchor),
                                         trailing.centerYAnchor.constraint(equalTo:label.centerYAnchor)])
        }
        return group
    }

    func segmented(_ title:String,id:String,titles:[String],select:@escaping (Int)->Void) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels:titles,trackingMode:.selectOne,target:nil,action:nil)
        control.segmentStyle = .rounded
        control.setAccessibilityLabel(title)
        configure(control,id:id) { [weak control] in
            guard let index = control?.selectedSegment, titles.indices.contains(index) else { return }
            select(index)
        }
        return control
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
            if let step {
                let tickCount = Int((range.upperBound - range.lowerBound) / step) + 1
                if tickCount <= 10 {
                    slider.numberOfTickMarks = tickCount
                    slider.allowsTickMarkValuesOnly = true
                }
            }
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
