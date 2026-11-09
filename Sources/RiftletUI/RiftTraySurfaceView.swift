import AppKit
import QuartzCore
import RiftletCapture

private enum TrayAction: Equatable {
    case expand, capture(ScreenshotMode), unassigned
}

private extension ScreenshotMode {
    var traySymbol: String {
        switch self {
        case .window: return "macwindow"
        case .region: return "viewfinder"
        case .fullScreen: return "display"
        }
    }

    var trayName: String {
        switch self {
        case .window: return "窗口截图"
        case .region: return "区域截图"
        case .fullScreen: return "全屏截图"
        }
    }
}

private final class TrayButton: NSButton {
    private static let motionKey = "rift.tray.morph"
    private(set) var assignment: TrayAction = .unassigned
    private(set) var screenFrame = CGRect.zero
    private var revision = 0
    private var pressedRevision: Int?
    private var glyph: NSImage?
    private var palette: RiftTrayGlassPalette?
    private var unit: CGFloat = 1
    private var symbol = ""
    private var isRetiring = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        setAccessibilityRole(.button)
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var canAct: Bool {
        !isHidden && !isRetiring && isEnabled && layer?.animation(forKey: Self.motionKey) == nil &&
            (pressedRevision == nil || pressedRevision == revision)
    }

    override func mouseDown(with event: NSEvent) {
        guard canAct else { return }
        pressedRevision = revision
        defer { pressedRevision = nil }
        super.mouseDown(with: event)
    }

    func assign(_ action: TrayAction, title: String, symbol: String) {
        if assignment != action || toolTip != title { revision += 1 }
        assignment = action
        isRetiring = false
        isEnabled = action != .unassigned
        setAccessibilityHidden(false)
        setAccessibilityLabel(title)
        toolTip = title
        if self.symbol != symbol {
            self.symbol = symbol
            glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            needsDisplay = true
        }
    }

    func apply(_ palette: RiftTrayGlassPalette, unit: CGFloat) {
        self.palette = palette
        self.unit = unit
        needsDisplay = true
    }

    private var radius: CGFloat { min(unit * 12, min(bounds.width, bounds.height) / 2) }

    override func draw(_ dirtyRect: NSRect) {
        guard let palette else { return }
        let stroke = max(1 / (window?.backingScaleFactor ?? 1), unit * 0.68)
        let outline = bounds.insetBy(dx: stroke / 2, dy: stroke / 2)
        let foot = min(4.5 * unit, bounds.height * 0.08)
        let upper = CGRect(x: outline.minX, y: outline.minY + (isFlipped ? 0 : foot),
                           width: outline.width, height: max(0, outline.height - foot))
        let face = NSBezierPath(roundedRect: upper, xRadius: radius, yRadius: radius)
        let base = NSBezierPath(roundedRect: outline, xRadius: radius, yRadius: radius)
        base.windingRule = .evenOdd
        base.append(face)
        palette.keyFoot.setFill()
        base.fill()
        palette.key.setFill()
        face.fill()
        if cell?.isHighlighted == true {
            palette.ink.withAlphaComponent(0.08).setFill()
            face.fill()
        }
        palette.keyRim.setStroke()
        face.lineWidth = stroke
        face.stroke()

        if assignment == .expand {
            drawCamera(ink: palette.ink, centerY: upper.midY)
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            .applying(.init(paletteColors: [palette.ink]))
        guard let image = glyph?.withSymbolConfiguration(configuration), image.size.width > 0, image.size.height > 0 else { return }
        let glyphWidth = min(bounds.width * 0.52, 23 * unit)
        let factor = min(glyphWidth / image.size.width, bounds.height * 0.6 / image.size.height)
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: upper.midY - size.height / 2,
                          width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.45,
                   respectFlipped: true, hints: nil)
    }

