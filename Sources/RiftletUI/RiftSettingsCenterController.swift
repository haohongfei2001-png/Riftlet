import AppKit
import RiftletCapture

/// One native settings window over the existing owner/model. Rendering cannot
/// persist preferences, request permission, start capture, or reopen the window.
@MainActor
public final class RiftSettingsCenterController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSMenuDelegate {
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("RiftletSettingsCenter")
    public let window: NSWindow
    public var isVisible: Bool { window.isVisible }
    public private(set) var selectedPage: SettingsPage = .general

    let pageHeading = NSTextField(labelWithString: "")
    let model: SettingsStateModel
    let onAction: SettingsProductActionHandler
    var product: SettingsProductSnapshot
    let scroll = RiftVisualStyle.topAlignedScrollView()
    let footerStatus = SettingsNativeStyle.label("", role: "secondary")
    var pages: [SettingsPage: NSStackView] = [:]
    var navigation: [SettingsPage: NSButton] = [:]
    var labels: [String: NSTextField] = [:]
    var controls: [String: NSControl] = [:]
    // Natural-width actions use a full-width alignment container. Hide both
    // together so conditional recovery actions never leave empty rows.
    var actionContainers: [String: NSView] = [:]
    var numericFields: [SettingsField: NSTextField] = [:]
    var numericSliders: [SettingsField: NSSlider] = [:]
    var handlers: [ObjectIdentifier: () -> Void] = [:]
    var preferenceRecoveryRows: [SettingsPreferenceDomain: NSView] = [:]
    var errorRows: [SettingsDomain: NSStackView] = [:]
    var errorLabels: [SettingsDomain: NSTextField] = [:]
    var retryButtons: [SettingsDomain: NSButton] = [:]

    var disclosures: [String: (button: NSButton, content: NSView)] = [:]
    var pageWidthConstraints: [SettingsPage: NSLayoutConstraint] = [:]
    var pagePositionConstraints: [NSLayoutConstraint] = []
    var displayItems: [RiftSettingsDisplay] = []
    var displaySelection: UInt32?
    var displayMenuTracking = false
    var displayRefreshPending = false
    var archiveCustom = false
    var archiveField: NSTextField!
    var archiveCustomRow: NSView!
    var captureOptions: NSView!
    var automaticUpdatesRow: NSView!
    var trayFavorites: NSView!
    var commonEdgeSettings: NSView!
    var slitInsetFraction: NSView!

    var windChimeLineSetting: NSView!
    var windChimeSettings: NSView!
    var traySettings: NSView!
    var trayTintSettings: NSView!
    var trayOcclusionRow: NSView!
    var displayRow: NSView!
    var legacySection: NSView!
    var trayAppearanceSection: NSView!
    var geometryRows: [SettingsField: NSView] = [:]
    var previewTransparency: Double?
    var previewBodyColor: String?
    var pendingTone: Task<Void, Never>?
    var pendingPreview: Task<Void, Never>?
    var announcedErrors: [SettingsDomain: String] = [:]
    var editingTransparency = false
    var editingBodyColor = false
    var storageRequested = false
    let edgePreview = SettingsEdgeDiagram()
    let geometryPreview = RiftSettingsCenterPreview()
    // Consecutive edits to a single on-disk owner must run in event order.
    private var queuedSaves: [SettingsDomain: Task<Void, Never>] = [:]
    private var queuedSaveIDs: [SettingsDomain: UUID] = [:]
    private var submittingCloseEdit = false
    private var replacingEditor = false
    // Last value actually displayed or submitted. AppKit can deliver end-editing
    // on a focus-only visit without ever sending a begin-editing notification.
    var displayedEditorValues: [ObjectIdentifier: String] = [:]
    private var markedFields = Set<ObjectIdentifier>()
    private var allowClose = false
    private var hasPositioned = false
    private(set) var pendingCloseAlert: NSAlert?
    private var suspendedEditor: (field: NSTextField, selection: NSRange)?
    private var closingAfterApply = false
    private var closeSheetApproved = false
    private var closeKeyMonitor: Any?
    private var terminationCompletion: (@MainActor (Bool) -> Void)?

