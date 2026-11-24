import AppKit

/// Connection to the browser identified by the matching SetupSnapshot.
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
        return nil
    }
}

/// Two-step guidance uses the same host facts and explicit settings commands.
/// Its only local state is navigation; it stores no permission/completion flags.
@MainActor
public final class RiftOnboardingController: NSObject, NSWindowDelegate {
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
    private lazy var workflowPreview = RiftOnboardingPlacementPreview(workflow: true, copy: copy)
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
    private var closedByOwner = false
    private var didDefer = false

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
            currentStep = 0; finishing = false; didDefer = false
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

    public func closeForTeardown() {
        closedByOwner = true
        window.close()
        closedByOwner = false
    }
    public func windowWillClose(_ notification: Notification) {
        guard hasPresented, !closedByOwner, !didDefer else { return }
        didDefer = true
        onDefer()
    }
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
        for (index, title) in [copy.stepFolder, copy.stepChrome].enumerated() {
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
        controls["onboarding.workflowPreview"] = workflowPreview
        let intro = page([
            introTitle, introDescription,
            section(copy.folderHeading, symbol: "folder", views: [
                sourcePath, sourceDetail, sourceAccess,
                actionButton(copy.filePrivacy, id: "onboarding.filePrivacy"),
                actionButton(copy.resume, id: "onboarding.resume"),
                actionButton(copy.unhide, id: "onboarding.unhide"),
                actionButton(copy.recheckFolder, id: "onboarding.recheck")
            ]),
            introCapability, workflowPreview
        ])
        let connections = page([
            SettingsNativeStyle.label(copy.chromeHeading, role: "title"),
            section(copy.automationHeading, symbol: "macwindow", views: [automationDetail, automation]),
            chromeMenuSection
        ])
        pages = [intro, connections]
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
        let presentation = SetupPresentation(snapshot: snapshot.setup, copy: copy)
        let ordinary = snapshot.setup.attachment == .available || snapshot.reviewEnvironment
        introTitle.stringValue = ordinary ? copy.headline : copy.introduction(presentation).title
        introDescription.stringValue = ordinary
            ? copy.introDetail
            : copy.introduction(presentation).detail
        introCapability.stringValue = snapshot.reviewEnvironment
            ? copy.reviewDetail : ""
        introCapability.isHidden = introCapability.stringValue.isEmpty
        sourceDetail.stringValue = sourceStatus(snapshot)
        sourcePath.stringValue = presentation.hasSourceLocation
            ? (presentation.sourcePath as NSString).abbreviatingWithTildeInPath : ""
        sourcePath.toolTip = presentation.sourcePath
        sourcePath.isHidden = !presentation.hasSourceLocation
        sourceAccess.title = copy.authorizeFolder
        sourceAccess.setAccessibilityLabel(sourceAccess.title)
        sourceAccess.isHidden = !snapshot.capabilities.initialized || snapshot.setup.source == .checking || !presentation.needsSourceAccess
        sourceAccess.isEnabled = snapshot.capabilities.canChooseSource && !snapshot.setup.isChecking && !sourceAccess.isHidden
        configureAction("onboarding.filePrivacy", visible: snapshot.setup.issue == .sourceAccess && !snapshot.reviewEnvironment,
                        enabled: snapshot.capabilities.canChooseSource && !snapshot.setup.isChecking)
        workflowPreview.isHidden = !sourceAccess.isHidden || controls["onboarding.filePrivacy"]?.isHidden == false
        configureAction("onboarding.resume", visible: snapshot.state.owner.collectionPaused,
                        enabled: snapshot.capabilities.canChangeCollection && !busy.contains(.collection))
        configureAction("onboarding.unhide", visible: snapshot.state.owner.isHidden,
                        enabled: snapshot.capabilities.canChangeVisibility && !busy.contains(.visibility))
        configureAction("onboarding.recheck", visible: snapshot.capabilities.initialized && !snapshot.setup.isChecking && snapshot.firstIncompleteOnboardingStep == 0 && sourceAccess.isHidden && !snapshot.state.owner.collectionPaused && !snapshot.state.owner.isHidden,
                        enabled: snapshot.capabilities.canRecheck)
        automationDetail.stringValue = copy.automationStatus(presentation)
        automation.title = presentation.permissionActionTitle
        automation.setAccessibilityLabel(automation.title)
        automation.isHidden = !presentation.canRequestPermission && snapshot.setup.permission != .notRunning
        automation.isEnabled = !automation.isHidden && snapshot.capabilities.canRequestAutomation && presentation.canRequestPermission
        if snapshot.setup.permission == .notRunning {
            automation.title = copy.text("打开 \(snapshot.setup.browser.displayName)", "Open \(snapshot.setup.browser.displayName)")
            automation.setAccessibilityLabel(automation.title)
            automation.isEnabled = snapshot.capabilities.canRecheck
        }
        let scriptDisabled = snapshot.chromeConnection == .javaScriptDisabled || snapshot.setup.issue == .chromeJavaScriptDisabled
        scriptDetail.stringValue = scriptDisabled
            ? ChromeAttachmentSetup.instructions(in: copy, browser: snapshot.setup.browser)
            : copy.chromeInstructions(presentation)
        chromeMenuSection.isHidden = snapshot.setup.permission != .granted || presentation.automationStatusText == nil
        scriptDetail.isHidden = scriptDetail.stringValue.isEmpty || snapshot.chromeConnection == .ready
            || (snapshot.setup.browser == .edge && !scriptDisabled)
        connectionStatus.stringValue = snapshot.onboardingReady
            ? copy.finishReady(browser: snapshot.setup.browser) : chromeStatus(snapshot.chromeConnection)
        let chromeCheck = controls["onboarding.checkChrome"] as? NSButton
        chromeCheck?.title = snapshot.chromeConnection == .unchecked ? copy.checkConnection : copy.recheckConnection
        if let chromeCheck { chromeCheck.setAccessibilityLabel(chromeCheck.title) }
        chromeCheck?.isHidden = snapshot.chromeConnection == .ready
        chromeCheck?.isEnabled = snapshot.setup.permission == .granted && snapshot.chromeConnection != .checking
        refreshNext()
        window.initialFirstResponder = firstAction
    }

