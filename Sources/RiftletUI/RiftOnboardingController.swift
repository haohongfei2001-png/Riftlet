import AppKit

/// The host measures this only after an explicit Chrome check.
public enum OnboardingChromeConnection: Equatable, Sendable {
    case unchecked, checking, ready, javaScriptDisabled, noWindow, unavailable
}

public extension SettingsProductSnapshot {
    var onboardingReady: Bool { !reviewEnvironment && firstIncompleteOnboardingStep == nil }

    fileprivate var firstIncompleteOnboardingStep: Int? {
        guard capabilities.initialized, setup.source == .accessible, setup.collection == .collecting,
              !state.owner.collectionPaused, !state.owner.isHidden, !setup.isHidden else { return 0 }
        switch setup.issue {
        case .initializationFailed, .sourceAccess, .wrongScreenshotFolder, .screenshotFolderNeedsSelection,
             .insufficientSpace, .privateWriteFailed, .sourceVolumeUnidentified: return 0
        default: break
        }
        switch setup.storage {
        case .insufficientSpace, .writeFailed: return 0
        default: break
        }
        guard setup.attachment == .available, setup.permission == .granted,
              chromeConnection == .ready, setup.issue != .chromeJavaScriptDisabled else { return 1 }
        for domain in [SettingsDomain.placement, .display] {
            if let setting = state.domains[domain], setting.isSaving || setting.hasIssue { return 2 }
        }
        return nil
    }
}

/// Three-step guidance uses the same host facts and explicit settings commands.
/// Its only local state is navigation; it stores no permission/completion flags.
@MainActor
public final class RiftOnboardingController: NSObject, NSWindowDelegate, NSMenuDelegate {
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("RiftletOnboarding")
    public let window: NSWindow
    public private(set) var currentStep = 0
    public private(set) var presentationID = UUID()
    public var isVisible: Bool { window.isVisible }
    private let onDefer: @MainActor () -> Void
    private let onAction: SettingsProductActionHandler
    private var snapshot: SettingsProductSnapshot?
    private var hasPresented = false
    private var finishing = false
    private var busy: Set<SettingsDomain> = []
    private var controls: [String: NSView] = [:]
    private var pages: [NSView] = []
    private let progress = SettingsNativeStyle.stack([], vertical: false, spacing: 9)
    private let content = RiftVisualStyle.documentStack([], spacing: 16)
    private let scroll = RiftVisualStyle.topAlignedScrollView()
    private lazy var next = SettingsNativeStyle.button(copy.continueButton)
    private lazy var back = SettingsNativeStyle.button(copy.back)
    private lazy var later = SettingsNativeStyle.button(copy.later)
    private lazy var introTitle = SettingsNativeStyle.label(copy.headline, role: "title")
    private let introDescription = SettingsNativeStyle.label("")
    private let introCapability = SettingsNativeStyle.label("", role: "secondary")
    private let sourceDetail = SettingsNativeStyle.label("", role: "secondary")
    private let sourcePath = SettingsNativeStyle.label("", role: "caption")
    private let automationDetail = SettingsNativeStyle.label("", role: "secondary")
    private let scriptDetail = SettingsNativeStyle.label("")
    private let connectionStatus = SettingsNativeStyle.label("", role: "secondary")
    private lazy var chromeMenuSection = section(copy.chromeMenuHeading, symbol: "menubar.rectangle", views: [scriptDetail, connectionStatus, actionButton(copy.checkConnection, id: "onboarding.checkChrome")])
    private lazy var sourceAccess = SettingsNativeStyle.button(copy.allowAccess)
    private lazy var automation = SettingsNativeStyle.button(copy.checkPermission)
    private let display = NSPopUpButton(frame: .zero, pullsDown: false)
    private var displayMenuTracking = false
    private var displayRefreshPending = false
    private var displaySignature: [RiftSettingsDisplay] = []
    private var representedPreferredDisplayID: UInt32?
    private lazy var placementPreview = RiftOnboardingPlacementPreview(copy: copy)
    private var placements: [RiftPlacement: NSButton] = [:]
    private let placementHint = SettingsNativeStyle.label("", role: "caption")
    private let placementError = SettingsNativeStyle.label("", role: "secondary")
    private let displayError = SettingsNativeStyle.label("", role: "secondary")
    private let finishHint = SettingsNativeStyle.label("", role: "secondary")

