import AppKit
import RiftletCapture

extension RiftTrayFavoriteChoice {
    static let menuChoices: [Self] = [.automatic, .empty] + ScreenshotMode.allCases.map(Self.mode) + [.unsupported]
    var menuTitle: String {
        switch self {
        case .automatic: return ProductCopy.text("自动", "Automatic")
        case .empty: return ProductCopy.text("留空", "Empty")
        case .mode(.window): return ProductCopy.text("窗口", "Window")
        case .mode(.region): return ProductCopy.text("区域", "Area")
        case .mode(.fullScreen): return ProductCopy.text("全屏", "Full Screen")
        case .unsupported: return ProductCopy.text("当前版本不支持", "Unsupported in this version")
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
        let button = makeButton(domain == .layout ? ProductCopy.text("恢复默认布局", "Restore Default Layout") : ProductCopy.text("恢复默认归档时限", "Restore Default Archive Time"), id: key + ".restore") { [weak self] in
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
        let form = segmented(ProductCopy.text("桌面形态", "Desktop Form"), id: "desktopForm", titles: forms.map(\.title)) { [weak self] index in
            self?.dispatch(.settings(.selectDesktopForm(forms[index])))
        }
        let arrangements = RiftWindChimeArrangement.allCases
        let arrangement = segmented(ProductCopy.text("风铃排列", "Wind Chime Layout"), id: "windChimeArrangement", titles: arrangements.map(\.title)) { [weak self] index in
            self?.dispatch(.settings(.selectWindChimeArrangement(arrangements[index])))
        }
        windChimeSettings = row(ProductCopy.text("风铃排列", "Wind Chime Layout"), control: arrangement)
        let placement = popup(ProductCopy.text("屏幕边缘", "Screen Edge"), id: "placement", titles: RiftPlacement.allCases.map(\.title)) { [weak self] popup in
            guard RiftPlacement.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.settings(.selectPlacement(RiftPlacement.allCases[popup.indexOfSelectedItem])))
        }
        for (index, option) in RiftPlacement.allCases.enumerated() {
            placement.item(at:index)?.identifier = .init("settings.center.placement." + option.rawValue)
        }
        placement.autoenablesItems = false
        placement.addItem(withTitle: ProductCopy.text("旧版位置", "Previous Position"))
        placement.lastItem?.isEnabled = false
        let display = popup(ProductCopy.text("显示器", "Display"), id: "display", titles: []) { [weak self] popup in
            guard let number = popup.selectedItem?.representedObject as? NSNumber else { return }
            self?.dispatch(.settings(.selectDisplay(number.uint32Value)))
        }
        display.menu?.delegate = self
        let theme = popup(ProductCopy.text("托盘材质", "Tray Material"), id: "trayTheme", titles: RiftTrayTheme.allCases.map(\.title)) { [weak self] popup in
            guard RiftTrayTheme.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.settings(.selectTrayTheme(RiftTrayTheme.allCases[popup.indexOfSelectedItem])))
        }
        trayTintSettings = group([
            numericRow(.trayTintHue, title: ProductCopy.text("玻璃色调", "Glass Hue"), unit: "°", range: 0...360, step: 1),
            numericRow(.trayTintStrength, title: ProductCopy.text("色彩强度", "Color Strength"), unit: "%", range: 0...100, step: 1)
        ])
        traySettings = group([row(ProductCopy.text("托盘材质", "Tray Material"), control: theme), domainError(.trayTheme), trayTintSettings!])
        trayOcclusionRow = numericRow(.trayOcclusion, title: ProductCopy.text("缩略图遮挡", "Thumbnail Overlap"), unit: "%", range: 0...90)
        slitInsetFraction = numericRow(.hiddenFraction, title: ProductCopy.text("藏入边缘", "Hide into Edge"), unit: "%", range: 0...90)
        commonEdgeSettings = group([slitInsetFraction!, numericRow(.outerInset, title: ProductCopy.text("边缘内缩", "Edge Inset"), unit: "pt", range: 0...256)])
        windChimeLineSetting = numericRow(.windChimeLineInset, title: ProductCopy.text("连线距边", "Line Inset"), unit: "pt", range: 0...256)
        let arrival = popup(ProductCopy.text("出现动效", "Arrival Motion"), id: "arrival", titles: ArrivalMotionMode.allCases.map(\.title)) { [weak self] popup in
            guard ArrivalMotionMode.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.settings(.setArrival(ArrivalMotionMode.allCases[popup.indexOfSelectedItem])))
        }
        let advanced = group([
            numericRow(.visibleCountPreference, title: ProductCopy.text("每页截图上限", "Screenshots per Page"), unit: ProductCopy.text("张", "images"), range: 1...10, step: 1),
            commonEdgeSettings!, windChimeLineSetting!, trayOcclusionRow!,
            row(ProductCopy.text("出现动效", "Arrival Motion"), control: arrival), domainError(.arrival), namedLabel("motion.detail", role: "caption"),
            makeButton(ProductCopy.text("恢复本形态的默认数值", "Restore This Form’s Defaults"), id: "layout.defaults.display") { [weak self] in
                self?.restoreVisibleDefaults()
            }
        ])
        return [
            preferenceRecoveryRow(.layout), row(ProductCopy.text("桌面形态", "Desktop Form"), control: form), domainError(.desktopForm),
            row(ProductCopy.text("屏幕边缘", "Screen Edge"), control: placement), domainError(.placement),
            row(ProductCopy.text("显示器", "Display"), control: display), namedLabel("display.detail", role: "caption"), domainError(.display),
            makeButton(ProductCopy.text("回到已选显示器", "Return to Preferred Display"), id: "display.restore") { [weak self] in self?.dispatch(.restorePreferredDisplay) },
            geometryPreview, namedLabel("layoutPreview.detail", role: "caption"),
            windChimeSettings!, domainError(.windChimeArrangement), traySettings!,
            disclosure(ProductCopy.text("高级外观", "Advanced Appearance"), id: "display.advanced", content: advanced), domainError(.layout),
            namedLabel("diagnostics", role: "caption")
        ]
    }

    private func trayFavoriteSettings() -> NSView {
        var rows: [NSView] = [namedLabel("tray.favorites.detail", role: "caption")]
        let choices = RiftTrayFavoriteChoice.menuChoices
        for slot in RiftTrayFavoriteSlot.allCases {
            let title = ProductCopy.text("常用键 \(slot.rawValue)", "Favorite \(slot.rawValue)")
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
        let entry = nativeSwitch(ProductCopy.text("显示内置截图入口", "Show Capture Button"), id: "entry") { [weak self] in self?.dispatch(.settings(.setEntryEnabled($0))) }
        let modes: [ScreenshotMode] = [.window, .region, .fullScreen]
        let mode = segmented(ProductCopy.text("默认截图方式", "Default Capture Mode"), id: "captureMode", titles: [ProductCopy.text("窗口", "Window"),ProductCopy.text("区域", "Area"),ProductCopy.text("全屏", "Full Screen")]) { [weak self] in
            self?.dispatch(.settings(.setCaptureMode(modes[$0])))
        }
        trayFavorites = disclosure(ProductCopy.text("自定义三个常用键", "Customize Three Favorites"), id: "tray.favorites", content: trayFavoriteSettings())
        captureOptions = group([
            row(ProductCopy.text("默认截图方式", "Default Capture Mode"), control: mode), domainError(.captureMode), trayFavorites!,
            namedLabel("screen.capture", role: "caption"),
            makeButton(ProductCopy.text("屏幕录制设置…", "Screen Recording Settings…"), id: "screen.privacy") { [weak self] in self?.dispatch(.openScreenRecordingPrivacy) }
        ])
        return [
            section(ProductCopy.text("系统截图", "System Screenshots")), row(ProductCopy.text("截图文件夹", "Screenshot Folder"), control: makeButton(ProductCopy.text("在 Finder 中打开", "Open in Finder"), id: "source.open.capture") { [weak self] in self?.dispatch(.openSource) }),
            namedLabel("sourcePath.capture", role:"caption"), namedLabel("source.capture", role:"caption"),
            buttonRow([
                makeButton(ProductCopy.text("允许访问截图文件夹…", "Allow Screenshot Folder Access…"), id: "source.access.capture") { [weak self] in self?.dispatch(.chooseSourceAccess) },
                makeButton(ProductCopy.text("重新检查", "Check Again"), id: "source.recheck.capture") { [weak self] in self?.dispatch(.recheck) }
            ]),
            domainError(.collection), domainError(.visibility),
            row(ProductCopy.text("显示内置截图入口", "Show Capture Button"), control: entry), domainError(.entry), captureOptions!,
            section(ProductCopy.text("归档与本机存储", "Archive and Local Storage")), preferenceRecoveryRow(.archive), archiveSettings(),
            row(ProductCopy.text("本机存储", "Local Storage"), control: makeButton(ProductCopy.text("检查用量", "Check Usage"), id: "storage.check") { [weak self] in self?.dispatch(.checkStorage) }),
            namedLabel("storage", role:"caption"),
            makeButton(ProductCopy.text("重新检查本地截图副本", "Check Local Screenshot Copies"), id:"storage.recheckMedia") { [weak self] in self?.dispatch(.recheck) },
            makeButton(ProductCopy.text("打开截图历史…", "Open Screenshot History…"), id:"history.open") { [weak self] in self?.dispatch(.openHistory) },
            namedLabel("history.detail", role:"caption")
        ]
    }

    static var archivePresetMinutes: [Int] { [1, Int(QueueArchivePolicy.defaultMinutes), 5, 10] }

    private func archiveSettings() -> NSView {
        let choices = Self.archivePresetMinutes
        let preset = popup(ProductCopy.text("自动归档时限", "Auto-Archive Time"), id: "archive.preset", titles: [ProductCopy.text("关闭", "Off")] + choices.map { ProductCopy.text("\($0) 分钟", "\($0) min") } + [ProductCopy.text("自定义…", "Custom…")]) { [weak self] popup in
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
        archiveField = textField(id: "archive.minutes", accessibility: ProductCopy.text("自定义归档分钟数", "Custom archive time in minutes"))
        archiveCustomRow = row(ProductCopy.text("自定义时限", "Custom Time"), detail: ProductCopy.text("1–10 分钟，可用小数。", "1–10 minutes. Decimals are allowed."), control: buttonRow([archiveField, SettingsNativeStyle.label(ProductCopy.text("分钟", "min"), role: "secondary")]))
        return group([
            row(ProductCopy.text("闲置后归档", "Archive When Idle"), detail:ProductCopy.text("归档后可在截图历史中找回。", "Find archived screenshots in Screenshot History."), control:preset), archiveCustomRow, domainError(.archive)
        ])
    }

    func generalContent() -> [NSView] {
        let login = nativeSwitch(ProductCopy.text("登录时启动 Riftlet", "Launch Riftlet at Login"), id: "login") { [weak self] in self?.dispatch(.loginEnabled($0)) }
        let appearance = popup(ProductCopy.text("窗口外观", "Window Appearance"), id: "appearance", titles: SettingsAppearanceChoice.allCases.map(\.title)) { [weak self] popup in
            guard SettingsAppearanceChoice.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.appearance(SettingsAppearanceChoice.allCases[popup.indexOfSelectedItem]))
        }
        return [
            row(ProductCopy.text("登录时启动 Riftlet", "Launch Riftlet at Login"), control:login), namedLabel("login.detail", role:"caption"),
            buttonRow([makeButton(ProductCopy.text("重试", "Retry"), id:"login.retry") { [weak self] in self?.dispatch(.retryLogin) },
                       makeButton(ProductCopy.text("打开登录项设置…", "Open Login Items Settings…"), id:"login.system") { [weak self] in self?.dispatch(.openLoginSettings) }]),
            row(ProductCopy.text("窗口外观", "Window Appearance"), control: appearance), namedLabel("appearance.detail", role: "caption"),
            makeButton(ProductCopy.text("重试保存外观", "Retry Saving Appearance"), id: "appearance.retry") { [weak self] in self?.dispatch(.retryAppearance) },
            section(ProductCopy.text("软件更新", "Software Updates")), row(ProductCopy.text("当前版本", "Current Version"), control: namedLabel("version", role:"secondary")),
            makeButton(ProductCopy.text("检查更新…", "Check for Updates…"), id: "updates.check") { [weak self] in self?.dispatch(.checkForUpdates) },
            row(ProductCopy.text("每天检查更新", "Check Daily for Updates"), control: nativeSwitch(ProductCopy.text("每天检查更新", "Check Daily for Updates"), id: "updates.automatic") { [weak self] enabled in self?.dispatch(.automaticUpdateChecks(enabled)) }),
            namedLabel("updates.failure", role: "caption"),
            makeButton(ProductCopy.text("从官网下载…", "Download from Website…"), id: "updates.website") { [weak self] in self?.dispatch(.openDownloadWebsite) }
        ]
    }

    func helpContent() -> [NSView] {
        [
            section(ProductCopy.text("Chrome 连接", "Chrome Connection")), namedLabel("access.chrome", role: "rowTitle"), namedLabel("automation", role: "secondary"),
            namedLabel("chrome.menu", role: "caption"), namedLabel("attachment", role: "caption"),
            makeButton(ProductCopy.text("检查 Chrome 权限…", "Check Chrome Access…"), id:"automation.request") { [weak self] in self?.dispatch(.requestAutomation) },
            makeButton(ProductCopy.text("检查 Chrome 连接", "Check Chrome Connection"), id:"chrome.check") { [weak self] in self?.dispatch(.checkChromeConnection) },
            section(ProductCopy.text("使用帮助", "Getting Help")), SettingsNativeStyle.label(ProductCopy.text("截一张图，点桌面边缘的缩略图，即可将图片加入当前 Chrome 的 ChatGPT 草稿。确认后由你发送。", "Take a screenshot, then click its thumbnail at the edge of your desktop to attach it to your current ChatGPT draft in Chrome. You choose when to send."), role: "secondary"),
            makeButton(ProductCopy.text("重新查看引导…", "Open Setup Guide…"), id:"guide.help") { [weak self] in self?.dispatch(.openOnboarding) },
            makeButton(ProductCopy.text("反馈与建议…", "Send Feedback…"), id:"feedback.help") { [weak self] in self?.dispatch(.openFeedback) },
            disclosure(ProductCopy.text("诊断", "Diagnostics"), id:"diagnostics", content: group([namedLabel("support", role:"caption"),
                makeButton(ProductCopy.text("在 Finder 中显示数据目录…", "Show Data Folder in Finder…"), id:"storage.reveal") { [weak self] in self?.dispatch(.revealDataFolder) }
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
            item.button.setAccessibilityValue(expand ? ProductCopy.text("已展开", "Expanded") : ProductCopy.text("已折叠", "Collapsed"))
            window.recalculateKeyViewLoop()
        }
        button.bezelStyle = .inline; button.isBordered = false; button.setButtonType(.pushOnPushOff)
        button.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        button.imagePosition = .imageLeading; button.alignment = .left
        button.setAccessibilityLabel(title); button.setAccessibilityValue(ProductCopy.text("已折叠", "Collapsed"))
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
        let retry = makeButton(ProductCopy.text("重试保存这次选择", "Retry Saving This Choice"), id: "retry.\(domain.rawValue)") { [weak self] in self?.dispatch(.settings(.retry(domain))) }
        let stack = SettingsNativeStyle.stack([label, retry], spacing: 6)
        stack.isHidden = true
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        errorRows[domain] = stack; errorLabels[domain] = label; retryButtons[domain] = retry
        return stack
    }
}
