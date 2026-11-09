import AppKit
import QuartzCore
import RiftletCapture

private final class TrayButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Nonactivating tray surface. Screenshot hit islands and AX actions remain
/// owned by RiftPanelController, above this view in window ordering.
final class RiftTraySurfaceView: NSView {
    var onToggle: (() -> Void)?
    var onCapture: ((ScreenshotMode) -> Void)?
    var onMore: ((NSView) -> Void)?
    var onScroll: ((NSEvent) -> Void)?

    private let glass = NSVisualEffectView()
    private let tint = CAGradientLayer()
    private let camera = TrayButton()
    private let more = TrayButton()
    private var modes: [ScreenshotMode: TrayButton] = [:]
    private var showingMenu = false
    private var previousSlot = CGRect.zero
    private var violet = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.setAccessibilityElement(false)
        glass.layer?.cornerRadius = 12
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.addSublayer(tint)
        tint.startPoint = CGPoint(x: 0, y: 1)
        tint.endPoint = CGPoint(x: 1, y: 0)
        addSubview(glass)
        configure(camera, symbol: "camera", title: "展开截图方式", action: #selector(toggle))
        configure(more, symbol: "ellipsis", title: "更多截图选项", action: #selector(openMore))
        for mode in ScreenshotMode.allCases {
            let button = TrayButton()
            let info: (String, String)
            switch mode {
            case .window: info = ("macwindow", "窗口截图")
            case .region: info = ("viewfinder", "区域截图")
            case .fullScreen: info = ("display", "全屏截图")
            }
            configure(button, symbol: info.0, title: info.1, action: #selector(capture(_:)))
            modes[mode] = button
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("截图托盘")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure(_ button: TrayButton, symbol: String, title: String, action: Selector) {
        button.title = ""
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.setButtonType(.momentaryChange)
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.target = self
        button.action = action
        button.isHidden = true
        addSubview(button)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tint.frame = glass.bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    private func applyPalette() {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = violet ? NSColor.systemPurple : NSColor.controlAccentColor
            let base = violet ? NSColor.systemIndigo : NSColor.windowBackgroundColor
            tint.colors = [base.withAlphaComponent(violet ? 0.28 : 0.14).cgColor,
                           accent.withAlphaComponent(violet ? 0.17 : 0.04).cgColor]
            glass.layer?.borderColor = NSColor.labelColor.withAlphaComponent(contrast ? 0.72 : 0.18).cgColor
            glass.layer?.borderWidth = contrast ? 1.5 : 0.75
            for button in [camera, more] + Array(modes.values) {
                button.contentTintColor = contrast ? .labelColor : (violet ? .systemPurple : .labelColor)
                button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(contrast ? 0.95 : 0.65).cgColor
            }
        }
    }

    func update(layout: RiftLayoutResult, violet: Bool, defaultMode: ScreenshotMode, reduceMotion: Bool, side: RiftSide) {
        self.violet = violet
        applyPalette()
        func local(_ r: CGRect) -> CGRect {
            r.offsetBy(dx: -layout.surfaceFrame.minX, dy: -layout.surfaceFrame.minY)
        }
        let wasOpen = showingMenu
        showingMenu = !layout.captureMenuFrame.isEmpty
        let buttonVisible = !layout.captureSlot.isEmpty
        let menu = local(layout.captureMenuFrame)
        let slot = local(layout.captureSlot)
        // Keep stable NSButtons, and never leave an old invisible target active.
        let insideToEdge = [more] + (ScreenshotMode.allCases.filter { $0 != defaultMode } + [defaultMode]).compactMap { modes[$0] }
        let order = side == .left ? Array(insideToEdge.reversed()) : insideToEdge
        for (index, button) in order.enumerated() {
            let wasHidden = button.isHidden
            button.isHidden = !showingMenu
            guard showingMenu else { continue }
            let gap = min(3, menu.width / 80)
            let width = (menu.width - 3 * gap) / 4
            let target = CGRect(x: menu.minX + CGFloat(index) * (width + gap), y: menu.minY,
                                width: width, height: menu.height)
            button.frame = target
            if wasHidden && !wasOpen && !reduceMotion && !previousSlot.isEmpty {
                animateEntrance(button, from: previousSlot)
            }
            button.nextKeyView = order[(index + 1) % order.count]
        }
        camera.isHidden = !buttonVisible
        if buttonVisible {
            camera.frame = slot
            if wasOpen && !reduceMotion, let defaultButton = modes[defaultMode] {
                animateEntrance(camera, from: defaultButton.frame)
            }
            previousSlot = slot
        } else if !showingMenu {
            previousSlot = .zero
        }
    }

    // Move only the presentation layer. Until it settles, a control must not
    // perform an action at its destination while visibly somewhere else.
    private func animateEntrance(_ button: NSButton, from source: CGRect) {
        guard let layer = button.layer else { return }
        let move = CABasicAnimation(keyPath: "transform.translation")
        move.fromValue = NSValue(size: NSSize(width: source.midX-button.frame.midX, height: source.midY-button.frame.midY))
        move.toValue = NSValue(size: .zero)
        move.duration = 0.14
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(move, forKey: "trayEntry")
    }
    private func settled(_ button: NSButton) -> Bool { button.layer?.animation(forKey: "trayEntry") == nil }
    @objc private func toggle() { if settled(camera) { onToggle?() } }
    @objc private func openMore() { if settled(more) { onMore?(more) } }
    @objc private func capture(_ button: NSButton) {
        guard settled(button), let mode = modes.first(where: { $0.value === button })?.key else { return }
        onCapture?(mode)
    }
    override func cancelOperation(_ sender: Any?) { if showingMenu { onToggle?() } }
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }
}
