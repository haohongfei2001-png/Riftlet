import AppKit
import RiftletCapture

@MainActor
extension RiftSettingsCenterController {
    func render() {
        let owner = model.snapshot.owner
        let settings = owner.settings
        let presentation = SetupPresentation(snapshot: product.setup)
        for (page, button) in navigation {
            button.state = page == selectedPage ? .on : .off
            button.contentTintColor = page == selectedPage ? SettingsNativeStyle.color(.accentInk) : .secondaryLabelColor
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                button.layer?.backgroundColor = page == selectedPage ? SettingsNativeStyle.color(.accentInk).withAlphaComponent(0.13).cgColor : NSColor.clear.cgColor
            }
            button.setAccessibilityValue(page == selectedPage ? "已选中" : "")
        }
        for (domain, row) in preferenceRecoveryRows {
            row.isHidden = !product.preferenceRecovery.contains(domain)
            let key = "recovery." + domain.rawValue
            let description = domain == .layout ? "布局设置无法读取，当前使用可用布局。" : "归档设置无法读取，自动归档已暂停。"
            let detail = product.preferenceRecoveryFailure == domain ? "恢复未完成，请重试。" : "恢复时会保留原文件副本。"
            text(key, description + detail)
            enable(key + ".restore", product.capabilities.canEditPreferences)
        }
        renderLogin()
        select("appearance", index: SettingsAppearanceChoice.allCases.firstIndex(of: product.appearance.selection) ?? 0)
        enable("appearance", product.appearance.available)
        text("appearance.detail", product.appearance.failure ?? (product.appearance.unreadable ? "暂时无法读取外观偏好。当前显示不代表偏好已保存。"
             : product.appearance.applied == nil ? "外观尚未应用。" : "当前外观已应用。"))
        labels["appearance.detail"]?.isHidden = product.appearance.failure == nil && !product.appearance.unreadable && product.appearance.applied != nil
        hide("appearance.retry", product.appearance.failure == nil)
        enable("appearance.retry", product.appearance.available && product.appearance.pending != nil)
        renderDisplay()
        check("entry", settings.entryEnabled, enabled: settings.entryAvailable && product.capabilities.canEditPreferences && !busy(.entry))
        select("captureMode", index: [.window, .region, .fullScreen].firstIndex(of: settings.defaultCaptureMode) ?? 0)
        enable("captureMode", settings.entryAvailable && product.capabilities.canEditPreferences && !busy(.captureMode))
        captureOptions.isHidden = !settings.entryEnabled && ![SettingsDomain.captureMode, .trayFavorite1, .trayFavorite2, .trayFavorite3].contains { model.snapshot.domains[$0]?.hasIssue == true }
        trayFavorites.isHidden = settings.configuration.desktopForm != .tray && !RiftTrayFavoriteSlot.allCases.contains { model.snapshot.domains[$0.settingsDomain]?.hasIssue == true }
        text("source.capture", presentation.sourceText)
        text("sourcePath.capture", presentation.sourcePath)
        hide("source.access.capture", !presentation.needsSourceAccess)
        enable("source.access.capture", product.capabilities.canChooseSource && presentation.needsSourceAccess)
        text("screen.capture", screenRecordingText)
        let screenNeedsAttention = settings.entryEnabled && product.screenRecording == .notGranted
        labels["screen.capture"]?.isHidden = !screenNeedsAttention
        hide("screen.privacy", !screenNeedsAttention)
        let readableFolder = product.setup.source == .accessible && presentation.sourceIssue == nil
        labels["source.capture"]?.isHidden = readableFolder
        hide("source.recheck.capture", readableFolder || product.setup.source == .notApplicable)
        enable("source.recheck.capture", product.capabilities.canRecheck && !product.setup.isChecking)
        let supportsConnectionCheck = product.setup.attachment == .available
        var chromeState: String
        switch product.setup.permission {
        case .granted: chromeState = "已允许自动化"
        case .denied: chromeState = "需要授权"
        case .notNeeded: chromeState = "无需授权"
        case .notRunning, .browserUnavailable, .unavailable: chromeState = "暂不可用"
        default: chromeState = "使用时检查"
        }
        if supportsConnectionCheck && product.setup.permission == .granted {
            switch product.chromeConnection {
            case .unchecked:
                chromeState = product.setup.issue == .chromeJavaScriptDisabled ? "需开启 JavaScript" : "待检查连接"
            case .checking: chromeState = "检查中"
            case .ready: chromeState = "已连接"
            case .javaScriptDisabled: chromeState = "需开启 JavaScript"
            case .noWindow: chromeState = "请打开 Chrome 窗口"
            case .unavailable: chromeState = "连接未成功"
            }
        }
        text("access.chrome", chromeState)
        let canTestConnection = supportsConnectionCheck && product.setup.permission == .granted
        hide("chrome.check", !canTestConnection)
        enable("chrome.check", canTestConnection && product.capabilities.canRequestAutomation
               && !product.reviewEnvironment && product.chromeConnection != .checking && !product.setup.isChecking)
        (controls["chrome.check"] as? NSButton)?.title = product.chromeConnection == .checking ? "正在检查连接…" : "检查 Chrome 连接"
        enable("source.open.capture", presentation.hasSourceLocation)
        select("arrival", index: ArrivalMotionMode.allCases.firstIndex(of: settings.arrivalMode) ?? 0)
        enable("arrival", product.capabilities.canEditPreferences && !busy(.arrival))
        text("motion.detail", "已开启系统“减少动态效果”。截图将直接显示，动效选择会保留。")
        labels["motion.detail"]?.isHidden = !product.accessibility.reduceMotion
        let count = product.setup.pendingCount
        text("history.detail", "有 \(count) 张截图的附加结果待核实。请查看原草稿，Riftlet 不会自动重传。")
        labels["history.detail"]?.isHidden = count == 0
        enable("history.open", product.capabilities.canOpenHistory)
        text("storage", product.setup.storage == .notMeasured ? "尚未检查本地存储用量。" : presentation.storageText)
        enable("storage.recheckMedia", product.capabilities.canRecheck && !product.setup.isChecking)
        enable("storage.check", product.capabilities.canCheckStorage && product.setup.storage != .measuring)
        enable("storage.reveal", product.capabilities.initialized)
        text("automation", presentation.automationStatusText ?? "当前模式不需要 Chrome 自动化访问。")
        let scriptInstructions = presentation.chromeScriptInstructions
            ?? (canTestConnection && [.unchecked, .javaScriptDisabled].contains(product.chromeConnection) ? ChromeAttachmentSetup.instructions : nil)
        text("chrome.menu", scriptInstructions ?? "")
        labels["chrome.menu"]?.isHidden = scriptInstructions == nil || product.setup.issue == .chromeJavaScriptDisabled
            || (canTestConnection && product.chromeConnection == .ready)
        // A general invitation to click a screenshot would contradict a failed connection check.
        let lastAttachmentProblem = product.setup.issue?.isAttachmentConnectionIssue == true
        labels["attachment"]?.isHidden = supportsConnectionCheck && !lastAttachmentProblem
        text("attachment", presentation.attachmentText)
        (controls["automation.request"] as? NSButton)?.title = presentation.permissionActionTitle
        hide("automation.request", !presentation.canRequestPermission)
        enable("automation.request", product.capabilities.canRequestAutomation && presentation.canRequestPermission && !product.setup.isChecking)
        enable("screen.privacy", settings.entryAvailable)
        text("version", product.version.isEmpty ? "版本信息尚未提供。" : product.version)
        let updater = product.updater
        check("updates.automatic", updater?.automaticChecks == true, enabled: updater?.automaticChecks != nil)
        (controls["updates.check"] as? NSButton)?.title = updater?.checkTitle ?? "检查更新…"
        enable("updates.check", updater?.canCheck == true)
        text("updates.failure", updater?.failure.map { "更新未完成。" + $0 } ?? "")
        labels["updates.failure"]?.isHidden = updater?.failure == nil
        text("support", presentation.supportText)
        text("diagnostics", "当前操作结束后会应用新的桌面布局。")
        labels["diagnostics"]?.isHidden = !product.configurationDeferred
        hide("updates.website", updater?.failure == nil)
        for domain in SettingsDomain.allCases { renderError(domain) }
        refreshDraftPresentation()
        refreshCloseButtons()
    }

    func renderLogin() {
        let login = product.login
        check("login", login.switchValue, enabled: login.available && !login.isBusy && login.status != .unknown && login.status != nil)
        let detail: String
        if login.isBusy { detail = "正在等待 macOS 更新登录项状态…" }
        else if !login.available { detail = "此运行环境不更改系统登录项。" }
        else if login.status == .requiresApproval { detail = "开启请求已提交，等待你在系统设置中允许；尚未获准登录启动。" }
        else if login.notConfirmed { detail = "更改尚未确认。可重试或在系统设置中查看登录项。" }
        else {
            switch login.status {
            case .enabled: detail = "macOS 已允许 Riftlet 在登录后启动。"
            case .notRegistered: detail = "未注册登录启动。"
            case .notFound: detail = "macOS 暂未找到此应用的登录项。可以尝试开启。"
            case .unknown, nil: detail = "暂时无法读取登录项状态。"
            case .requiresApproval: detail = "等待系统批准。"
            }
        }
        let error = login.errorCode.map { " macOS 返回错误代码 \($0)。" } ?? ""
        text("login.detail", detail + error)
        labels["login.detail"]?.isHidden = login.available && !login.notConfirmed && !login.isBusy && login.errorCode == nil && (login.status == .notRegistered || login.status == .enabled)
        hide("login.retry", login.failedTarget == nil)
        enable("login.retry", login.available && !login.isBusy && login.failedTarget != nil)
        hide("login.system", login.status != .requiresApproval && !login.notConfirmed)
        enable("login.system", login.available && !login.isBusy)
    }

    func renderDisplay() {
        let owner = model.snapshot.owner
        let settings = owner.settings
        let configuration = settings.configuration
        select("desktopForm", index: RiftDesktopForm.allCases.firstIndex(of: configuration.desktopForm) ?? 0)
        let windChime = configuration.desktopForm == .windChime
        windChimeSettings?.isHidden = !windChime
        let tray = configuration.desktopForm == .tray
        commonEdgeSettings?.isHidden = windChime
        slitInsetFraction?.isHidden = configuration.desktopForm != .microSlit
        trayOcclusionRow?.isHidden = !tray
        windChimeLineSetting?.isHidden = !windChime
        select("windChimeArrangement", index: RiftWindChimeArrangement.allCases.firstIndex(of: configuration.windChimeArrangement)!)
        enable("windChimeArrangement", product.capabilities.canEditPreferences && !configurationBusy)
        (controls["trayTheme"] as? NSPopUpButton)?.selectItem(withTitle: configuration.trayTheme.title)
        enable("desktopForm", product.capabilities.canEditPreferences && !configurationBusy)
        enable("trayTheme", product.capabilities.canEditPreferences && !configurationBusy)
        trayTintSettings?.isHidden = configuration.trayTheme != .custom
        traySettings?.isHidden = configuration.desktopForm != .tray
        let defaultMode = settings.defaultCaptureMode
        let defaultTitle = RiftTrayFavoriteChoice.mode(defaultMode).menuTitle
        text("tray.favorites.detail", "常用键从屏幕内侧向边缘排列。最外侧使用“截图”页的默认方式（\(defaultTitle)）。")
        let choices = RiftTrayFavoriteChoice.menuChoices
        for slot in RiftTrayFavoriteSlot.allCases {
            let id = slot.settingsDomain.rawValue
            guard let control = controls[id] as? NSPopUpButton else { continue }
            let choice = configuration.trayFavorite(slot)
            let automatic = slot.automaticMode(defaultMode: defaultMode).map(RiftTrayFavoriteChoice.mode) ?? .empty
            let title = "自动（\(automatic.menuTitle)）"
            if control.item(at: 0)?.title != title { control.item(at: 0)?.title = title }
            control.lastItem?.isHidden = choice != .unsupported
            if let index = choices.firstIndex(of: choice) { select(id, index: index) }
            enable(id, product.capabilities.canEditPreferences && !configurationBusy)
        }
        guard let popup = controls["display"] as? NSPopUpButton else { return }
        // Concrete UUID/ID resolution is already performed by the owner; the
        // view never converts a temporary fallback into a preference.
        let selected = settings.configuration.preferredDisplayID ?? settings.preferredDisplayID
        if displayMenuTracking {
            displayRefreshPending = true
        } else {
            if displayItems != settings.displays || displaySelection != selected || popup.numberOfItems == 0 {
                popup.removeAllItems()
                if selected == nil {
                    popup.addItem(withTitle: "尚未选择显示器")
                    popup.lastItem?.isEnabled = false
                } else if !settings.displays.contains(where: { $0.id == selected }) {
                    popup.addItem(withTitle: "已选显示器（未连接）")
                    popup.lastItem?.representedObject = NSNumber(value: selected!)
                    popup.lastItem?.isEnabled = false
                }
                let repeatedNames = Dictionary(grouping: settings.displays, by: \.name).mapValues(\.count)
                var ordinals: [String:Int] = [:]
                for display in settings.displays {
                    // Two physical displays may have the same human name.
                    // NSPopUpButton.addItem(withTitle:) can replace a same-title
                    // item; add distinct native menu items with concrete IDs.
                    ordinals[display.name,default:0] += 1
                    let title = repeatedNames[display.name,default:0] > 1 ? display.name + " · " + String(ordinals[display.name,default:0]) : display.name
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    item.representedObject = NSNumber(value: display.id)
                    popup.menu?.addItem(item)
                }
                displayItems = settings.displays; displaySelection = selected
            }
            let index = popup.itemArray.firstIndex { ($0.representedObject as? NSNumber)?.uint32Value == selected }
            popup.selectItem(at: index ?? 0)
        }
        enable("display", product.capabilities.canEditPreferences && !settings.displays.isEmpty && !configurationBusy)
        let current = owner.effectiveDisplayID.flatMap { id in settings.displays.first(where: { $0.id == id })?.name }
        if let selected, owner.effectiveDisplayID != selected {
            text("display.detail", "已保留所选显示器。当前临时显示在\(current.map { "“\($0)”" } ?? "可用屏幕")，不会自动修改偏好。")
        } else if let current { text("display.detail", "当前显示在“\(current)”。") }
        else { text("display.detail", "暂时无法确认截图显示在哪个屏幕。") }
        // The normal popup already names the active selected display. Retain
        // the full extra explanation whenever that equality is not confirmed.
        labels["display.detail"]?.isHidden = selected != nil && selected == owner.effectiveDisplayID && current != nil
        hide("display.restore", !settings.displayRestoreAvailable)
        enable("display.restore", settings.displayRestoreAvailable && product.capabilities.canEditPreferences)
        if let popup = controls["placement"] as? NSPopUpButton {
            popup.lastItem?.isHidden = configuration.placement != nil
            popup.selectItem(at: configuration.placement.flatMap { RiftPlacement.allCases.firstIndex(of: $0) } ?? RiftPlacement.allCases.count)
        }
        enable("placement", product.capabilities.canEditPreferences && !configurationBusy)
    }

    /// Use the same screen and the same layout calculation as the live presentation.
    /// A stored preference can exceed the current display without rewriting it.
    func countCapacity(_ owner: SettingsOwnerSnapshot) -> Int {
        var c = owner.settings.configuration
        c.visibleCountPreference = 10
        if c.desktopForm == .tray { return 4 }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == owner.effectiveDisplayID
        } ?? window.screen ?? NSScreen.main
        guard let screen else { return 10 }
        if c.desktopForm == .windChime {
            return RiftWindChimeLayout.make(records: [], visibleFrame: screen.visibleFrame, configuration: c, displayFrame: screen.frame).capacity
        }
        return RiftLayout.make(records: [], visibleFrame: screen.visibleFrame, configuration: c).capacity
    }

    func refreshDraftPresentation() {
        let state = model.snapshot
        let editable = product.capabilities.canEditPreferences
        let limit = countCapacity(state.owner)
        for (field, view) in numericFields {
            let failed = state.domains[.layout]?.saveFailure != nil
            var value = failed ? model.effectiveText(for: field) : model.text(for: field)
            if field == .visibleCountPreference, state.layoutText[field] == nil || failed {
                value = String(min(state.owner.settings.configuration.visibleCountPreference, limit))
            }
            if view.currentEditor() == nil {
                displayedEditorValues[ObjectIdentifier(view)] = value
                if view.stringValue != value { view.stringValue = value }
                view.isEnabled = editable && (field != .visibleCountPreference || limit > 0)
            }
            if let slider = numericSliders[field] {
                if field == .visibleCountPreference {
                    slider.maxValue = Double(max(1, limit))
                    slider.numberOfTickMarks = max(1, limit)
                }
                if let n = number(value), n.isFinite { slider.doubleValue = min(slider.maxValue, max(slider.minValue, n)) }
                slider.isEnabled = editable && (field != .visibleCountPreference || limit > 1)
            }
        }
        let config = state.owner.settings.configuration
        numericSliders[.trayTintHue]?.trackFillColor = NSColor(hue: config.trayTintHue / 360, saturation: 0.7, brightness: 0.8, alpha: 1)
        let archiveFailed = state.domains[.archive]?.saveFailure != nil
        let minutes = state.owner.settings.archiveAfterMinutes
        let archiveValue = archiveFailed ? SettingsStateModel.archiveMinutesText(minutes ?? QueueArchivePolicy.defaultMinutes,
                decimalSeparator: Locale.current.decimalSeparator ?? ".") : model.archiveDraftText
        if archiveField.currentEditor() == nil {
            displayedEditorValues[ObjectIdentifier(archiveField)] = archiveValue
            if archiveField.stringValue != archiveValue { archiveField.stringValue = archiveValue }
            archiveField.isEnabled = editable
        }
        let choices = Self.archivePresetMinutes.map(Double.init)
        let preset = number(archiveValue).flatMap { choices.firstIndex(of: $0) }
        let disabled = archiveFailed ? minutes == nil : model.archiveIsDisabled
        let showCustom = !disabled && (archiveCustom || preset == nil)
        archiveCustomRow.isHidden = !showCustom
        select("archive.preset", index: disabled ? 0 : showCustom ? choices.count + 1 : (preset ?? 0) + 1)
        enable("archive.preset", editable)
        enable("layout.defaults.display", editable && !configurationBusy)
        renderError(.layout); renderError(.archive)
        var previewConfig = config
        previewConfig.visibleCountPreference = min(limit, config.visibleCountPreference)
        geometryPreview.update(configuration: previewConfig, entryEnabled: state.owner.settings.entryEnabled)
        text("layoutPreview.detail", "预览 · " + geometryPreview.geometrySummary)
        refreshCloseButtons()
    }

    func renderError(_ domain: SettingsDomain) {
        guard let row = errorRows[domain] else { return }
        let state = model.snapshot.domains[domain]
        let value = errorText(domain)
        row.isHidden = value == nil
        errorLabels[domain]?.stringValue = value ?? ""
        retryButtons[domain]?.isHidden = state?.saveFailure == nil || state?.pending == nil
        let canSave: Bool
        switch domain {
        case .collection: canSave = product.capabilities.canChangeCollection
        case .visibility: canSave = product.capabilities.canChangeVisibility
        default: canSave = product.capabilities.canEditPreferences
        }
        retryButtons[domain]?.isEnabled = canSave && !busy(domain) && (!domain.writesConfiguration || !configurationBusy)
    }
    func errorText(_ domain: SettingsDomain) -> String? {
        guard let state = model.snapshot.domains[domain] else { return nil }
        if let validation = state.validationFailure {
            switch validation {
            case .invalidArchive: return "请输入 1–10 之间的分钟数，支持小数。如需停用，请选择“关闭”。"
            case .invalidNumber(let field): return "“\(fieldTitle(field))”不是有效数值。请修改后按回车。"
            case .invalidConfiguration: return "该值超出允许范围，请输入有效数值。"
            case .displayUnavailable: return "所选显示器当前不可用，未保存新的显示器偏好。"
            case .inactiveLegacyField: return "已选择六点位置，旧版距顶部参数不再生效。请放弃这项旧参数草稿后重试。"
            }
        }
        guard state.saveFailure != nil else { return nil }
        let target: String
        switch state.pending {
        case .collectionPaused(let paused): target = paused ? "暂停收录" : "继续收录"
        case .hidden(let hidden): target = hidden ? "隐藏桌面微图" : "显示桌面微图"
        case .entryEnabled(let enabled): target = enabled ? "启用内置截图" : "关闭内置截图"
        case .captureMode: target = "默认截图方式"
        case .arrival: target = "截图出现动效"
        case .desktopForm: target = "桌面形态"
        case .windChimeArrangement(let arrangement): target = "风铃排列 · " + arrangement.title
        case .trayTheme: target = "托盘材质"
        case .trayFavorite(let slot, let choice): target = "常用键 \(slot.rawValue) · \(choice.menuTitle)"
        case .layout: target = "参数更改"
        case .placement: target = "边缘位置"
        case .display: target = "显示器偏好"
        case .archiveMinutes: target = "归档时限"
        case nil: target = "这项选择"
        }
        return "“\(target)”未能保存，请重试。"
    }
    var configurationBusy: Bool { SettingsDomain.allCases.contains { $0.writesConfiguration && busy($0) } }
    func busy(_ domain: SettingsDomain) -> Bool { model.snapshot.domains[domain]?.isSaving == true }
    func text(_ id: String, _ value: String) { if labels[id]?.stringValue != value { labels[id]?.stringValue = value } }
    func enable(_ id: String, _ enabled: Bool) { controls[id]?.isEnabled = enabled }
    func hide(_ id: String, _ hidden: Bool) { controls[id]?.isHidden = hidden }
    func check(_ id: String, _ on: Bool, enabled: Bool) {
        if let toggle = controls[id] as? NSSwitch { toggle.state = on ? .on : .off }
        else { (controls[id] as? NSButton)?.state = on ? .on : .off }
        enable(id, enabled)
    }
    func select(_ id: String, index: Int) {
        if let segments = controls[id] as? NSSegmentedControl {
            if (0..<segments.segmentCount).contains(index), segments.selectedSegment != index { segments.selectedSegment = index }
            return
        }
        guard let popup = controls[id] as? NSPopUpButton, popup.itemArray.indices.contains(index) else { return }
        if popup.indexOfSelectedItem != index { popup.selectItem(at: index) }
    }
    func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."))
    }
    func fieldTitle(_ field: SettingsField) -> String {
        numericFields[field]?.accessibilityLabel() ?? field.rawValue
    }
    var screenRecordingText: String {
        switch product.screenRecording {
        case .notChecked: return "尚未检查屏幕录制权限；仅在使用内置截图时需要。"
        case .granted: return "屏幕录制权限已允许。"
        case .notGranted: return "屏幕录制权限尚未允许，可在系统设置中开启。"
        case .unavailable: return "当前环境无法确认内置截图权限。"
        }
    }
}