    public init(model: SettingsStateModel, onAction: @escaping SettingsProductActionHandler) {
        self.model = model; self.onAction = onAction
        product = SettingsProductSnapshot(revision: 0, setup: .init(), state: model.snapshot)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsNativeStyle.settingsSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.identifier = Self.windowIdentifier
        window.title = ProductCopy.text("Riftlet 设置", "Riftlet Settings")
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = SettingsNativeStyle.settingsMinimumSize
        window.delegate = self
        buildWindow()
        render()
    }

    /// The host is the only subscriber to model.onChange and projects all owners.
    public func update(_ snapshot: SettingsProductSnapshot) {
        guard snapshot.revision >= product.revision else { return }
        product = snapshot
        render()
    }

    public func show(page: SettingsPage = .general) {
        navigate(to: page)
        if !hasPositioned {
            // Replacing contentView and establishing Auto Layout can change the
            // constructor's size. Restore the V2 content size after that work,
            // once only; owner refreshes and later shows preserve user resizing.
            window.contentView?.layoutSubtreeIfNeeded()
            var contentSize = SettingsNativeStyle.settingsSize
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                let available = window.contentRect(forFrameRect: visible).size
                contentSize.width = min(contentSize.width, max(1, available.width))
                contentSize.height = min(contentSize.height, max(1, available.height))
                window.setContentSize(contentSize)
                window.setFrame(Self.firstPresentationFrame(window.frame, visibleFrame: visible), display: false)
            } else {
                window.setContentSize(contentSize); window.center()
            }
            if !product.reviewEnvironment && Bundle.main.bundleIdentifier == "com.riftlet.app" {
                let savedFrame: NSWindow.FrameAutosaveName = "RiftletConsumerSettings"
                if window.setFrameUsingName(savedFrame) {
                    let reachable = RiftVisualStyle.reachableWindowFrame(window.frame, visibleFrames: NSScreen.screens.map(\.visibleFrame), preferredFrame: window.screen?.visibleFrame)
                    window.setFrame(reachable, display: false)
                }
                window.setFrameAutosaveName(savedFrame)
            }
            hasPositioned = true
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func firstPresentationFrame(_ proposed: NSRect, visibleFrame: NSRect) -> NSRect {
        let size = NSSize(width: min(proposed.width, visibleFrame.width), height: min(proposed.height, visibleFrame.height))
        return NSRect(x: visibleFrame.minX + (visibleFrame.width - size.width) / 2,
                      y: visibleFrame.minY + (visibleFrame.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Host teardown is distinct from the user closing an edited form.
    public func closeForTeardown() {
        resolveTermination(false)
        allowClose = true
        let sheet = window.attachedSheet
        removeCloseKeyMonitor()
        pendingCloseAlert = nil
        closingAfterApply = false
        closeSheetApproved = false
        suspendedEditor = nil
        if let sheet { window.endSheet(sheet, returnCode: .abort) }
        window.close()
        allowClose = false
    }

    /// Explicit App Quit shares the existing draft decision. A repeated request
    /// cannot replace an unanswered callback; teardown never approves a Quit.
    public func requestCloseForTermination(_ completion: @escaping @MainActor (Bool) -> Void) {
        flushTrayAppearance()
        guard terminationCompletion == nil else { completion(false); return }
        guard window.attachedSheet == nil || pendingCloseAlert != nil else { completion(false); return }
        if commitActiveEditBeforeClose(termination: completion) { return }
        flushEditor()
        if pendingCloseAlert == nil && !needsCloseConfirmation && !persistenceBusy {
            completion(true)
            return
        }
        terminationCompletion = completion
        if !window.isVisible { show(page: selectedPage) }
        presentCloseConfirmation()
        refreshCloseButtons()
    }

    func buildWindow() {
        let canvas = SettingsWindowCanvas(frame: NSRect(origin: .zero, size: SettingsNativeStyle.settingsSize))
        let root = canvas.column
        window.contentView = canvas
        let nav = SettingsNativeStyle.stack([], vertical: false, spacing: 8)
        for page in SettingsPage.allCases {
            let button = makeButton(page.title, id: "nav.\(page.rawValue)") { [weak self] in self?.navigate(to: page) }
            button.bezelStyle = .texturedRounded
            button.setButtonType(.pushOnPushOff)
            button.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.setAccessibilityLabel(page.title)
            navigation[page] = button
            nav.addArrangedSubview(button)
        }
        scroll.identifier = .init("settings.center.scroll")
        scroll.setAccessibilityLabel(ProductCopy.text("设置页面", "Settings page"))
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        pageHeading.font = .systemFont(ofSize: 20, weight: .semibold)
        footerStatus.identifier = .init("settings.center.footerStatus")
        footerStatus.maximumNumberOfLines = 2
        footerStatus.alignment = .right
        footerStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let rule = NSBox()
        rule.boxType = .separator
        for view in [nav, rule, pageHeading, scroll, footerStatus] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            nav.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            nav.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            rule.topAnchor.constraint(equalTo: nav.bottomAnchor, constant: 8),
            rule.leadingAnchor.constraint(equalTo: root.leadingAnchor), rule.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pageHeading.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 24),
            pageHeading.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: pageHeading.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footerStatus.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -24),
            footerStatus.leadingAnchor.constraint(greaterThanOrEqualTo: pageHeading.trailingAnchor, constant: 12),
            footerStatus.centerYAnchor.constraint(equalTo: pageHeading.centerYAnchor)
        ])
        buildPages()
        mountPage(.general)
        window.initialFirstResponder = navigation[.general]
    }

