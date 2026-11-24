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
        let rows = views.map { ($0 as? NSButton).map(actionRow) ?? $0 }
        let document = RiftVisualStyle.documentStack(rows, spacing: 0)
        document.identifier = .init("settings.center.page.\(page.rawValue)")
        document.edgeInsets = NSEdgeInsets(top: 15, left: 24, bottom: 22, right: 24)
        document.translatesAutoresizingMaskIntoConstraints = false
        for view in rows { view.widthAnchor.constraint(equalTo: document.widthAnchor, constant: -48).isActive = true }
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
        let visible = nativeSwitch(ProductCopy.text("显示桌面截图", "Show Desktop Screenshots"), id: "desktop.visible") { [weak self] visible in
            self?.dispatch(.settings(.setHidden(!visible)))
        }
        let appearance = popup(ProductCopy.text("窗口外观", "Window Appearance"), id: "appearance", titles: SettingsAppearanceChoice.allCases.map(\.title)) { [weak self] popup in
            guard SettingsAppearanceChoice.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.appearance(SettingsAppearanceChoice.allCases[popup.indexOfSelectedItem]))
        }
        geometryPreview.identifier = .init("settings.center.layoutPreview")
        geometryPreview.heightAnchor.constraint(equalToConstant: 140).isActive = true
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
        let arrival = popup(ProductCopy.text("出现动效", "Arrival Motion"), id: "arrival", titles: ArrivalMotionMode.allCases.map(\.title)) { [weak self] popup in
            guard ArrivalMotionMode.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
            self?.dispatch(.settings(.setArrival(ArrivalMotionMode.allCases[popup.indexOfSelectedItem])))
        }
        let restore = makeButton(ProductCopy.text("使用推荐外观", "Use Recommended Appearance"), id: "layout.defaults.display") { [weak self] in
            self?.restoreVisibleDefaults()
        }
        legacySection = row(ProductCopy.text("沿用自定义外观", "Custom Appearance"), control: restore)
        let count = popup(ProductCopy.text("每页截图数", "Screenshots per Page"), id: "count", titles: []) { [weak self] popup in
            guard let self, let count = Int(popup.titleOfSelectedItem ?? "") else { return }
            dispatch(.settings(.commitField(.visibleCountPreference, String(count), maximumCount: countCapacity(model.snapshot.owner))))
        }
        trayAppearanceSection = trayAppearanceControls()
        displayRow = row(ProductCopy.text("显示器", "Display"), control: display)
        let advanced = group([
            row(ProductCopy.text("每页截图数", "Screenshots per Page"), control: count),
            row(ProductCopy.text("出现动效", "Arrival Motion"), control: arrival), domainError(.arrival), namedLabel("motion.detail", role: "caption")
        ])
        return [
            preferenceRecoveryRow(.layout),
            row(ProductCopy.text("显示桌面截图", "Show Desktop Screenshots"), detail: SettingsNativeStyle.label(ProductCopy.text("隐藏后仍会收录新截图。", "New screenshots are still collected when hidden."), role: "caption"), control: visible), domainError(.visibility),
            row(ProductCopy.text("窗口外观", "Window Appearance"), control: appearance), namedLabel("appearance.detail", role: "caption"),
            makeButton(ProductCopy.text("重试保存外观", "Retry Saving Appearance"), id: "appearance.retry") { [weak self] in self?.dispatch(.retryAppearance) },
            row(ProductCopy.text("桌面形态", "Desktop Form"), control: form), domainError(.desktopForm),
            geometryPreview, windChimeSettings!, domainError(.windChimeArrangement),
            row(ProductCopy.text("屏幕边缘", "Screen Edge"), control: buttonRow([edgePreview, placement])), domainError(.placement),
            displayRow!, namedLabel("display.detail", role: "caption"), domainError(.display),
            makeButton(ProductCopy.text("回到已选显示器", "Return to Preferred Display"), id: "display.restore") { [weak self] in self?.dispatch(.restorePreferredDisplay) },
            trayAppearanceSection!,
            disclosure(ProductCopy.text("更多", "More"), id: "display.advanced", content: advanced),
            legacySection!, domainError(.layout), namedLabel("diagnostics", role: "caption")
        ]
    }

    private func trayFavoriteSettings() -> NSView {
        let slots = SettingsNativeStyle.stack([], vertical: false, spacing: 8)
        slots.distribution = .fillEqually
        var errors: [NSView] = []
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
            let slotColumn = SettingsNativeStyle.stack([SettingsNativeStyle.label(title, role: "caption"), control], spacing: 4)
            control.widthAnchor.constraint(equalTo: slotColumn.widthAnchor).isActive = true
            slots.addArrangedSubview(slotColumn)
            errors.append(domainError(slot.settingsDomain))
        }
        return group([namedLabel("tray.favorites.detail", role: "caption"), slots] + errors)
    }

    func captureContent() -> [NSView] {
        let resumeCollection = makeButton(ProductCopy.text("继续收录截图", "Resume Screenshot Collection"), id: "collection.resume") { [weak self] in
            self?.dispatch(.settings(.setCollectionPaused(false)))
        }
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
        let sourceName = namedLabel("sourcePath.capture", role: "caption")
        sourceName.maximumNumberOfLines = 1
        sourceName.lineBreakMode = .byTruncatingMiddle
        return [
            section(ProductCopy.text("系统截图", "System Screenshots")),
            row(ProductCopy.text("截图文件夹", "Screenshot Folder"), detail: sourceName, control: makeButton(ProductCopy.text("在 Finder 中打开", "Open in Finder"), id: "source.open.capture") { [weak self] in self?.dispatch(.openSource) }),
            namedLabel("source.capture", role:"body"),
            buttonRow([
                makeButton(ProductCopy.text("允许访问截图文件夹…", "Allow Screenshot Folder Access…"), id: "source.access.capture") { [weak self] in self?.dispatch(.chooseSourceAccess) },
                makeButton(ProductCopy.text("重新检查", "Check Again"), id: "source.recheck.capture") { [weak self] in self?.dispatch(.recheckSource) }
            ]),
            resumeCollection, domainError(.collection),
            section(ProductCopy.text("内置截图", "Built-in Capture")),
            row(ProductCopy.text("显示内置截图入口", "Show Capture Button"), control: entry), domainError(.entry), captureOptions!,
            section(ProductCopy.text("截图仓库", "Screenshot Library")), preferenceRecoveryRow(.archive), archiveSettings(),
            buttonRow([
                makeButton(ProductCopy.text("打开截图仓库…", "Open Screenshot Library…"), id:"history.open") { [weak self] in self?.dispatch(.openHistory) },
                makeButton(ProductCopy.text("管理截图资料…", "Manage Screenshot Storage…"), id: "storage.manage") { [weak self] in self?.dispatch(.manageMedia) }
            ]),
            namedLabel("history.detail", role:"caption"),
            disclosure(ProductCopy.text("本机存储", "Local Storage"), id:"storage", content: group([namedLabel("storage", role:"caption"), makeButton(ProductCopy.text("重新检查用量", "Refresh Usage"), id: "storage.check") { [weak self] in self?.dispatch(.checkStorage) }]))
        ]
    }

    static var archivePresetMinutes: [Int] { [1, Int(QueueArchivePolicy.defaultMinutes), 5, 10] }

    private func archiveSettings() -> NSView {
        let choices = Self.archivePresetMinutes
        let preset = popup(ProductCopy.text("自动归档时限", "Auto-Archive Time"), id: "archive.preset", titles: [ProductCopy.text("关闭", "Off")] + choices.map { ProductCopy.text("\($0) 分钟", "\($0) min") } + [ProductCopy.text("自定义…", "Custom…")]) { [weak self] popup in
            let index = popup.indexOfSelectedItem
            guard index <= choices.count else { return }
            let text = choices.indices.contains(index - 1) ? String(choices[index - 1]) : nil
            self?.dispatch(.settings(.commitArchive(text)))
        }
        preset.autoenablesItems = false
        preset.lastItem?.isEnabled = false
        return group([
            row(ProductCopy.text("闲置后从桌面收起", "Hide Idle Screenshots"), detail: SettingsNativeStyle.label(ProductCopy.text("收起后仍可在截图仓库中查看。", "Hidden screenshots remain in your library."), role: "caption"), control: preset), domainError(.archive)
        ])
    }

    func generalContent() -> [NSView] {
        let login = nativeSwitch(ProductCopy.text("登录时启动 Riftlet", "Launch Riftlet at Login"), id: "login") { [weak self] in self?.dispatch(.loginEnabled($0)) }
        automaticUpdatesRow = row(ProductCopy.text("每天检查更新", "Check Daily for Updates"), control: nativeSwitch(ProductCopy.text("每天检查更新", "Check Daily for Updates"), id: "updates.automatic") { [weak self] enabled in self?.dispatch(.automaticUpdateChecks(enabled)) })
        return [
            row(ProductCopy.text("登录时启动 Riftlet", "Launch Riftlet at Login"), control:login), namedLabel("login.detail", role:"caption"),
            buttonRow([makeButton(ProductCopy.text("重试", "Retry"), id:"login.retry") { [weak self] in self?.dispatch(.retryLogin) },
                       makeButton(ProductCopy.text("打开登录项设置…", "Open Login Items Settings…"), id:"login.system") { [weak self] in self?.dispatch(.openLoginSettings) }]),
            section(ProductCopy.text("软件更新", "Software Updates")),
            row(ProductCopy.text("当前版本", "Current Version"), detail: namedLabel("version"), control:
                makeButton(ProductCopy.text("检查更新…", "Check for Updates…"), id: "updates.check") { [weak self] in self?.dispatch(.checkForUpdates) }),
            automaticUpdatesRow,
            namedLabel("updates.failure", role: "caption"),
            makeButton(ProductCopy.text("从官网下载…", "Download from Website…"), id: "updates.website") { [weak self] in self?.dispatch(.openDownloadWebsite) }
        ]
    }

    func helpContent() -> [NSView] {
        [
            section(ProductCopy.text("浏览器连接", "Browser Connection")), namedLabel("access.chrome", role: "rowTitle"), namedLabel("automation", role: "secondary"),
            namedLabel("chrome.menu", role: "caption"), namedLabel("attachment", role: "caption"),
            makeButton(ProductCopy.text("允许浏览器连接…", "Allow Browser Connection…"), id:"automation.request") { [weak self] in
                guard let self else { return }
                dispatch(product.setup.permission == .notRunning ? .openChrome : .requestAutomation)
            },
            makeButton(ProductCopy.text("检查浏览器连接", "Check Browser Connection"), id:"chrome.check") { [weak self] in self?.dispatch(.checkChromeConnection) },
            section(ProductCopy.text("使用帮助", "Getting Help")), SettingsNativeStyle.label(ProductCopy.text("截一张图，点桌面边缘的缩略图，即可将图片加入当前 Chrome 或 Edge 的 ChatGPT 草稿。确认后由你发送。", "Take a screenshot, then click its thumbnail at the edge of your desktop to attach it to your current ChatGPT draft in Chrome or Edge. You choose when to send."), role: "secondary"),
            makeButton(ProductCopy.text("重新查看引导…", "Open Setup Guide…"), id:"guide.help") { [weak self] in self?.dispatch(.openOnboarding) },
            makeButton(ProductCopy.text("反馈与建议…", "Send Feedback…"), id:"feedback.help") { [weak self] in self?.dispatch(.openFeedback) },
            disclosure(ProductCopy.text("诊断", "Diagnostics"), id:"diagnostics", content: group([namedLabel("support", role:"caption"), namedLabel("build.detail", role:"caption"),
                makeButton(ProductCopy.text("复制诊断摘要", "Copy Diagnostic Summary"), id:"diagnostics.copy") { [weak self] in
                    guard let self else { return }
                    let lines = ["build.detail", "access.chrome", "screen.capture"].compactMap { self.labels[$0]?.stringValue }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                },
                makeButton(ProductCopy.text("重新检查本地截图副本", "Check Local Screenshot Copies"), id:"storage.recheckMedia") { [weak self] in self?.dispatch(.recheckMedia) },
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
        return popup
    }
    func namedLabel(_ id: String, role: String = "body") -> NSTextField {
        let label = SettingsNativeStyle.label("", role: role)
        label.identifier = .init("settings.center.\(id)")
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        labels[id] = label
        return label
    }
    func buttonRow(_ views: [NSView]) -> NSStackView {
        // Action clusters align with the controls above. Numeric input clusters
        // remain intrinsic-width so their slider, value and unit stay together.
        let actionsOnly = !views.isEmpty && views.allSatisfy { $0 is NSButton }
        return SettingsNativeStyle.stack(actionsOnly ? [NSView()] + views : views, vertical: false, spacing: 9)
    }
    /// A secondary action keeps its native bezel and intrinsic width, rather
    /// than becoming a full-width, shallow button when placed in a page stack.
    func actionRow(_ button: NSButton) -> NSView {
        let container = NSView()
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalTo: button.heightAnchor, constant: 12)
        ])
        if let id = button.identifier?.rawValue, id.hasPrefix("settings.center.") {
            actionContainers[String(id.dropFirst("settings.center.".count))] = container
        }
        return container
    }
    func row(_ title: String, detail: NSTextField? = nil, control: NSView) -> NSStackView {
        var copyViews = [SettingsNativeStyle.label(title, role: "rowTitle")]
        if let detail { copyViews.append(detail) }
        let copy = SettingsNativeStyle.stack(copyViews, spacing: 4)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = SettingsNativeStyle.stack([copy, control], vertical: false, spacing: 16)
        stack.distribution = .fill
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: detail == nil ? 36 : 50).isActive = true
        return stack
    }
    func group(_ views: [NSView]) -> NSStackView {
        let rows = views.map { ($0 as? NSButton).map(actionRow) ?? $0 }
        let group = SettingsNativeStyle.stack(rows, spacing: 8)
        for view in rows { view.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true }
        return group
    }
    func section(_ title:String, trailing:NSView? = nil) -> NSView {
        let label = SettingsNativeStyle.label(title,role:"rowTitle")
        label.textColor = .labelColor
        label.font = .systemFont(ofSize:13,weight:.semibold)
        let group = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:group.leadingAnchor), label.bottomAnchor.constraint(equalTo:group.bottomAnchor,constant:-5),
                                     label.topAnchor.constraint(equalTo:group.topAnchor,constant:14)])
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
            if expand && id == "storage" && product.setup.storage == .notMeasured && product.capabilities.canCheckStorage && !storageRequested {
                storageRequested = true
                dispatch(.checkStorage)
            }
            window.recalculateKeyViewLoop()
        }
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
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
