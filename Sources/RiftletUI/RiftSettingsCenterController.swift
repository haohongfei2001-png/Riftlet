import AppKit
import RiftletCapture

/// One native settings window over the existing owner/model. Rendering cannot
/// persist preferences, request permission, start capture, or reopen the window.
@MainActor
public final class RiftSettingsCenterController: NSObject, NSWindowDelegate, NSMenuDelegate {
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("RiftletSettingsCenter")
    public let window: NSWindow
    public var isVisible: Bool { window.isVisible }
    public private(set) var selectedPage: SettingsPage = .general

    let pageHeading = NSTextField(labelWithString: "")
    let model: SettingsStateModel
    let onAction: SettingsProductActionHandler
    var product: SettingsProductSnapshot
    let scroll = RiftVisualStyle.topAlignedScrollView()
    var pages: [SettingsPage: NSStackView] = [:]
    var navigation: [SettingsPage: NSButton] = [:]
    var labels: [String: NSTextField] = [:]
    var controls: [String: NSControl] = [:]
    // Natural-width actions use a full-width alignment container. Hide both
    // together so conditional recovery actions never leave empty rows.
    var actionContainers: [String: NSView] = [:]
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
    var legacyUndo: (form: RiftDesktopForm, fields: [SettingsField: Double], theme: RiftTrayTheme?)?
    var captureOptions: NSView!
    var automaticUpdatesRow: NSView!
    var attachmentBrowserRow: NSView!
    var trayFavorites: NSView!

    var windChimeSettings: NSView!
    var displayRow: NSView!
    var legacySection: NSView!
    var trayAppearanceSection: NSView!
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
    private var allowClose = false
    private var hasPositioned = false
    private(set) var pendingCloseAlert: NSAlert?
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
        if snapshot.state.owner.settings.configuration.desktopForm != product.state.owner.settings.configuration.desktopForm { legacyUndo = nil }
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
        let canvas = SettingsWindowCanvas(frame: NSRect(origin: .zero, size: SettingsNativeStyle.settingsSize), maximumColumnWidth: .greatestFiniteMagnitude)
        window.contentView = canvas
        let root = canvas.column
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.setAccessibilityElement(false)
        let nav = SettingsNativeStyle.stack([], spacing: 3)
        nav.identifier = .init("settings.center.navigation")
        nav.setAccessibilityRole(.group)
        nav.setAccessibilityLabel(ProductCopy.text("设置分类", "Settings Categories"))
        let categories = SettingsPage.allCases
        for (index, page) in categories.enumerated() {
            let button = SettingsSidebarButton(page: page)
            configure(button, id: "nav.\(page.rawValue)") { [weak self] in self?.navigate(to: page) }
            button.refusesFirstResponder = false
            button.moveSelection = { [weak self] offset in
                guard let self, categories.indices.contains(index + offset) else { return }
                let next = categories[index + offset]
                navigate(to: next)
                window.makeFirstResponder(navigation[next])
            }
            navigation[page] = button
            nav.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: nav.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
        scroll.identifier = .init("settings.center.scroll")
        scroll.setAccessibilityLabel(ProductCopy.text("设置页面", "Settings Page"))
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        pageHeading.font = .systemFont(ofSize: 22, weight: .semibold)
        let rule = NSBox()
        rule.boxType = .separator
        let detail = SettingsWindowCanvas(frame: .zero)
        let column = detail.column
        for (view, parent) in [(sidebar as NSView, root), (nav, sidebar), (rule, root), (detail, root), (pageHeading, column), (scroll, column)] {
            view.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(view)
        }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor), sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 174),
            nav.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 17),
            nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            nav.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            rule.widthAnchor.constraint(equalToConstant: 1), rule.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            rule.topAnchor.constraint(equalTo: root.topAnchor), rule.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: rule.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            detail.topAnchor.constraint(equalTo: root.topAnchor), detail.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            pageHeading.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 24),
            pageHeading.topAnchor.constraint(equalTo: column.topAnchor, constant: 20),
            scroll.topAnchor.constraint(equalTo: pageHeading.bottomAnchor, constant: 3),
            scroll.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: column.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: column.bottomAnchor)
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
            navigation[destination]?.state = .on
            scrollToDeepLink(page)
            return
        }
        flushTrayAppearance()
        window.makeFirstResponder(nil)
        selectedPage = destination
        mountPage(destination)
        render()
        scrollToDeepLink(page)
        window.recalculateKeyViewLoop()
    }

    private func scrollToDeepLink(_ page: SettingsPage) {
        let id: String
        switch page {
        case .motion: id = "arrival"
        case .history: id = "archive.preset"
        default: return
        }
        window.contentView?.layoutSubtreeIfNeeded()
        guard let view = controls[id] else { return }
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
        window.title = ProductCopy.text("Riftlet 设置", "Riftlet Settings")
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
        let config = model.snapshot.owner.settings.configuration
        if let undo = legacyUndo, undo.form == config.desktopForm {
            dispatch(.settings(.restoreLegacyCustom(fields: Set(undo.fields.keys), resetTheme: undo.theme != nil, priorValues: undo.fields, priorTheme: undo.theme)))
            legacyUndo = nil
        } else {
            let fields = visibleLegacyFields
            let resetTheme = product.hasLegacyTrayTheme && config.desktopForm == .tray
            guard !fields.isEmpty || resetTheme else { return }
            legacyUndo = (config.desktopForm, Dictionary(uniqueKeysWithValues: fields.map { ($0, $0.value(in: config)) }), resetTheme ? config.trayTheme : nil)
            dispatch(.settings(.restoreLegacyCustom(fields: fields, resetTheme: resetTheme)))
        }
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

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowClose { return true }
        if finishAppearanceBeforeClose() { return false }
        if pendingCloseAlert != nil { return false }
        guard needsCloseConfirmation else { return true }
        presentCloseConfirmation()
        return false
    }

    func presentCloseConfirmation() {
        guard pendingCloseAlert == nil, window.attachedSheet == nil else { return }
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
    private func finishUserClose() {
        allowClose = true; window.close(); allowClose = false
    }

}


/// Content can grow vertically while the window size stays under user control.
@MainActor private final class SettingsSidebarButton: NSButton {
    var moveSelection: ((Int) -> Void)?

    init(page: SettingsPage) {
        super.init(frame: .zero)
        title = ""
        alternateTitle = ""
        bezelStyle = .recessed
        setButtonType(.pushOnPushOff)
        showsBorderOnlyWhileMouseInside = true
        setAccessibilityLabel(page.title)
        // The recessed cell dims its own unselected title even when the control
        // is enabled. Draw the row with AppKit's semantic label and symbol views.
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)
        icon.contentTintColor = .labelColor
        icon.setAccessibilityElement(false)
        let label = NSTextField(labelWithString: page.title)
        label.textColor = .labelColor
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.setAccessibilityElement(false)
        for view in [icon as NSView, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 17), icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            switch event.specialKey {
            case .upArrow: moveSelection?(-1); return
            case .downArrow: moveSelection?(1); return
            default: break
            }
        }
        super.keyDown(with: event)
    }
}

@MainActor private final class SettingsWindowCanvas: NSView {
    let column = NSView()
    let maximumColumnWidth: CGFloat

    init(frame: NSRect, maximumColumnWidth: CGFloat = 768) {
        self.maximumColumnWidth = maximumColumnWidth
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
        let width = min(bounds.width, maximumColumnWidth)
        column.frame = NSRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
    }
}