    /// The selected reference has a raised viewfinder above a centered lens.
    /// Trace the 28 × 24 silhouette in top-down coordinates even on a flipped NSButton.
    private func drawCamera(ink: NSColor, centerY: CGFloat) {
        let scale = min(unit, bounds.width / 36, bounds.height / 32)
        guard scale > 0 else { return }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: bounds.midX + (x - 14) * scale,
                    y: centerY + (isFlipped ? 1 : -1) * (y - 12) * scale)
        }
        let path = NSBezierPath()
        path.move(to: point(3, 5.5))
        path.line(to: point(8.3, 5.5))
        path.line(to: point(10.8, 1.4))
        path.line(to: point(17.2, 1.4))
        path.line(to: point(19.8, 5.5))
        path.line(to: point(25.2, 5.5))
        path.curve(to: point(26.8, 7.2), controlPoint1: point(26.4, 5.5), controlPoint2: point(26.8, 5.9))
        path.line(to: point(26.8, 20.9))
        path.curve(to: point(25.2, 22.5), controlPoint1: point(26.8, 22.1), controlPoint2: point(26.4, 22.5))
        path.line(to: point(2.8, 22.5))
        path.curve(to: point(1.2, 20.9), controlPoint1: point(1.6, 22.5), controlPoint2: point(1.2, 22.1))
        path.line(to: point(1.2, 7.2))
        path.curve(to: point(3, 5.5), controlPoint1: point(1.2, 5.9), controlPoint2: point(1.6, 5.5))
        path.close()
        let lens = point(14, 13.8)
        path.appendOval(in: CGRect(x: lens.x - 4.5 * scale, y: lens.y - 4.5 * scale,
                                   width: 9 * scale, height: 9 * scale))
        path.lineWidth = 2.55 * scale
        path.lineJoinStyle = .round
        ink.setStroke()
        path.stroke()
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    override func layout() {
        super.layout()
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowColor = NSColor(srgbRed: 0.18, green: 0.16, blue: 0.29, alpha: 1).cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: -1.8 * unit)
        layer.shadowRadius = 2.4 * unit
        layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.commit()
    }

    /// The parent panel already has its new frame when update() runs. Retain
    /// the previous screen-space target and add its live presentation offset.
    var visibleScreenFrame: CGRect? {
        guard !isHidden, !screenFrame.isEmpty else { return nil }
        guard let layer, layer.animation(forKey: Self.motionKey) != nil, let visible = layer.presentation() else { return screenFrame }
        return CGRect(x: screenFrame.minX + visible.frame.minX - layer.frame.minX,
                      y: screenFrame.minY + visible.frame.minY - layer.frame.minY,
                      width: visible.frame.width, height: visible.frame.height)
    }

    func move(to target: CGRect, in surface: CGRect, from source: CGRect?, reduceMotion: Bool,
              retiring: Bool = false) {
        let wasHidden = isHidden
        let changed = screenFrame != target
        if changed || wasHidden || retiring { revision += 1 }
        screenFrame = target
        frame = target.offsetBy(dx: -surface.minX, dy: -surface.minY)
        isHidden = false
        if retiring {
            isRetiring = true
            isEnabled = false
            toolTip = nil
            setAccessibilityHidden(true)
        }
        guard let layer, !reduceMotion, let source, !source.isEmpty, !target.isEmpty,
              abs(source.midX - target.midX) <= surface.width,
              abs(source.midY - target.midY) <= max(surface.width, surface.height) else {
            if reduceMotion || changed || wasHidden { layer?.removeAnimation(forKey: Self.motionKey) }
            if retiring { hide() }
            return
        }
        let transform = CABasicAnimation(keyPath: "transform")
        var start = CATransform3DMakeScale(source.width / target.width, source.height / target.height, 1)
        let anchor = layer.anchorPoint
        start.m41 = source.minX - target.minX + (source.width - target.width) * anchor.x
        start.m42 = source.minY - target.minY + (source.height - target.height) * anchor.y
        transform.fromValue = NSValue(caTransform3D: start)
        transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = wasHidden ? 0 : (layer.presentation()?.opacity ?? 1)
        opacity.toValue = retiring ? 0 : 1
        let motion = CAAnimationGroup()
        motion.animations = [transform, opacity]
        motion.duration = 0.18
        motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let owner = revision
        CATransaction.begin()
        if retiring {
            CATransaction.setCompletionBlock { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isRetiring, self.revision == owner else { return }
                    self.hide()
                }
            }
        }
        layer.add(motion, forKey: Self.motionKey)
        CATransaction.commit()
    }

    func hide() {
        revision += 1
        layer?.removeAnimation(forKey: Self.motionKey)
        isHidden = true
        isRetiring = false
        screenFrame = .zero
    }

    func finishRetirementIfNeeded(reduceMotion: Bool) {
        if isRetiring && (reduceMotion || layer?.animation(forKey: Self.motionKey) == nil) { hide() }
    }
}