    private let copy: OnboardingCopy

    public convenience init(onDefer: @escaping @MainActor () -> Void = {}, onAction: @escaping SettingsProductActionHandler) {
        self.init(copy: .current, onDefer: onDefer, onAction: onAction)
    }

    init(copy: OnboardingCopy, onDefer: @escaping @MainActor () -> Void = {}, onAction: @escaping SettingsProductActionHandler) {
        self.copy = copy
        self.onDefer = onDefer
        self.onAction = onAction
        window = RiftVisualStyle.window(outerSize: SettingsNativeStyle.onboardingSize,
            minimum: NSSize(width: 520, height: 416), title: copy.title)
        super.init()
        window.identifier = Self.windowIdentifier
        window.delegate = self
        window.animationBehavior = .none
        window.autorecalculatesKeyViewLoop = true
        configureContent()
        refreshStep()
    }

    public func update(_ value: SettingsProductSnapshot) {
        guard snapshot.map({ value.revision >= $0.revision }) ?? true else { return }
        snapshot = value
        refreshFacts()
    }

    /// The host records the first presentation separately from successful setup.
    /// This never writes a first-use/completion preference itself.
    @discardableResult
    public func show() -> Bool {
        guard snapshot != nil, let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return false }
        let previousFrame = window.frame
        if !isVisible {
            presentationID = UUID()
            currentStep = 0; finishing = false
            refreshStep()
        }
        if !hasPresented {
            var outer = SettingsNativeStyle.onboardingSize
            let visible = screen.visibleFrame
            outer.width = min(outer.width, visible.width)
            outer.height = min(outer.height, visible.height)
            let frame = NSRect(x: visible.midX - outer.width / 2, y: visible.midY - outer.height / 2,
                               width: outer.width, height: outer.height)
            layout(keeping: frame)
        } else {
            let reachable = RiftVisualStyle.reachableWindowFrame(previousFrame,
                visibleFrames: NSScreen.screens.map(\.visibleFrame), preferredFrame: window.screen?.visibleFrame)
            layout(keeping: reachable)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hasPresented = window.isVisible
        return window.isVisible
    }

    public func closeForTeardown() { window.close() }
    public func control(identifier: String) -> NSView? { controls[identifier] }

    private func layout(keeping frame: NSRect) {
        // Wrapping text and hidden stack pages can change the native fitting
        // width. Complete that pass first, then restore the explicit window
        // size; never read a fitting result back as the user's resize choice.
        // Do not run a second eager layout/center pass after applying this size.
        window.contentView?.layoutSubtreeIfNeeded()
        guard window.frame != frame else { return }
        window.setContentSize(window.contentRect(forFrameRect: frame).size)
        window.setFrame(frame, display: false)
    }

