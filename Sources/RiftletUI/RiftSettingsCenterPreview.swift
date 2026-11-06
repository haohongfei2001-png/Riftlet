import AppKit
import QuartzCore

/// Drawn fixtures only. No image URL, filesystem, capture, queue or upload owner.
@MainActor
final class RiftSettingsCenterPreview: NSView {
    enum Kind { case geometry, arrival, swallow }
    let kind: Kind
    private(set) var playCount = 0
    private(set) var lastDuration: Double = 0
    private(set) var configuration = RiftConfiguration()
    private var mode = ArrivalMotionMode.none
    private var reduceMotion = false
    private let clip = CALayer()
    private let tile = CALayer()
    private let titleBand = CALayer()
    private let lines = (0..<3).map { _ in CALayer() }
    private let edge = CALayer()
    private var drawnBounds = NSRect.zero
    var isAnimating: Bool { tile.animation(forKey: "settings.preview") != nil }
    var geometrySummary: String {
        let count = min(configuration.visibleCountPreference, 4)
        let title = configuration.placement?.title ?? "旧版位置"
        let countText = configuration.visibleCountPreference > count
            ? "\(configuration.visibleCountPreference) 张（示意前 \(count) 张）" : "\(count) 张"
        return title + " · " + countText
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7; layer?.masksToBounds = true
        layer?.addSublayer(clip); layer?.addSublayer(edge)
        clip.masksToBounds = true; clip.addSublayer(tile)
        tile.cornerRadius = 4; tile.masksToBounds = true
        tile.addSublayer(titleBand)
        lines.forEach { tile.addSublayer($0) }
        setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel(kind == .geometry ? "布局示意，不是真实截图" : kind == .arrival ? "入缝动效示意图" : "快速吞噬示意图")
        if kind == .geometry { clip.isHidden = true; edge.isHidden = true }
    }
    required init?(coder: NSCoder) { nil }
    func update(configuration: RiftConfiguration, mode: ArrivalMotionMode, reduceMotion: Bool) {
        let changed = self.configuration != configuration || self.mode != mode || self.reduceMotion != reduceMotion
        self.configuration = configuration; self.mode = mode; self.reduceMotion = reduceMotion
        if kind == .geometry { setAccessibilityValue(geometrySummary) }
        // An unrelated status refresh must neither restart nor stop a preview.
        if changed { stop(); positionLayers() }
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors(); needsDisplay = true }
    override func layout() {
        super.layout()
        if bounds != drawnBounds { stop(); positionLayers() }
    }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.backgroundColor = SettingsNativeStyle.color(.window).cgColor
            layer?.borderColor = SettingsNativeStyle.color(.border).cgColor
            layer?.borderWidth = 1
            tile.backgroundColor = SettingsNativeStyle.color(.surface).cgColor
            tile.borderColor = SettingsNativeStyle.color(.border).cgColor; tile.borderWidth = 1
            titleBand.backgroundColor = SettingsNativeStyle.color(.accent).withAlphaComponent(0.7).cgColor
            lines.forEach { $0.backgroundColor = SettingsNativeStyle.color(.secondary).withAlphaComponent(0.4).cgColor }
            edge.backgroundColor = SettingsNativeStyle.color(.secondary).withAlphaComponent(0.5).cgColor
            CATransaction.commit()
        }
    }
    private func positionLayers() {
        drawnBounds = bounds
        guard kind != .geometry else { colors(); return }
        let seam = bounds.maxX - 26
        let target = CGRect(x: seam - 56, y: bounds.midY - 25, width: 74, height: 50)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        clip.frame = CGRect(x: 0, y: 0, width: max(0, seam), height: bounds.height)
        tile.frame = target
        edge.frame = CGRect(x: seam - 0.5, y: bounds.midY - 35, width: 1, height: 70)
        titleBand.frame = CGRect(x: 0, y: 39, width: 74, height: 11)
        for (index, line) in lines.enumerated() { line.frame = CGRect(x: 9, y: 10 + index * 8, width: 45 - index * 6, height: 3) }
        CATransaction.commit()
        colors()
    }
    func play() {
        guard kind != .geometry, window?.isVisible == true, bounds.width > 100 else { return }
        stop(); positionLayers(); playCount += 1
        if kind == .arrival {
            guard mode.effective(reduceMotion: reduceMotion) == .magnet else { lastDuration = 0; return }
            let target = tile.frame
            guard let plan = MagnetMotionPlan(sourceRect: CGRect(x: 24, y: bounds.midY - 42, width: 135, height: 84),
                    targetImageFrame: target, clippingEdgeX: clip.frame.maxX, screenFrame: bounds) else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            plan.applyFinalState(to: tile, relativeTo: .zero)
            let animation = plan.makeLayerAnimation(relativeTo: .zero)
            lastDuration = plan.totalDuration
            tile.add(animation, forKey: "settings.preview")
            CATransaction.commit()
        } else {
            let duration = reduceMotion ? min(0.08, configuration.swallowDuration) : configuration.swallowDuration
            lastDuration = duration
            guard duration > 0 else { return }
            let movement = CABasicAnimation(keyPath: "position.x")
            movement.fromValue = tile.position.x
            movement.toValue = tile.position.x + 90
            movement.duration = duration
            movement.timingFunction = CAMediaTimingFunction(name: .easeIn)
            // Presentation-only motion returns to its model position on finish,
            // ready for another explicit preview; it never changes a queue item.
            tile.add(movement, forKey: "settings.preview")
        }
    }
    func stop() { tile.removeAllAnimations() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard kind == .geometry, bounds.width > 50 else { return }
        let screen = bounds.insetBy(dx: 30, dy: 14)
        SettingsNativeStyle.color(.surface).setFill()
        NSBezierPath(roundedRect: screen, xRadius: 6, yRadius: 6).fill()
        SettingsNativeStyle.color(.border).setStroke()
        NSBezierPath(roundedRect: screen, xRadius: 6, yRadius: 6).stroke()
        let side = configuration.placement?.side ?? .right
        let count = min(configuration.visibleCountPreference, 4)
        let tileWidth = min(57, max(22, configuration.fitWidth * 0.66))
        let tileHeight = min(27, max(10, configuration.fitHeight * 0.42))
        let pitch = min(30, max(tileHeight + 2, configuration.rowPitch * 0.4))
        let total = Double(max(0, count - 1)) * pitch + tileHeight
        let top: Double
        switch configuration.placement?.vertical {
        case .top: top = screen.maxY - 9
        case .bottom: top = screen.minY + 9 + total
        case .middle, nil: top = screen.midY + total / 2
        }
        let inset = min(configuration.outerInset * 0.25, screen.width * 0.2)
        let seam = side == .left ? screen.minX + inset : screen.maxX - inset
        let x = side == .left ? seam - tileWidth * configuration.hiddenFraction : seam - tileWidth * (1 - configuration.hiddenFraction)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: screen).addClip()
        for index in 0..<count {
            let rect = NSRect(x: x, y: top - tileHeight - Double(index) * pitch, width: tileWidth, height: tileHeight)
            SettingsNativeStyle.color(.selection).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            SettingsNativeStyle.color(.accent).withAlphaComponent(0.6).setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        // The native caption lives outside this drawing, so a left/middle
        // placement cannot put its text over the second synthetic thumbnail.
    }
}
