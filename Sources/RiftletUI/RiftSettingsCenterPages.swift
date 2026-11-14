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
        makePage(.general, views: generalContent())
        makePage(.help, views: helpContent())
    }

    private func makePage(_ page: SettingsPage, views: [NSView]) {
        let document = RiftVisualStyle.documentStack(views, spacing: 0)
        document.identifier = .init("settings.center.page.\(page.rawValue)")
        document.edgeInsets = NSEdgeInsets(top: 15, left: 24, bottom: 22, right: 24)
        document.translatesAutoresizingMaskIntoConstraints = false
        for view in views { view.widthAnchor.constraint(equalTo: document.widthAnchor, constant: -48).isActive = true }
        pageWidthConstraints[page] = document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        pages[page] = document
    }

    func preferenceRecoveryRow(_ domain: SettingsPreferenceDomain) -> NSView {
        let key = "recovery." + domain.rawValue
        let button = makeButton(domain == .layout ? "恢复默认布局" : "恢复默认归档时限", id: key + ".restore") { [weak self] in
            self?.dispatch(.restorePreference(domain))
        }
        let stack = SettingsNativeStyle.stack([namedLabel(key, role: "caption"), button], spacing: 4)
        stack.isHidden = true
        preferenceRecoveryRows[domain] = stack
        return stack
    }

    func displayContent() -> [NSView] {
        geometryPreview.identifier = .init("settings.center.layoutPreview")
        geometryPreview.heightAnchor.constraint(equalToConstant: 92).isActive = true
        let forms = RiftDesktopForm.allCases
        let form = segmented("桌面形态", id: "desktopForm", titles: forms.map(\.title)) { [weak self] index in
            self?.dispatch(.settings(.selectDesktopForm(forms[index])))
        }
        let arrangements = RiftWindChimeArrangement.allCases
        let arrangement = segmented("风铃排列", id: "windChimeArrangement", titles: arrangements.map(\.title)) { [weak self] index in
            self?.dispatch(.settings(.selectWindChimeArrangement(arrangements[index])))
        }
        windChimeSettings = row("风铃排列", control: arrangement)
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
        traySettings = group([row("托盘材质", control: theme), domainError(.trayTheme), trayTintSettings!])
        trayOcclusionRow = numericRow(.trayOcclusion, title: "缩略图遮挡", unit: "%", range: 0...90)
        slitInsetFraction = numericRow(.hiddenFraction, title: "藏入边缘", unit: "%", range: 0...90)
        commonEdgeSettings = group([slitInsetFraction!, numericRow(.outerInset, title: "边缘内缩", unit: "pt", range: 0...256)])
        windChimeLineSetting = numericRow(.windChimeLineInset, title: "连线距边", unit: "pt", range: 0...256)
        let arrival = popup("出现动效", id: "arrival", titles: ArrivalMotionMode.allCases.map(\.title)) { [weak self] popup in
            guard ArrivalMotionMode.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.settings(.setArrival(ArrivalMotionMode.allCases[popup.indexOfSelectedItem])))
        }
        let advanced = group([
            numericRow(.visibleCountPreference, title: "每页截图上限", unit: "张", range: 1...10, step: 1),
            commonEdgeSettings!, windChimeLineSetting!, trayOcclusionRow!,
            row("出现动效", control: arrival), domainError(.arrival), namedLabel("motion.detail", role: "caption"),
            makeButton("恢复本形态的默认数值", id: "layout.defaults.display") { [weak self] in
                self?.restoreVisibleDefaults()
            }
        ])
        return [
            preferenceRecoveryRow(.layout), row("桌面形态", control: form), domainError(.desktopForm),
            row("屏幕边缘", control: placement), domainError(.placement),
            row("显示器", control: display), namedLabel("display.detail", role: "caption"), domainError(.display),
            makeButton("回到已选显示器", id: "display.restore") { [weak self] in self?.dispatch(.restorePreferredDisplay) },
            geometryPreview, namedLabel("layoutPreview.detail", role: "caption"),
            windChimeSettings!, domainError(.windChimeArrangement), traySettings!,
            disclosure("高级外观", id: "display.advanced", content: advanced), domainError(.layout),
            namedLabel("diagnostics", role: "caption")
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
        let entry = nativeSwitch("显示内置截图入口", id: "entry") { [weak self] in self?.dispatch(.settings(.setEntryEnabled($0))) }
        let modes: [ScreenshotMode] = [.window, .region, .fullScreen]
        let mode = segmented("默认截图方式", id: "captureMode", titles: ["窗口","区域","全屏"]) { [weak self] in
            self?.dispatch(.settings(.setCaptureMode(modes[$0])))
        }
        trayFavorites = disclosure("自定义三个常用键", id: "tray.favorites", content: trayFavoriteSettings())
        captureOptions = group([
            row("默认截图方式", control: mode), domainError(.captureMode), trayFavorites!,
            namedLabel("screen.capture", role: "caption"),
            makeButton("屏幕录制设置…", id: "screen.privacy") { [weak self] in self?.dispatch(.openScreenRecordingPrivacy) }
        ])
        return [
            section("系统截图"), row("截图文件夹", control: makeButton("在 Finder 中打开", id: "source.open.capture") { [weak self] in self?.dispatch(.openSource) }),
            namedLabel("sourcePath.capture", role:"caption"), namedLabel("source.capture", role:"caption"),
            buttonRow([
                makeButton("允许访问截图文件夹…", id: "source.access.capture") { [weak self] in self?.dispatch(.chooseSourceAccess) },
                makeButton("重新检查", id: "source.recheck.capture") { [weak self] in self?.dispatch(.recheck) }
            ]),
            domainError(.collection), domainError(.visibility),
            row("显示内置截图入口", control: entry), domainError(.entry), captureOptions!,
            section("归档与本机存储"), preferenceRecoveryRow(.archive), archiveSettings(),
            row("本机存储", control: makeButton("检查用量", id: "storage.check") { [weak self] in self?.dispatch(.checkStorage) }),
            namedLabel("storage", role:"caption"),
            makeButton("重新检查本地截图副本", id:"storage.recheckMedia") { [weak self] in self?.dispatch(.recheck) },
            makeButton("打开截图历史…", id:"history.open") { [weak self] in self?.dispatch(.openHistory) },
            namedLabel("history.detail", role:"caption")
        ]
    }

    static var archivePresetMinutes: [Int] { [1, Int(QueueArchivePolicy.defaultMinutes), 5, 10] }

    private func archiveSettings() -> NSView {
        let choices = Self.archivePresetMinutes
        let preset = popup("自动归档时限", id: "archive.preset", titles: ["关闭"] + choices.map { "\($0) 分钟" } + ["自定义…"]) { [weak self] popup in
            // Ending the previous editor can synchronously refresh this popup.
            let index = popup.indexOfSelectedItem
            guard let self, finishEditingForReplacement() else { return }
            archiveCustom = index == choices.count + 1
            if archiveCustom {
                if model.archiveIsDisabled { model.setArchiveDraftText(String(QueueArchivePolicy.defaultMinutes)) }
            } else {
                let text = choices.indices.contains(index - 1) ? String(choices[index - 1]) : nil
                model.setArchiveDraftText(text)
                dispatch(.settings(.commitArchive(text)))
            }
            refreshDraftPresentation()
            window.recalculateKeyViewLoop()
            if archiveCustom { window.makeFirstResponder(archiveField) }
        }
        archiveField = textField(id: "archive.minutes", accessibility: "自定义归档分钟数")
        archiveCustomRow = row("自定义时限", detail: "1–10 分钟，可用小数。", control: buttonRow([archiveField, SettingsNativeStyle.label("分钟", role: "secondary")]))
        return group([
            row("闲置后归档", detail:"归档后可在截图历史中找回。", control:preset), archiveCustomRow, domainError(.archive)
        ])
    }

    func generalContent() -> [NSView] {
        let login = nativeSwitch("登录时启动 Riftlet", id: "login") { [weak self] in self?.dispatch(.loginEnabled($0)) }
        let appearance = popup("窗口外观", id: "appearance", titles: SettingsAppearanceChoice.allCases.map(\.title)) { [weak self] popup in
            guard SettingsAppearanceChoice.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.appearance(SettingsAppearanceChoice.allCases[popup.indexOfSelectedItem]))
        }
        return [
            row("登录时启动 Riftlet", control:login), namedLabel("login.detail", role:"caption"),
            buttonRow([makeButton("重试", id:"login.retry") { [weak self] in self?.dispatch(.retryLogin) },
                       makeButton("打开登录项设置…", id:"login.system") { [weak self] in self?.dispatch(.openLoginSettings) }]),
            row("窗口外观", control: appearance), namedLabel("appearance.detail", role: "caption"),
            makeButton("重试保存外观", id: "appearance.retry") { [weak self] in self?.dispatch(.retryAppearance) },
            section("软件更新"), row("当前版本", control: namedLabel("version", role:"secondary")),
            makeButton("检查更新…", id: "updates.check") { [weak self] in self?.dispatch(.checkForUpdates) },
            row("每天检查更新", control: nativeSwitch("每天检查更新", id: "updates.automatic") { [weak self] enabled in self?.dispatch(.automaticUpdateChecks(enabled)) }),
            namedLabel("updates.failure", role: "caption"),
            makeButton("从官网下载…", id: "updates.website") { [weak self] in self?.dispatch(.openDownloadWebsite) }
        ]
    }

    func helpContent() -> [NSView] {
        [
            section("Chrome 连接"), namedLabel("access.chrome", role: "rowTitle"), namedLabel("automation", role: "secondary"),
            namedLabel("chrome.menu", role: "caption"), namedLabel("attachment", role: "caption"),
            makeButton("检查 Chrome 权限…", id:"automation.request") { [weak self] in self?.dispatch(.requestAutomation) },
            makeButton("检查 Chrome 连接", id:"chrome.check") { [weak self] in self?.dispatch(.checkChromeConnection) },
            section("使用帮助"), SettingsNativeStyle.label("截一张图，点桌面边缘的缩略图，即可将图片加入当前 Chrome 的 ChatGPT 草稿。确认后由你发送。", role: "secondary"),
            makeButton("重新查看引导…", id:"guide.help") { [weak self] in self?.dispatch(.openOnboarding) },
            makeButton("反馈与建议…", id:"feedback.help") { [weak self] in self?.dispatch(.openFeedback) },
            disclosure("诊断", id:"diagnostics", content: group([namedLabel("support", role:"caption"),
                makeButton("在 Finder 中显示数据目录…", id:"storage.reveal") { [weak self] in self?.dispatch(.revealDataFolder) }
            ]))
        ]
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
                dispatch(.settings(.commitField(key, text)))
            }
            if let step {
                let tickCount = Int((range.upperBound - range.lowerBound) / step) + 1
                if tickCount <= 10 {
                    slider.numberOfTickMarks = tickCount
                    slider.allowsTickMarkValuesOnly = true
                }
            }
            slider.isContinuous = false
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