    private func configureContent() {
        let root = SettingsSurfaceView(role: .window)
        window.contentView = root
        progress.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(progress); root.addSubview(scroll)
        for (index, title) in [copy.stepFolder, copy.stepChrome, copy.stepPosition].enumerated() {
            if index > 0 {
                let separator = NSImageView()
                separator.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 9, weight: .regular))
                separator.contentTintColor = .tertiaryLabelColor
                separator.setAccessibilityElement(false)
                progress.addArrangedSubview(separator)
            }
            let label = SettingsNativeStyle.label(title, role: "caption")
            label.tag = index
            label.identifier = .init("onboarding.progress.\(index)")
            progress.addArrangedSubview(label)
        }
        scroll.documentView = content
        scroll.setAccessibilityLabel(copy.scrollLabel)
        next.identifier = .init("onboarding.next"); next.target = self; next.action = #selector(nextStep)
        next.keyEquivalent = "\r"; next.bezelColor = SettingsNativeStyle.color(.accent)
        back.identifier = .init("onboarding.back"); back.target = self; back.action = #selector(previousStep)
        later.identifier = .init("onboarding.later"); later.target = self; later.action = #selector(deferSetup)
        later.keyEquivalent = "\u{1b}"
        let footer = SettingsNativeStyle.stack([back, later, NSView(), next], vertical: false, spacing: 12)
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.arrangedSubviews[2].setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addSubview(footer)
        for button in [next, back, later] {
            controls[button.identifier!.rawValue] = button
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        }
        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            progress.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -26),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            scroll.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 13),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22)
        ])
        introDescription.identifier = .init("onboarding.introDescription")
        introCapability.identifier = .init("onboarding.capability")
        controls["onboarding.introDescription"] = introDescription
        controls["onboarding.capability"] = introCapability
        introTitle.font = .systemFont(ofSize: 28, weight: .semibold)
        sourceAccess.identifier = .init("onboarding.sourceAccess")
        sourceAccess.target = self; sourceAccess.action = #selector(actionPressed(_:))
        controls["onboarding.sourceAccess"] = sourceAccess
        automation.identifier = .init("onboarding.automation")
        automation.target = self; automation.action = #selector(actionPressed(_:))
        controls["onboarding.automation"] = automation
        sourceDetail.identifier = .init("onboarding.sourceStatus")
        automationDetail.identifier = .init("onboarding.automationStatus")
        scriptDetail.identifier = .init("onboarding.scriptStatus")
        controls["onboarding.scriptStatus"] = scriptDetail
        controls["onboarding.sourceStatus"] = sourceDetail
        controls["onboarding.automationStatus"] = automationDetail
        controls["onboarding.connectionStatus"] = connectionStatus
        let intro = page([
            introTitle, introDescription,
            section(copy.folderHeading, symbol: "folder", views: [
                sourcePath, sourceDetail, sourceAccess,
                actionButton(copy.resume, id: "onboarding.resume"),
                actionButton(copy.unhide, id: "onboarding.unhide"),
                actionButton(copy.recheckFolder, id: "onboarding.recheck")
            ]),
            introCapability, RiftOnboardingPlacementPreview(workflow: true, copy: copy)
        ])
        let connections = page([
            SettingsNativeStyle.label(copy.chromeHeading, role: "title"),
            section(copy.automationHeading, symbol: "macwindow", views: [automationDetail, automation]),
            chromeMenuSection
        ])
        display.identifier = .init("onboarding.display"); display.setAccessibilityLabel(copy.display)
        display.target = self; display.action = #selector(displayChanged)
        display.menu?.delegate = self
        display.menu?.autoenablesItems = false
        display.font = .systemFont(ofSize: 13)
        display.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        controls["onboarding.display"] = display
        let choices = SettingsNativeStyle.stack([], vertical: false, spacing: 1)
        choices.distribution = .fillEqually
        for placement in RiftPlacement.allCases {
            let button = SettingsNativeStyle.button(copy.placement(placement))
            button.setButtonType(.pushOnPushOff); button.bezelStyle = .roundRect
            button.identifier = .init("onboarding.placement." + placement.rawValue)
            button.target = self; button.action = #selector(placementChanged(_:))
            button.setAccessibilityLabel(copy.positionLabel(placement))
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
            placements[placement] = button; controls[button.identifier!.rawValue] = button
            choices.addArrangedSubview(button)
        }
        let displayRetry = actionButton(copy.retryDisplay, id: "onboarding.retryDisplay")
        let placementRetry = actionButton(copy.retryPosition, id: "onboarding.retryPlacement")
        let displayRow = SettingsNativeStyle.stack([SettingsNativeStyle.label(copy.display, role: "rowTitle"), display, NSView()],
                                                  vertical: false, spacing: 8)
        controls["onboarding.finishHint"] = finishHint
        let placementPage = page([
            SettingsNativeStyle.label(copy.positionHeading, role: "title"),
            SettingsNativeStyle.label(copy.positionDetail, role: "secondary"),
            placementPreview, choices, displayRow,
            displayError, displayRetry, placementError, placementRetry, placementHint, finishHint
        ])
        pages = [intro, connections, placementPage]
        for page in pages {
            content.addArrangedSubview(page)
            page.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        window.initialFirstResponder = next
        root.setAccessibilityLabel(copy.rootLabel)
    }

    private func page(_ views: [NSView]) -> NSView {
        let value = SettingsNativeStyle.stack(views, spacing: 12)
        for view in views { view.widthAnchor.constraint(equalTo: value.widthAnchor).isActive = true }
        return value
    }

    private func section(_ title: String, symbol: String, views: [NSView]) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = SettingsNativeStyle.color(.accentInk)
        icon.setAccessibilityElement(false)
        let header = SettingsNativeStyle.stack([icon, SettingsNativeStyle.label(title, role: "heading"), NSView()],
                                             vertical: false, spacing: 8)
        let line = NSBox(); line.boxType = .separator
        let stack = SettingsNativeStyle.stack([line, header] + views, spacing: 5)
        for child in stack.arrangedSubviews where !(child is NSButton) {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func actionButton(_ title: String, id: String) -> NSButton {
        let value = SettingsNativeStyle.button(title)
        value.identifier = .init(id); value.target = self; value.action = #selector(actionPressed(_:))
        value.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        controls[id] = value
        return value
    }

    private func refreshFacts() {
        guard let snapshot else { return }
        let preservedFrame = hasPresented ? window.frame : nil
        defer { if let preservedFrame { layout(keeping: preservedFrame) } }
        let presentation = SetupPresentation(snapshot: snapshot.setup)
        let ordinary = snapshot.setup.attachment == .available || snapshot.reviewEnvironment
        introTitle.stringValue = ordinary ? copy.headline : copy.introduction(presentation).title
        introDescription.stringValue = ordinary
            ? copy.introDetail
            : copy.introduction(presentation).detail
        introCapability.stringValue = snapshot.reviewEnvironment
            ? copy.reviewDetail : ""
        introCapability.isHidden = introCapability.stringValue.isEmpty
        sourceDetail.stringValue = sourceStatus(snapshot)
        sourcePath.stringValue = presentation.sourcePath
        sourcePath.isHidden = !presentation.hasSourceLocation
        sourceAccess.title = copy.authorizeFolder
        sourceAccess.setAccessibilityLabel(sourceAccess.title)
        sourceAccess.isHidden = !presentation.needsSourceAccess
        sourceAccess.isEnabled = snapshot.capabilities.canChooseSource && !sourceAccess.isHidden
        configureAction("onboarding.resume", visible: snapshot.state.owner.collectionPaused,
                        enabled: snapshot.capabilities.canChangeCollection && !busy.contains(.collection))
        configureAction("onboarding.unhide", visible: snapshot.state.owner.isHidden,
                        enabled: snapshot.capabilities.canChangeVisibility && !busy.contains(.visibility))
        configureAction("onboarding.recheck", visible: snapshot.firstIncompleteOnboardingStep == 0,
                        enabled: snapshot.capabilities.canRecheck)
        automationDetail.stringValue = copy.automationStatus(presentation)
        automation.title = copy.permissionAction(presentation)
        automation.setAccessibilityLabel(automation.title)
        automation.isHidden = snapshot.setup.permission == .notNeeded || snapshot.setup.permission == .granted
        automation.isEnabled = !automation.isHidden && snapshot.capabilities.canRequestAutomation && presentation.canRequestPermission
        if snapshot.setup.permission == .notRunning || snapshot.setup.permission == .browserUnavailable {
            automation.title = copy.recheckChrome
            automation.setAccessibilityLabel(automation.title)
            automation.isEnabled = snapshot.capabilities.canRecheck
        }
        scriptDetail.stringValue = copy.chromeInstructions(presentation)
        chromeMenuSection.isHidden = presentation.chromeScriptInstructions == nil
        connectionStatus.stringValue = chromeStatus(snapshot.chromeConnection)
        let chromeCheck = controls["onboarding.checkChrome"] as? NSButton
        chromeCheck?.title = snapshot.chromeConnection == .unchecked ? copy.checkConnection : copy.recheckConnection
        if let chromeCheck { chromeCheck.setAccessibilityLabel(chromeCheck.title) }
        chromeCheck?.isEnabled = snapshot.setup.permission == .granted && snapshot.chromeConnection != .checking
        let settings = snapshot.state.owner.settings
        refreshDisplay()
        for (placement, button) in placements {
            button.state = settings.configuration.placement == placement ? .on : .off
            button.isEnabled = snapshot.capabilities.canEditPreferences
                && snapshot.state.domains[.placement]?.isSaving != true && !busy.contains(.placement)
            button.contentTintColor = button.state == .on ? SettingsNativeStyle.color(.accentInk) : SettingsNativeStyle.color(.ink)
        }
        placementPreview.configuration = settings.configuration
        placementPreview.entryEnabled = settings.entryEnabled
        placementHint.stringValue = settings.configuration.placement == nil
            ? copy.legacyPosition
            : ""
        placementHint.isHidden = placementHint.stringValue.isEmpty && !settings.displayRestoreAvailable
        if settings.displayRestoreAvailable {
            placementHint.stringValue += copy.fallbackDisplay
        }
        updateError(.display, label: displayError, retryID: "onboarding.retryDisplay")
        updateError(.placement, label: placementError, retryID: "onboarding.retryPlacement")
        if snapshot.reviewEnvironment {
            finishHint.stringValue = copy.previewFinish
        } else {
            switch snapshot.firstIncompleteOnboardingStep {
            case 0: finishHint.stringValue = copy.finishFolder
            case 1: finishHint.stringValue = copy.finishChrome
            case 2: finishHint.stringValue = ""
            default: finishHint.stringValue = copy.finishReady
            }
        }
        finishHint.isHidden = finishHint.stringValue.isEmpty
        refreshNext()
        window.initialFirstResponder = firstAction
    }

    private var firstAction: NSButton {
        let ids: [String]
        switch currentStep {
        case 0: ids = ["onboarding.resume", "onboarding.unhide", "onboarding.sourceAccess", "onboarding.recheck"]
        case 1: ids = ["onboarding.automation", "onboarding.checkChrome"]
        default: ids = []
        }
        if !next.isEnabled {
            for id in ids {
                if let button = controls[id] as? NSButton, button.isEnabled && !button.isHiddenOrHasHiddenAncestor {
                    return button
                }
            }
        }
        return next.isEnabled ? next : later
    }

    private func sourceStatus(_ snapshot: SettingsProductSnapshot) -> String {
        switch snapshot.setup.issue {
        case .sourceAccess: return copy.folderUnreadable
        case .wrongScreenshotFolder, .screenshotFolderNeedsSelection: return copy.wrongFolder
        case .initializationFailed: return copy.startupFailed
        case .insufficientSpace, .privateWriteFailed, .sourceVolumeUnidentified: return copy.storageIssue(snapshot.setup.issue)
        default: break
        }
        switch snapshot.setup.storage {
        case .insufficientSpace: return copy.lowSpace
        case .writeFailed: return copy.writeFailed
        default: break
        }
        if snapshot.state.owner.collectionPaused { return copy.paused }
        if snapshot.state.owner.isHidden { return copy.hidden }
        switch snapshot.setup.source {
        case .accessible: return snapshot.setup.collection == .collecting ? copy.collecting : copy.starting
        case .checking, .notChecked: return copy.checkingFolder
        case .notApplicable: return copy.unusedFolder
        case .notConfigured: return copy.configureFolder
        case .unavailable: return copy.chooseFolder
        }
    }

    private func chromeStatus(_ state: OnboardingChromeConnection) -> String {
        switch state {
        case .unchecked: return copy.unchecked
        case .checking: return copy.checking
        case .ready: return copy.connected
        case .javaScriptDisabled: return copy.jsDisabled
        case .noWindow: return copy.noWindow
        case .unavailable: return copy.unavailable
        }
    }

    private func configureAction(_ id: String, visible: Bool, enabled: Bool) {
        let button = controls[id] as? NSButton
        button?.isHidden = !visible
        button?.isEnabled = visible && enabled
    }

    private func updateError(_ domain: SettingsDomain, label: NSTextField, retryID: String) {
        guard let snapshot else { return }
        let state = snapshot.state.domains[domain]
        let failed = state?.hasIssue == true
        label.stringValue = failed ? copy.saveError(display: domain == .display) : ""
        label.textColor = SettingsNativeStyle.color(.warning)
        label.isHidden = !failed
        let retry = controls[retryID] as? NSButton
        retry?.isHidden = state?.saveFailure == nil
        retry?.isEnabled = snapshot.capabilities.canEditPreferences && state?.pending != nil
            && state?.isSaving != true && !busy.contains(domain)
    }

    private func refreshDisplay() {
        guard let snapshot else { return }
        guard !displayMenuTracking else { displayRefreshPending = true; return }
        let settings = snapshot.state.owner.settings
        let preferred = settings.configuration.preferredDisplayID ?? settings.preferredDisplayID
        if displaySignature != settings.displays || representedPreferredDisplayID != preferred || display.numberOfItems == 0 {
            displaySignature = settings.displays; representedPreferredDisplayID = preferred
            display.removeAllItems()
            let primary = NSMenuItem(title: copy.primaryDisplay, action: nil, keyEquivalent: "")
            primary.representedObject = NSNull(); display.menu?.addItem(primary)
            for screen in settings.displays {
                // addItem(withTitle:) deduplicates equal titles. Each physical
                // display instead gets its own native item and stable identity.
                let item = NSMenuItem(title: screen.name, action: nil, keyEquivalent: "")
                item.representedObject = NSNumber(value: screen.id)
                display.menu?.addItem(item)
            }
            if let preferred, !settings.displays.contains(where: { $0.id == preferred }) {
                let item = NSMenuItem(title: copy.disconnectedDisplay, action: nil, keyEquivalent: "")
                item.representedObject = NSNumber(value: preferred); item.isEnabled = false
                display.menu?.addItem(item)
            }
        }
        if let item = display.itemArray.first(where: { item in
            if let preferred { return (item.representedObject as? NSNumber)?.uint32Value == preferred }
            return item.representedObject is NSNull
        }) { display.select(item) }
        display.isEnabled = snapshot.capabilities.canEditPreferences && !settings.displays.isEmpty
            && snapshot.state.domains[.display]?.isSaving != true && !busy.contains(.display)
    }

    public func menuWillOpen(_ menu: NSMenu) {
        if menu === display.menu { displayMenuTracking = true }
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard menu === display.menu else { return }
        displayMenuTracking = false
        // Let the native picker action read the item that was actually chosen
        // before a queued background display-list refresh can replace it.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !displayMenuTracking, displayRefreshPending else { return }
            displayRefreshPending = false; refreshDisplay()
        }
    }

    private func refreshStep() {
        let preservedFrame = hasPresented ? window.frame : nil
        defer { if let preservedFrame { layout(keeping: preservedFrame) } }
        for (index, page) in pages.enumerated() { page.isHidden = index != currentStep }
        for view in progress.arrangedSubviews {
            guard let label = view as? NSTextField else { continue }
            let index = label.tag
            label.textColor = SettingsNativeStyle.color(index == currentStep ? .accentInk : .secondary)
            label.font = .systemFont(ofSize: 11, weight: index == currentStep ? .semibold : .regular)
        }
        progress.setAccessibilityLabel(copy.progress(step: currentStep + 1))
        back.isHidden = currentStep == 0
        refreshNext()
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        window.recalculateKeyViewLoop()
        window.initialFirstResponder = firstAction
        if window.isKeyWindow { window.makeFirstResponder(firstAction) }
    }

    private func refreshNext() {
        let incomplete = snapshot?.firstIncompleteOnboardingStep
        let preview = snapshot?.reviewEnvironment == true
        if currentStep < 2 {
            next.title = !preview && currentStep == 1 && incomplete == 0 ? copy.setUpFolder : copy.continueButton
            next.isEnabled = snapshot != nil && (preview || incomplete != currentStep)
        } else {
            switch (preview, incomplete) {
            case (true, _): next.title = copy.endPreview
            case (false, 0): next.title = copy.setUpFolder
            case (false, 1): next.title = copy.stepChrome
            default: next.title = copy.getStarted
            }
            let changingPosition = busy.contains(.placement) || busy.contains(.display)
            next.isEnabled = !finishing && snapshot != nil && (preview || (!changingPosition && incomplete != 2))
        }
        next.setAccessibilityLabel(next.title)
    }

    @objc private func previousStep() { guard currentStep > 0 else { return }; currentStep -= 1; refreshStep() }
    @objc private func nextStep() {
        guard next.isEnabled, let snapshot else { return }
        if currentStep < 2 {
            if !snapshot.reviewEnvironment, let missing = snapshot.firstIncompleteOnboardingStep,
               missing < currentStep { currentStep = missing } else { currentStep += 1 }
            refreshStep(); return
        }
        if snapshot.reviewEnvironment { window.performClose(nil); return }
        if let step = snapshot.firstIncompleteOnboardingStep {
            currentStep = step; refreshStep(); return
        }
        guard snapshot.onboardingReady, !finishing, !busy.contains(.display), !busy.contains(.placement) else { return }
        finishing = true; refreshNext()
        let session = presentationID
        Task {
            guard session == presentationID, isVisible else { return }
            await onAction(.finishOnboarding)
            guard session == presentationID else { return }
            finishing = false; refreshNext()
        }
    }
    @objc private func deferSetup() {
        onDefer()
        window.performClose(nil)
    }

    @objc private func actionPressed(_ sender: NSButton) {
        guard sender.isEnabled, !sender.isHiddenOrHasHiddenAncestor, let snapshot else { return }
        switch sender.identifier?.rawValue {
        case "onboarding.sourceAccess":
            guard snapshot.capabilities.canChooseSource else { return }; send(.chooseSourceAccess)
        case "onboarding.resume": send(.settings(.setCollectionPaused(false)), domain: .collection)
        case "onboarding.unhide": send(.settings(.setHidden(false)), domain: .visibility)
        case "onboarding.automation":
            if snapshot.setup.permission == .notRunning || snapshot.setup.permission == .browserUnavailable {
                send(.recheck)
            } else if snapshot.capabilities.canRequestAutomation {
                send(.requestAutomation)
            }
        case "onboarding.checkChrome":
            guard snapshot.setup.permission == .granted, snapshot.chromeConnection != .checking else { return }
            send(.checkChromeConnection)
        case "onboarding.recheck":
            guard snapshot.capabilities.canRecheck else { return }; send(.recheck)
        case "onboarding.retryDisplay": send(.settings(.retry(.display)), domain: .display)
        case "onboarding.retryPlacement": send(.settings(.retry(.placement)), domain: .placement)
        default: break
        }
    }

    @objc private func displayChanged() {
        guard display.isEnabled, snapshot?.capabilities.canEditPreferences == true,
              let item = display.selectedItem else { return }
        let target: UInt32?
        if item.representedObject is NSNull { target = nil }
        else if let number = item.representedObject as? NSNumber { target = number.uint32Value }
        else { return }
        send(.settings(.selectDisplay(target)), domain: .display)
    }

    @objc private func placementChanged(_ sender: NSButton) {
        guard sender.isEnabled, let placement = placements.first(where: { $0.value === sender })?.key else { return }
        send(.settings(.selectPlacement(placement)), domain: .placement)
    }

    private func send(_ action: SettingsProductAction, domain: SettingsDomain? = nil) {
        if let domain {
            guard !busy.contains(domain) else { refreshFacts(); return }
            busy.insert(domain); refreshFacts()
        }
        Task { [weak self] in
            guard let self else { return }
            await self.onAction(action)
            if let domain { self.busy.remove(domain); self.refreshFacts() }
        }
    }
}