    private var firstAction: NSButton {
        let ids: [String]
        switch currentStep {
        case 0: ids = ["onboarding.resume", "onboarding.unhide", "onboarding.sourceAccess", "onboarding.filePrivacy", "onboarding.recheck"]
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
        guard snapshot.capabilities.initialized else { return copy.checkingFolder }
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
        if currentStep == 0 {
            next.title = copy.continueButton
            next.isEnabled = snapshot != nil && (preview || incomplete != 0)
        } else {
            next.title = preview ? copy.endPreview : incomplete == 0 ? copy.setUpFolder : copy.getStarted
            next.isEnabled = !finishing && snapshot != nil && (preview || incomplete != 1)
        }
        later.title = currentStep == 1 && incomplete == 1
            ? copy.text("先使用本地截图", "Use Local Screenshots") : copy.later
        later.setAccessibilityLabel(later.title)
        next.setAccessibilityLabel(next.title)
    }

    @objc private func previousStep() { guard currentStep > 0 else { return }; currentStep -= 1; refreshStep() }
    @objc private func nextStep() {
        guard next.isEnabled, let snapshot else { return }
        if currentStep == 0 {
            currentStep = 1; refreshStep(); return
        }
        if snapshot.reviewEnvironment { closeForTeardown(); return }
        if let step = snapshot.firstIncompleteOnboardingStep {
            currentStep = step; refreshStep(); return
        }
        guard snapshot.onboardingReady, !finishing else { return }
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
        window.performClose(nil)
    }

    @objc private func actionPressed(_ sender: NSButton) {
        guard sender.isEnabled, !sender.isHiddenOrHasHiddenAncestor, let snapshot else { return }
        switch sender.identifier?.rawValue {
        case "onboarding.sourceAccess":
            guard snapshot.capabilities.canChooseSource else { return }; send(.chooseSourceAccess)
        case "onboarding.filePrivacy": send(.openFilePrivacy)
        case "onboarding.resume": send(.settings(.setCollectionPaused(false)), domain: .collection)
        case "onboarding.unhide": send(.settings(.setHidden(false)), domain: .visibility)
        case "onboarding.automation":
            if snapshot.setup.permission == .notRunning {
                send(.openChrome)
            } else if snapshot.capabilities.canRequestAutomation {
                send(.requestAutomation)
            }
        case "onboarding.checkChrome":
            guard snapshot.setup.permission == .granted, snapshot.chromeConnection != .checking else { return }
            send(.checkChromeConnection)
        case "onboarding.recheck":
            guard snapshot.capabilities.canRecheck else { return }; send(.recheckSource)
        default: break
        }
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
