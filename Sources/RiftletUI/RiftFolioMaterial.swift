#if canImport(AppKit)
import AppKit

/// A single material root shared by all visible pages. The containing panel
/// ignores mouse events; hover and activation belong to the UUID-bound pages.
final class RiftFolioBaseView: NSVisualEffectView {
    var edge: RiftSide = .left { didSet { needsLayout = true } }
    private let seam = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.addSublayer(seam)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let pixel = 1 / max(1, window?.backingScaleFactor ?? 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.borderWidth = contrast ? 1 : pixel
        layer?.borderColor = NSColor(white: contrast && !dark ? 0.27 : 1, alpha: contrast ? 0.9 : dark ? 0.29 : 0.84).cgColor
        let x = edge == .left ? bounds.maxX - 5 : bounds.minX + 5
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: bounds.minY + 6))
        path.addLine(to: CGPoint(x: x, y: bounds.maxY - 6))
        seam.lineWidth = pixel
        seam.strokeColor = NSColor(white: dark ? 1 : 0.22, alpha: contrast ? 0.85 : 0.18).cgColor
        seam.path = path
        CATransaction.commit()
    }
}

/// Paint beneath the existing thumbnail and ordinal layers, never above them.
@MainActor enum RiftFolioPage {
    static func draw(in rect: CGRect, appearance: NSAppearance, hovered: Bool, pressed: Bool) {
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let workspace = NSWorkspace.shared
        let highContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        let opaque = workspace.accessibilityDisplayShouldReduceTransparency
        let width: CGFloat = highContrast ? 1.25 : 0.75
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2),
                                   xRadius: 8, yRadius: 8)
        let shade: CGFloat = dark ? (pressed ? 0.26 : hovered ? 0.23 : 0.19) : (pressed ? 0.91 : 0.99)
        NSColor(white: shade, alpha: opaque || highContrast ? 1 : 0.93).setFill()
        outline.fill()
        if pressed || hovered {
            NSColor(srgbRed: 0.098, green: 0.718, blue: 0.643, alpha: highContrast ? 1 : 0.76).setStroke()
        } else {
            NSColor(white: dark ? 0.92 : 0.26, alpha: highContrast ? 0.9 : 0.18).setStroke()
        }
        outline.lineWidth = width
        outline.stroke()
    }
}
#endif