    func navigate(to page: SettingsPage) {
        let destination = page.destination
        if page == .motion, let advanced = disclosures["display.advanced"], advanced.content.isHidden {
            advanced.button.performClick(nil)
        }
        if destination == selectedPage, scroll.documentView != nil {
            if page == .motion { scrollToMotion() }
            return
        }
        flushTrayAppearance()
        flushEditor()
        window.makeFirstResponder(nil)
        selectedPage = destination
        mountPage(destination)
        render()
        if page == .motion { scrollToMotion() }
        window.recalculateKeyViewLoop()
    }

    private func scrollToMotion() {
        window.contentView?.layoutSubtreeIfNeeded()
        guard let view = controls["arrival"] else { return }
        view.scrollToVisible(view.bounds)
    }

    func mountPage(_ page: SettingsPage) {
        guard let document = pages[page] else { return }
        NSLayoutConstraint.deactivate(pagePositionConstraints)
        NSLayoutConstraint.deactivate(Array(pageWidthConstraints.values))
        scroll.documentView = document
        pagePositionConstraints = [document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
                                   document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)]
        NSLayoutConstraint.activate(pagePositionConstraints)
        pageWidthConstraints[page]?.isActive = true
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        pageHeading.stringValue = page.title
        window.title = "Riftlet — \(page.title)"
    }

    func dispatch(_ action: SettingsProductAction) {
        // Native switches/pop-ups tentatively change themselves before invoking
        // their action. Immediately project actual owner state while awaiting it.
        render()
        let writer: SettingsDomain?
        switch action {
        case .settings(.setTrayBackgroundTransparency), .settings(.setTrayCameraBodyColor), .settings(.restoreLegacyCustom), .settings(.commitField), .settings(.restoreVisibleDefaults), .settings(.selectPlacement),
             .settings(.selectDisplay), .settings(.selectDesktopForm), .settings(.selectWindChimeArrangement),
             .settings(.selectTrayTheme), .settings(.selectTrayFavorite):
            writer = .layout
        case .settings(.commitArchive): writer = .archive
        case .settings(.retry(let domain)): writer = domain.writesConfiguration ? .layout : domain
        default: writer = nil
        }
        let prior = writer.flatMap { queuedSaves[$0] }
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            if let prior { await prior.value }
            guard let self else { return }
            await onAction(action)
            if let writer, queuedSaveIDs[writer] == id {
                queuedSaveIDs[writer] = nil
                queuedSaves[writer] = nil
            }
            render()
        }
        if let writer { queuedSaves[writer] = task; queuedSaveIDs[writer] = id }
    }

    @objc func invoked(_ sender: NSControl) {
        guard sender.isEnabled else { return }
        handlers[ObjectIdentifier(sender)]?()
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
            markedFields.insert(ObjectIdentifier(field))
            return
        }
        markedFields.remove(ObjectIdentifier(field))
        record(field)
        refreshDraftPresentation()
    }
    public func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        guard !allowClose, !submittingCloseEdit, !replacingEditor, pendingCloseAlert == nil,
              markedFields.remove(ObjectIdentifier(field)) == nil,
              (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        commitEditor(field)
    }
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText(),
              let field = control as? NSTextField else { return false }
        markedFields.remove(ObjectIdentifier(field))
        commitEditor(field)
        return true
    }

    private func commitEditor(_ field: NSTextField) {
        let text = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
        guard text != displayedEditorValues[ObjectIdentifier(field)] else { return }
        record(field)
        displayedEditorValues[ObjectIdentifier(field)] = text
        if field === archiveField, model.hasArchiveDraft {
            dispatch(.settings(.commitArchive(model.archiveDraftText)))
        } else if let key = numericFields.first(where: { $0.value === field })?.key,
                  let text = model.snapshot.layoutText[key] {
            dispatch(.settings(.commitField(key, text, maximumCount: countCapacity(model.snapshot.owner))))
        }
    }

    var visibleLegacyFields: Set<SettingsField> {
        let c = model.snapshot.owner.settings.configuration
        return product.legacyCustomFields.filter { field in
            switch field {
            case .outerInset: return c.desktopForm != .windChime
            case .windChimeLineInset: return c.desktopForm == .windChime
            case .fitWidth, .fitHeight, .rowPitch, .numberFontSize, .numberGap, .leftPadding:
                return c.desktopForm != .tray
            case .firstCenterFromTop: return c.placement == nil && c.desktopForm != .tray
            case .hiddenFraction: return c.desktopForm == .microSlit
            case .trayOcclusion: return c.desktopForm == .tray
            case .trayTintHue, .trayTintStrength: return c.desktopForm == .tray && c.trayTheme == .custom
            default: return false
            }
        }
    }

    private func finishAppearanceBeforeClose() -> Bool {
        guard editingBodyColor || editingTransparency || queuedSaves[.layout] != nil else { return false }
        flushTrayAppearance()
        let write = queuedSaves[.layout]
        Task { @MainActor [weak self] in
            await write?.value
            guard let self else { return }
            if needsCloseConfirmation { presentCloseConfirmation() }
            else { window.performClose(nil) }
        }
        return true
    }

    func restoreVisibleDefaults() {
        guard finishEditingForReplacement() else { return }
        let alert = NSAlert()
        let fields = visibleLegacyFields
        let resetTheme = product.hasLegacyTrayTheme && model.snapshot.owner.settings.configuration.desktopForm == .tray
        guard !fields.isEmpty || resetTheme else { return }
        alert.messageText = ProductCopy.text("恢复旧版自定义？", "Restore Legacy Defaults?")
        let names = fields.sorted { $0.rawValue < $1.rawValue }.map(fieldTitle)
            + (resetTheme ? [ProductCopy.text("托盘材质", "Tray Material")] : [])
        alert.informativeText = names.joined(separator: ProductCopy.text("、", ", "))
        alert.addButton(withTitle: ProductCopy.text("取消", "Cancel"))
        alert.addButton(withTitle: ProductCopy.text("恢复默认数值", "Restore Defaults")).identifier = .init("settings.center.defaults.confirm")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.dispatch(.settings(.restoreLegacyCustom(fields: fields, resetTheme: resetTheme))) }
        }
    }

    func record(_ field: NSTextField) {
        guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        let text = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
        if text == displayedEditorValues[ObjectIdentifier(field)] { return }
        if field === archiveField {
            if model.archiveDraftText != text { model.setArchiveDraftText(text) }
        } else if let key = numericFields.first(where: { $0.value === field })?.key,
                  model.text(for: key) != text {
            model.setDraftText(text, for: key)
        }
    }
    func flushEditor() {
        for field in numericFields.values where field.currentEditor() != nil { record(field) }
        if archiveField?.currentEditor() != nil { record(archiveField) }
    }
    /// Explicit replacement is different from a background refresh. Retire the
    /// old field editor first so its later end-edit notification cannot restore
    /// text that the user has just chosen to discard or replace with defaults.
    @discardableResult func finishEditingForReplacement() -> Bool {
        let fields = Array(numericFields.values) + [archiveField].compactMap { $0 }
        guard let field = fields.first(where: { $0.currentEditor() != nil }),
              let editor = field.currentEditor() as? NSTextView else { return true }
        replacingEditor = true
        defer { replacingEditor = false; markedFields.remove(ObjectIdentifier(field)) }
        if editor.hasMarkedText() {
            // This explicit discard/default action cancels unconfirmed input
            // through AppKit; it never treats a partial IME string as a Save.
            guard field.abortEditing() else {
                footerStatus.stringValue = ProductCopy.text("请先完成当前输入，再恢复或放弃更改。", "Finish editing this field before restoring or discarding changes.")
                return false
            }
        } else {
            record(field)
            guard window.makeFirstResponder(nil) else { return false }
        }
        return field.currentEditor() == nil
    }
    func replaceDrafts(_ command: SettingsCommand) {
        guard finishEditingForReplacement() else { return }
        dispatch(.settings(command))
    }

    public func menuWillOpen(_ menu: NSMenu) {
        if menu === (controls["display"] as? NSPopUpButton)?.menu { displayMenuTracking = true }
    }
    public func menuDidClose(_ menu: NSMenu) {
        guard menu === (controls["display"] as? NSPopUpButton)?.menu else { return }
        displayMenuTracking = false
        // Native item action is delivered after tracking ends. Do not replace
        // its represented display identity before that action has been read.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !displayMenuTracking, displayRefreshPending else { return }
            displayRefreshPending = false; renderDisplay()
        }
    }

    var needsCloseConfirmation: Bool {
        let state = model.snapshot
        return model.hasLayoutDraft || model.hasArchiveDraft || [SettingsDomain.layout, .archive].contains {
            state.domains[$0]?.hasIssue == true || state.domains[$0]?.isSaving == true
        }
    }

    /// Closing a valid focused editor is a commit, just like Tab or Return.
    /// Keep invalid edits and failed writes recoverable in the existing sheet.
    private func commitActiveEditBeforeClose(termination: (@MainActor (Bool) -> Void)? = nil) -> Bool {
        if submittingCloseEdit { termination?(false); return true }
        guard pendingCloseAlert == nil,
              let field = (Array(numericFields.values) + [archiveField].compactMap { $0 }).first(where: { $0.currentEditor() != nil }),
              let editor = field.currentEditor() as? NSTextView else { return false }
        if editor.hasMarkedText() {
            termination?(false)
            return true
        }
        guard editor.string != displayedEditorValues[ObjectIdentifier(field)] else { return false }
        record(field)
        let command: SettingsCommand
        if field === archiveField, model.hasArchiveDraft {
            guard let n = number(model.archiveDraftText), QueueArchivePolicy.minutesRange.contains(n) else { return false }
            command = .commitArchive(model.archiveDraftText)
        } else if let key = numericFields.first(where: { $0.value === field })?.key,
                  let text = model.snapshot.layoutText[key], number(text) != nil {
            command = .commitField(key, text, maximumCount: countCapacity(model.snapshot.owner))
        } else { return false }
        displayedEditorValues[ObjectIdentifier(field)] = editor.string
        submittingCloseEdit = true
        dispatch(.settings(command))
        let write = queuedSaves[field === archiveField ? .archive : .layout]
        Task { @MainActor [weak self] in
            await write?.value
            guard let self else { termination?(false); return }
            submittingCloseEdit = false
            if needsCloseConfirmation || persistenceBusy {
                termination?(false)
                if needsCloseConfirmation && window.isVisible { presentCloseConfirmation() }
            } else {
                finishUserClose()
                termination?(true)
            }
        }
        return true
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowClose { return true }
        if finishAppearanceBeforeClose() { return false }
        if commitActiveEditBeforeClose() { return false }
        flushEditor()
        if pendingCloseAlert != nil { return false }
        guard needsCloseConfirmation else { return true }
        presentCloseConfirmation()
        return false
    }

    func presentCloseConfirmation() {
        guard pendingCloseAlert == nil, window.attachedSheet == nil else { return }
        if let field = (Array(numericFields.values) + [archiveField].compactMap { $0 }).first(where: { $0.currentEditor() != nil }),
           let editor = field.currentEditor() as? NSTextView {
            suspendedEditor = (field, editor.selectedRange())
        }
        let alert = NSAlert()
        alert.messageText = ProductCopy.text("要保存更改后再关闭吗？", "Save changes before closing?")
        alert.alertStyle = .informational
        for (name, id) in [(ProductCopy.text("继续编辑", "Keep Editing"), "continue"), (ProductCopy.text("不保存", "Don’t Save"), "discard"), (ProductCopy.text("应用并关闭", "Apply and Close"), "apply")] {
            let button = alert.addButton(withTitle: name)
            button.identifier = .init("settings.center.close.\(id)")
            button.setAccessibilityLabel(name)
        }
        // A default button owns Return. Escape is scoped to this exact sheet
        // separately; assigning both keys to one button loses one of them.
        alert.window.defaultButtonCell = alert.buttons[0].cell as? NSButtonCell
        pendingCloseAlert = alert
        closeSheetApproved = false
        refreshCloseButtons()
        alert.beginSheetModal(for: window) { [weak self, weak alert] response in
            Task { @MainActor [weak self, weak alert] in
                guard let self, let alert, pendingCloseAlert === alert else { return }
                let approved = closeSheetApproved
                removeCloseKeyMonitor()
                pendingCloseAlert = nil
                closingAfterApply = false
                closeSheetApproved = false
                if approved && (response == .alertSecondButtonReturn || response == .alertThirdButtonReturn)
                    && !needsCloseConfirmation && (terminationCompletion == nil || !persistenceBusy) {
                    finishUserClose()
                    resolveTermination(true)
                } else {
                    restoreEditor()
                    resolveTermination(false)
                }
            }
        }
        // Keep this exact sheet open while awaiting an owner. NSAlert's default
        // button action ends it immediately, which would lose the Quit decision
        // on a failed/partial save. Continue remains usable during that wait.
        for button in alert.buttons { button.target = self; button.action = #selector(closeChoiceInvoked(_:)) }
        closeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak alert] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let alert, self.pendingCloseAlert === alert,
                      self.window.attachedSheet === alert.window, event.window === alert.window,
                      event.keyCode == 53, event.charactersIgnoringModifiers == "\u{1b}",
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
                alert.buttons[0].performClick(nil)
                return true
            }
            return handled ? nil : event
        }
    }
    private func removeCloseKeyMonitor() {
        if let closeKeyMonitor { NSEvent.removeMonitor(closeKeyMonitor) }
        closeKeyMonitor = nil
    }
    @objc private func closeChoiceInvoked(_ sender: NSButton) {
        guard let alert = pendingCloseAlert, let index = alert.buttons.firstIndex(where: { $0 === sender }) else { return }
        if index == 0 {
            window.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
            return
        }
        guard sender.isEnabled, !closingAfterApply else { return }
        if index == 1 && !finishEditingForReplacement() { return }
        closingAfterApply = true
        refreshCloseButtons()
        Task { @MainActor [weak self, weak alert] in
            guard let self, let alert, pendingCloseAlert === alert, window.attachedSheet === alert.window else { return }
            await onAction(.settings(index == 1 ? .discardDrafts : .applyDrafts(maximumCount: countCapacity(model.snapshot.owner))))
            // A continued edit, teardown, or newer sheet cannot be approved by
            // a receipt for the earlier decision. The owner write still stands.
            guard pendingCloseAlert === alert, window.attachedSheet === alert.window else { return }
            closingAfterApply = false
            render()
            guard !needsCloseConfirmation, terminationCompletion == nil || !persistenceBusy else { return }
            closeSheetApproved = true
            window.endSheet(alert.window, returnCode: index == 1 ? .alertSecondButtonReturn : .alertThirdButtonReturn)
        }
    }
    func refreshCloseButtons() {
        guard let alert = pendingCloseAlert else { return }
        let busy = closingAfterApply || [SettingsDomain.layout, .archive].contains { model.snapshot.domains[$0]?.isSaving == true }
            || (terminationCompletion != nil && persistenceBusy)
        let failed = [SettingsDomain.layout, .archive].contains { model.snapshot.domains[$0]?.saveFailure != nil }
        alert.buttons[1].isEnabled = !busy
        alert.buttons[2].isEnabled = !busy && product.capabilities.canEditPreferences
        alert.informativeText = busy
            ? ProductCopy.text("正在保存更改。你可以继续编辑，或在保存结束后关闭。", "Saving changes. You can keep editing or close when saving finishes.")
            : failed ? ProductCopy.text("更改尚未保存，草稿已保留。你可以继续编辑或重试“应用并关闭”。", "Your edits haven’t been saved. Keep editing or try Apply and Close again.")
            : ProductCopy.text("选择“不保存”会放弃尚未应用的更改。已生效的设置会保留。", "Don’t Save discards unapplied edits. Settings already applied are kept.")
    }
    private var persistenceBusy: Bool {
        // Appearance writes are synchronous on MainActor. Login registration
        // and model owners can yield, and must finish before approving Quit.
        !queuedSaves.isEmpty || model.snapshot.domains.values.contains(where: \.isSaving) || product.login.isBusy
    }
    private func resolveTermination(_ approved: Bool) {
        let completion = terminationCompletion
        terminationCompletion = nil
        completion?(approved)
    }
    private func restoreEditor() {
        guard let context = suspendedEditor else { return }
        suspendedEditor = nil
        guard context.field.window === window, !context.field.isHiddenOrHasHiddenAncestor else { return }
        window.makeFirstResponder(context.field)
        if let editor = context.field.currentEditor() as? NSTextView, !editor.hasMarkedText() {
            let count = (editor.string as NSString).length
            let start = min(context.selection.location, count)
            editor.setSelectedRange(NSRange(location: start, length: min(context.selection.length, count - start)))
        }
    }
    private func finishUserClose() {
        suspendedEditor = nil
        allowClose = true; window.close(); allowClose = false
    }

}


/// Content can grow vertically while the window size stays under user control.
@MainActor private final class SettingsWindowCanvas: NSView {
    let column = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(column)
        sizeColumn()
    }
    required init?(coder: NSCoder) { nil }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        sizeColumn()
    }

    private func sizeColumn() {
        let width = min(bounds.width, 768)
        column.frame = NSRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
    }
}
