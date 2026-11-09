import AppKit
import QuartzCore

/// Ratios measured from the 246-pixel-wide tray in the PR #51 reference.
/// A source pixel becomes one ratio unit; it is not assumed to be a point.
struct RiftTrayGlassPalette {
    var material: NSColor
    var key: NSColor
    var ink: NSColor
    var keyFoot: NSColor
    var rim: NSColor
    var keyRim: NSColor
    var blurOpacity: CGFloat

    init(violet: Bool, appearance: NSAppearance, clearGlass: Bool) {
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ||
            appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
                .map { $0 == .accessibilityHighContrastAqua || $0 == .accessibilityHighContrastDarkAqua } == true
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let glassAlpha: CGFloat = opaque ? 1 : contrast ? 0.86 : (clearGlass ? 0.53 : 0.68)
        let keyAlpha: CGFloat = opaque || contrast ? 1 : (violet && !dark ? 0.94 : 0.78)
        if violet {
            // Milky glass acquires most of its blue from the live desktop.
            // The camera tile and its ink were sampled separately from the glass.
            material = dark ? NSColor(srgbRed: 0.18, green: 0.17, blue: 0.29, alpha: glassAlpha)
                            : NSColor(srgbRed: clearGlass ? 0.937 : 0.851, green: clearGlass ? 0.941 : 0.867,
                                      blue: clearGlass ? 0.992 : 1, alpha: glassAlpha)
            key = dark ? NSColor(srgbRed: 0.32, green: 0.30, blue: 0.46, alpha: keyAlpha)
                       : NSColor(srgbRed: 0.918, green: 0.909, blue: 1, alpha: keyAlpha)
            ink = dark ? NSColor(srgbRed: 0.83, green: 0.78, blue: 1, alpha: 1)
                       : NSColor(srgbRed: 0.600, green: 0.477, blue: 0.980, alpha: 1)
            keyFoot = dark ? NSColor(srgbRed: 0.28, green: 0.25, blue: 0.43, alpha: keyAlpha)
                           : NSColor(srgbRed: 0.820, green: 0.761, blue: 1, alpha: opaque ? 1 : 0.67)
        } else {
            material = NSColor.windowBackgroundColor.withAlphaComponent(glassAlpha)
            key = NSColor.controlBackgroundColor.withAlphaComponent(keyAlpha)
            ink = .labelColor
            keyFoot = NSColor.controlColor.withAlphaComponent(keyAlpha)
        }
        if contrast { ink = .labelColor }
        rim = contrast ? .labelColor : NSColor.white.withAlphaComponent(dark ? 0.32 : 0.21)
        keyRim = contrast ? .labelColor : NSColor.white.withAlphaComponent(dark ? 0.27 : 0.42)
        blurOpacity = opaque ? 0 : (clearGlass ? 1 : 0.22)
    }
}

@MainActor
final class RiftTrayGlass: NSView {
    private let backdrop: NSView
    let usesClearGlass: Bool
    private let wash = CAGradientLayer()
    private let overlay = NSView()
    private var maskSize = CGSize.zero

    override init(frame: NSRect) {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            backdrop = glass
            usesClearGlass = true
        } else {
            backdrop = Self.legacyBackdrop()
            usesClearGlass = false
        }
        #else
        backdrop = Self.legacyBackdrop()
        usesClearGlass = false
        #endif
        super.init(frame: frame)
        wantsLayer = true
        backdrop.setAccessibilityElement(false)
        addSubview(backdrop)

        overlay.wantsLayer = true
        overlay.setAccessibilityElement(false)
        wash.startPoint = CGPoint(x: 0, y: 1)
        wash.endPoint = CGPoint(x: 1, y: 0)
        wash.cornerCurve = .continuous
        overlay.layer?.addSublayer(wash)
        addSubview(overlay)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    private static func legacyBackdrop() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ palette: RiftTrayGlassPalette) {
        backdrop.alphaValue = palette.blurOpacity
        let tint = palette.material
        let highlight = tint.withAlphaComponent(min(1, tint.alphaComponent + 0.012))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.colors = [highlight.cgColor, tint.cgColor]
        wash.borderColor = palette.rim.cgColor
        CATransaction.commit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let radius = min(bounds.height / 2, bounds.width * 24 / 246)
        backdrop.frame = bounds
        overlay.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = overlay.bounds
        wash.cornerRadius = radius
        wash.borderWidth = max(1 / (window?.backingScaleFactor ?? 1), bounds.width / 328)
        CATransaction.commit()
        if maskSize != bounds.size, !bounds.isEmpty {
            maskSize = bounds.size
            // Mask the actual WindowServer blur as well as the in-window tint.
            if let legacy = backdrop as? NSVisualEffectView {
                legacy.maskImage = NSImage(size: bounds.size, flipped: false) { rect in
                    NSColor.white.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                    return true
                }
            }
            #if compiler(>=6.2)
            if #available(macOS 26, *), let glass = backdrop as? NSGlassEffectView { glass.cornerRadius = radius }
            #endif
            window?.invalidateShadow()
        }
    }
}

/// The system window shadow supplies the contact edge. This wider penumbra
/// lives on the existing click-through decoration panel, entirely outside the glass.
@MainActor
final class RiftTrayCastShadow: NSView {
    private let caster = CALayer()
    private let exterior = CAShapeLayer()
    private var appliedSize = CGSize.zero
    private var appliedViolet: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        exterior.fillRule = .evenOdd
        layer?.mask = exterior
        layer?.addSublayer(caster)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(for surface: CGRect, violet: Bool) -> CGRect {
        let unit = surface.width / 246
        let margin = ceil(42 * unit)
        let outer = surface.insetBy(dx: -margin, dy: -margin)
        guard surface.size != appliedSize || violet != appliedViolet else { return outer }
        appliedSize = surface.size
        appliedViolet = violet
        let local = CGRect(origin: CGPoint(x: margin, y: margin), size: surface.size)
        let radius = min(local.height / 2, 24 * unit)
        let shape = CGPath(roundedRect: local, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let outside = CGMutablePath()
        let bounds = CGRect(origin: .zero, size: outer.size)
        outside.addRect(bounds)
        outside.addPath(shape)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        exterior.frame = bounds
        exterior.path = outside
        caster.frame = bounds
        caster.shadowPath = shape
        caster.shadowColor = violet ? NSColor(srgbRed: 0.05, green: 0.06, blue: 0.15, alpha: 1).cgColor : NSColor.black.cgColor
        caster.shadowRadius = 11 * unit
        caster.shadowOffset = CGSize(width: 0, height: -10.5 * unit)
        caster.shadowOpacity = 0.20
        CATransaction.commit()
        return outer
    }
}
