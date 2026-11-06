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
            button.contentTintColor = SettingsNativeStyle.color(page == selectedPage ? .accent : .ink)
            button.setAccessibilityValue(page == selectedPage ? "已选中" : "")
        }
        let statusTitle: String
        if owner.collectionPaused { statusTitle = owner.isHidden ? "已暂停 · 裂缝已隐藏" : "已暂停收录" }
        else if product.setup.collection == .collecting { statusTitle = owner.isHidden ? "正在收录 · 裂缝已隐藏" : "正在收录" }
        else { statusTitle = owner.isHidden ? "裂缝已隐藏" : "收录状态" }
        text("status.title", statusTitle)
        let collection = owner.collectionPaused ? "收录已暂停，已有截图保留。" : presentation.collectionText
        text("status.detail", collection + " " + (owner.isHidden ? "边缘微图当前隐藏。" : "当前可见 \(product.setup.visibleCount) 张。"))
        check("paused", owner.collectionPaused, enabled: product.capabilities.canChangeCollection && !busy(.collection))
        check("hidden", owner.isHidden, enabled: product.capabilities.canChangeVisibility && !busy(.visibility))
        renderLogin()
        select("appearance", index: SettingsAppearanceChoice.allCases.firstIndex(of: product.appearance.selection) ?? 0)
        enable("appearance", product.appearance.available)
        text("appearance.detail", product.appearance.failure != nil
             ? "外观保存结果尚未确认。重试会保存刚才选择的外观。"
             : product.appearance.unreadable ? "暂时无法读取外观偏好。当前显示不代表偏好已保存。"
             : product.appearance.applied == nil ? "外观尚未应用。" : "当前外观已应用。")
        hide("appearance.retry", product.appearance.failure == nil)
        enable("appearance.retry", product.appearance.available && product.appearance.pending != nil)
        var a11y: [String] = []
        if product.accessibility.reduceMotion { a11y.append("减少动态效果") }
        if product.accessibility.reduceTransparency { a11y.append("减少透明度") }
        if product.accessibility.increaseContrast { a11y.append("提高对比度") }
        text("accessibility", a11y.isEmpty ? "遵循 macOS 的动态效果、透明度与对比度设置。" : "系统已开启：" + a11y.joined(separator: "、") + "。")

        renderDisplay()
        check("entry", settings.entryEnabled, enabled: settings.entryAvailable && product.capabilities.canEditPreferences && !busy(.entry))
        select("captureMode", index: [.window, .region, .fullScreen].firstIndex(of: settings.defaultCaptureMode) ?? 0)
        enable("captureMode", settings.entryAvailable && product.capabilities.canEditPreferences && !busy(.captureMode))
        enable("capture.start", product.capabilities.canCapture)
        for suffix in ["capture", "help"] {
            text("source.\(suffix)", presentation.sourceText)
            text("sourcePath.\(suffix)", presentation.sourcePath)
            enable("source.access.\(suffix)", product.capabilities.canChooseSource && presentation.hasSourceLocation)
            text("screen.\(suffix)", screenRecordingText)
        }
        enable("source.open.capture", presentation.hasSourceLocation)
        select("arrival", index: ArrivalMotionMode.allCases.firstIndex(of: settings.arrivalMode) ?? 0)
        enable("arrival", product.capabilities.canEditPreferences && !busy(.arrival))
        let motionText: String
        if product.accessibility.reduceMotion {
            motionText = "系统已开启“减少动态效果”：入缝静态呈现，保留已选偏好。"
        } else if !settings.hasArrivalSelection {
            motionText = "尚未选择入缝偏好；当前以“无”呈现。选择后保存，但不会自动播放。"
        } else { motionText = "当前入缝偏好：\(settings.arrivalMode.title)。" }
        text("motion.detail", motionText)
        let count = product.setup.pendingCount
        text("history.detail", count > 0 ? "当前有 \(count) 张结果待核实。记录留在本机，不会自动再次附加。" : "查看已有记录与本地图片；不会自动重传或发送聊天。")
        enable("history.open", product.capabilities.canOpenHistory)
        enable("history.clear", product.capabilities.canClearVisible && product.setup.visibleCount > 0)
        text("storage", presentation.storageText)
        enable("storage.check", product.capabilities.canCheckStorage && product.setup.storage != .measuring)
        text("automation", presentation.permissionText ?? "当前模式不需要 Chrome 自动化访问。")
        text("attachment", presentation.attachmentText)
        (controls["automation.request"] as? NSButton)?.title = presentation.permissionActionTitle
        enable("automation.request", product.capabilities.canRequestAutomation && presentation.canRequestPermission)
        enable("recheck", product.capabilities.canRecheck && !product.setup.isChecking)
        enable("source.privacy", product.capabilities.initialized)
        enable("screen.privacy", settings.entryAvailable)
        text("version", product.version.isEmpty ? "版本信息尚未提供。" : product.version)
        text("support", presentation.supportText)
        text("diagnostics", "设置状态版本 \(model.snapshot.revision)\n" + (product.configurationDeferred ? "几何更新会在当前交互结束后应用。" : "配置读取与保存不会处理图片或上传记录。"))
        enable("configuration.reload", product.capabilities.canEditPreferences && !model.hasLayoutDraft && !busy(.layout))
        enable("configuration.open", product.capabilities.canOpenConfiguration)
        for domain in SettingsDomain.allCases { renderError(domain) }
        refreshDraftPresentation()
        refreshCloseButtons()
    }

    func renderLogin() {
        let login = product.login
        check("login", login.switchValue, enabled: login.available && !login.isBusy && login.status != .unknown && login.status != .notFound && login.status != nil)
        let detail: String
        if login.isBusy { detail = "正在等待 macOS 更新登录项状态…" }
        else if !login.available { detail = "此运行环境不更改系统登录项。" }
        else if login.status == .requiresApproval { detail = "开启请求已提交，等待你在系统设置中允许；尚未获准登录启动。" }
        else if login.notConfirmed { detail = "这次选择尚未确认，开关显示 macOS 当前实际状态。可以重试同一个选择。" }
        else {
            switch login.status {
            case .enabled: detail = "macOS 已允许 Riftlet 在登录后启动。"
            case .notRegistered: detail = "未注册登录启动。"
            case .notFound: detail = "macOS 未找到可用的应用登录项。"
            case .unknown, nil: detail = "登录项状态暂时无法确认，不会据此注册或取消。"
            case .requiresApproval: detail = "等待系统批准。"
            }
        }
        let error = login.errorCode.map { " 本次系统操作返回异常（代码 \($0)）；当前状态以系统结果为准。" } ?? ""
        text("login.detail", detail + error)
        hide("login.retry", login.failedTarget == nil)
        enable("login.retry", login.available && !login.isBusy && login.failedTarget != nil)
        hide("login.system", login.status != .requiresApproval && !login.notConfirmed)
        enable("login.system", login.available && !login.isBusy)
    }

    func renderDisplay() {
        let owner = model.snapshot.owner
        let settings = owner.settings
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
                for display in settings.displays {
                    // Two physical displays may have the same human name.
                    // NSPopUpButton.addItem(withTitle:) can replace a same-title
                    // item; add distinct native menu items with concrete IDs.
                    let item = NSMenuItem(title: display.name, action: nil, keyEquivalent: "")
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
        else { text("display.detail", "显示器运行位置尚未确认。选择后保存具体显示器身份。") }
        hide("display.restore", !settings.displayRestoreAvailable)
        enable("display.restore", settings.displayRestoreAvailable && product.capabilities.canEditPreferences)
        for placement in RiftPlacement.allCases {
            let id = "placement.\(placement.rawValue)"
            let selected = settings.configuration.placement == placement
            check(id, selected, enabled: product.capabilities.canEditPreferences && !configurationBusy)
            if let button = controls[id] as? NSButton {
                // Native toggle bezels alone can look identical in both themes.
                // A checkmark preserves selection even without color perception.
                button.image = selected ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) : nil
                button.contentTintColor = SettingsNativeStyle.color(selected ? .accent : .ink)
                button.bezelColor = selected ? SettingsNativeStyle.color(.selection) : nil
            }
        }
        legacyFieldRow.isHidden = settings.configuration.placement != nil
    }

    func refreshDraftPresentation() {
        let state = model.snapshot
        let editable = product.capabilities.canEditPreferences
        for (field, view) in numericFields {
            // Never replace an active field editor's contents, selection or IME
            // marked range. Blurred dirty text comes verbatim from the model.
            if view.currentEditor() == nil {
                let value = model.text(for: field)
                if view.stringValue != value { view.stringValue = value }
                view.isEnabled = editable && (field != .firstCenterFromTop || state.owner.settings.configuration.placement == nil)
            }
            if let slider = numericSliders[field] {
                if let value = number(model.text(for: field)), value.isFinite { slider.doubleValue = min(slider.maxValue, max(slider.minValue, value)) }
                slider.isEnabled = editable
            }
        }
        if archiveField.currentEditor() == nil {
            let value = model.archiveDraftText
            if archiveField.stringValue != value { archiveField.stringValue = value }
            archiveField.isEnabled = editable
        }
        let archiveValues: [Double] = [0, 1, 8, 24, 72]
        let preset = number(model.archiveDraftText).flatMap { archiveValues.firstIndex(of: $0) }
        let showCustom = archiveCustom || preset == nil
        archiveCustomRow.isHidden = !showCustom
        select("archive.preset", index: showCustom ? 5 : preset ?? 0)
        enable("archive.preset", editable)
        let archiveIssue = state.domains[.archive]?.hasIssue == true
        text("archive.detail", busy(.archive) ? "正在保存这次归档时限…" : model.hasArchiveDraft ? "归档时限尚未应用；选择预设也需要点击保存。" : archiveIssue ? "归档时限还有未确认的保存结果。" : "当前归档时限已读取。")
        enable("archive.save", editable && !busy(.archive) && (model.hasArchiveDraft || archiveIssue))
        enable("archive.discard", !busy(.archive) && (model.hasArchiveDraft || archiveIssue || state.archiveText != nil))
        let layoutIssue = state.domains[.layout]?.hasIssue == true
        let layoutText = busy(.layout) ? "正在保存这次参数；新的编辑会继续保留在草稿中。"
            : model.hasLayoutDraft ? "位置与动效参数共用一份草稿；应用时保存两页的参数更改。"
            : layoutIssue ? "参数还有未确认的保存结果。" : "参数与当前有效设置一致。"
        for suffix in ["display", "motion"] {
            text("layout.detail.\(suffix)", layoutText)
            enable("layout.defaults.\(suffix)", editable)
            enable("layout.discard.\(suffix)", !busy(.layout) && (model.hasLayoutDraft || layoutIssue || !state.layoutText.isEmpty))
            enable("layout.apply.\(suffix)", editable && !configurationBusy && (model.hasLayoutDraft || layoutIssue))
        }
        let error = errorText(.layout)
        text("layout.error.motion", error ?? "")
        labels["layout.error.motion"]?.superview?.isHidden = error == nil
        hide("layout.retry.motion", state.domains[.layout]?.saveFailure == nil || state.domains[.layout]?.pending == nil)
        enable("layout.retry.motion", editable && !configurationBusy)
        renderError(.layout); renderError(.archive)
        let previewConfig = state.configurationDraft ?? state.owner.settings.configuration
        let valid = state.configurationDraft != nil
        geometryPreview.update(configuration: previewConfig, mode: state.owner.settings.arrivalMode, reduceMotion: product.accessibility.reduceMotion)
        arrivalPreview.update(configuration: previewConfig, mode: state.owner.settings.arrivalMode, reduceMotion: product.accessibility.reduceMotion)
        swallowPreview.update(configuration: previewConfig, mode: state.owner.settings.arrivalMode, reduceMotion: product.accessibility.reduceMotion)
        let previewNote = !valid ? "输入尚未有效，示意图暂用当前生效参数。" : model.hasLayoutDraft ? "草稿示意 · 尚未应用" : "布局示意 · 不读取真实截图"
        text("layoutPreview.detail", geometryPreview.geometrySummary + " · " + previewNote)
        let duration = product.accessibility.reduceMotion ? min(0.08, previewConfig.swallowDuration) : previewConfig.swallowDuration
        text("motion.effective", "示意吞噬时长 \(formatMilliseconds(duration)) ms" + (model.hasLayoutDraft ? "（包含参数草稿）" : "") + (product.accessibility.reduceMotion ? "。减少动态不会延长原本更短的时长。" : "。"))
        let issues = state.domains.values.filter(\.hasIssue).count + (product.appearance.failure == nil ? 0 : 1) + (product.login.notConfirmed ? 1 : 0)
        footerStatus.stringValue = model.hasLayoutDraft || model.hasArchiveDraft ? "有尚未应用的更改" : issues > 0 ? "\(issues) 项设置结果待确认；可在对应页面重试" : "即时设置独立保存 · 参数更改需应用"
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
        retryButtons[domain]?.isEnabled = canSave && !busy(domain) && (![SettingsDomain.layout, .placement, .display].contains(domain) || !configurationBusy)
    }
    func errorText(_ domain: SettingsDomain) -> String? {
        guard let state = model.snapshot.domains[domain] else { return nil }
        if let validation = state.validationFailure {
            switch validation {
            case .invalidArchive: return "请输入完整、有限且不小于 0 的小时数；0 表示不自动归档。"
            case .invalidNumber(let field): return "“\(fieldTitle(field))”不是有效数值。请完成输入后再应用。"
            case .invalidConfiguration: return "参数超出有效范围。尺寸应大于 0；藏入比例为 0–90%，时长为 0–3000 ms。草稿已保留。"
            case .displayUnavailable: return "所选显示器当前不可用，未保存新的显示器偏好。"
            case .inactiveLegacyField: return "已选择六点位置，旧版距顶部参数不再生效。请放弃这项旧参数草稿后重试。"
            }
        }
        guard state.saveFailure != nil else { return nil }
        let target: String
        switch state.pending {
        case .collectionPaused(let paused): target = paused ? "暂停收录" : "继续收录"
        case .hidden(let hidden): target = hidden ? "隐藏裂缝" : "显示裂缝"
        case .entryEnabled(let enabled): target = enabled ? "启用内置截图" : "关闭内置截图"
        case .captureMode: target = "默认截图方式"
        case .arrival: target = "入缝偏好"
        case .layout: target = "参数更改"
        case .placement: target = "边缘位置"
        case .display: target = "显示器偏好"
        case .archiveHours: target = "归档时限"
        case nil: target = "这项选择"
        }
        return "“\(target)”的保存结果尚未确认。控件显示当前有效状态；重试会保存同一个选择，其他设置成功不会清除此提示。"
    }
    var configurationBusy: Bool { [SettingsDomain.layout, .placement, .display].contains { busy($0) } }
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
        guard let popup = controls[id] as? NSPopUpButton, popup.itemArray.indices.contains(index) else { return }
        if popup.indexOfSelectedItem != index { popup.selectItem(at: index) }
    }
    func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."))
    }
    func formatMilliseconds(_ duration: Double) -> String { String(format: "%g", duration * 1000) }
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
    func playArrival() {
        guard selectedPage == .motion, window.isVisible else { return }
        flushEditor(); refreshDraftPresentation(); arrivalPreview.play()
    }
    func playSwallow() {
        guard selectedPage == .motion, window.isVisible else { return }
        flushEditor(); refreshDraftPresentation(); swallowPreview.play()
    }
}