/// The original screenshot records and event routes are owned by the panel.
/// This view owns the tray glass and its terminal capture item.
final class RiftTraySurfaceView: NSView {
    var onToggle: (() -> Void)?
    var onCapture: ((ScreenshotMode) -> Void)?
    var onScroll: ((NSEvent) -> Void)?

    private let glass = RiftTrayGlass(frame: .zero)
    private let captureKey = TrayButton(frame: .zero)
    private let favorites = (0..<3).map { _ in TrayButton(frame: .zero) }
    private var showingMenu = false
    private var violet = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(glass)
        for button in favorites + [captureKey] {
            button.target = self
            button.action = #selector(press(_:))
            addSubview(button)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("截图托盘")
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        glass.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    private func applyPalette() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let palette = RiftTrayGlassPalette(violet: violet, appearance: effectiveAppearance, clearGlass: glass.usesClearGlass)
            glass.apply(palette)
            for button in favorites + [captureKey] {
                button.apply(palette, unit: bounds.width / 246)
            }
        }
    }

    func update(layout: RiftLayoutResult, violet: Bool, defaultMode: ScreenshotMode, favoriteModes: [ScreenshotMode?],
                reduceMotion: Bool) {
        self.violet = violet
        applyPalette()
        let wasOpen = showingMenu
        showingMenu = !layout.captureMenuFrame.isEmpty
        let oldCapture = captureKey.visibleScreenFrame
        let surface = layout.surfaceFrame
        if showingMenu {
            let menu = layout.captureMenuFrame
            let gap = min(4 * surface.width / 246, menu.width / 32)
            let width = (menu.width - 3 * gap) / 4
            captureKey.assign(.capture(defaultMode), title: "默认截图，" + defaultMode.trayName, symbol: defaultMode.traySymbol)
            for (i, button) in favorites.enumerated() {
                let mode = favoriteModes.indices.contains(i) ? favoriteModes[i] : nil
                button.assign(mode.map(TrayAction.capture) ?? .unassigned,
                              title: "常用截图 \(i + 1)，" + (mode?.trayName ?? "未设置"), symbol: mode?.traySymbol ?? "minus")
            }
            let order = favorites + [captureKey]
            for (i, button) in order.enumerated() {
                let target = CGRect(x: menu.minX + CGFloat(i) * (width + gap), y: menu.minY, width: width, height: menu.height)
                let source: CGRect? = !wasOpen ? (button.visibleScreenFrame ?? oldCapture) :
                    (button.screenFrame != target ? button.visibleScreenFrame : nil)
                button.move(to: target, in: surface, from: source, reduceMotion: reduceMotion)
            }
            let enabled = order.filter(\.isEnabled)
            for (i, button) in enabled.enumerated() { button.nextKeyView = enabled[(i + 1) % enabled.count] }
            return
        }
        let slot = layout.captureSlot
        if slot.isEmpty {
            for button in favorites + [captureKey] { button.hide() }
            return
        }
        captureKey.assign(.expand, title: "展开截图方式", symbol: "camera")
        let source = wasOpen || captureKey.screenFrame != slot ? oldCapture : nil
        captureKey.move(to: slot, in: surface, from: source, reduceMotion: reduceMotion)
        for button in favorites {
            if wasOpen {
                button.move(to: slot, in: surface, from: button.visibleScreenFrame,
                            reduceMotion: reduceMotion, retiring: true)
            } else {
                button.finishRetirementIfNeeded(reduceMotion: reduceMotion)
            }
        }
    }

    @objc private func press(_ button: TrayButton) {
        guard button.canAct else { return }
        switch button.assignment {
        case .expand: onToggle?()
        case .capture(let mode): onCapture?(mode)
        case .unassigned: break
        }
    }

    override func cancelOperation(_ sender: Any?) { if showingMenu { onToggle?() } }
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }
}
