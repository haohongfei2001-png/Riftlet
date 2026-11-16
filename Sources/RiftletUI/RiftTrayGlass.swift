import AppKit
import QuartzCore

extension RiftTrayColors {
    /// Retint a sampled violet surface in linear sRGB at its original luminance.
    /// This keeps glass alpha, key contrast and thumbnail image content independent.
    func tint(_ sampled: NSColor) -> NSColor {
        guard case .custom(let hue, let strength) = self,
              let source = sampled.usingColorSpace(.sRGB) else { return sampled }
        let saturation = min(1, source.saturationComponent * 1.6) * strength
        guard let target = NSColor(hue: hue / 360, saturation: saturation, brightness: 1, alpha: 1)
            .usingColorSpace(.sRGB) else { return sampled }

        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        func luminance(_ rgb: NSColor) -> CGFloat {
            0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        let from = luminance(target)
        let to = luminance(source)
        func channel(_ srgb: CGFloat) -> CGFloat {
            let value = linear(srgb)
            let adjusted = to <= from ? value * to / from : value + (1 - value) * (to - from) / (1 - from)
            return adjusted <= 0.0031308 ? 12.92 * adjusted : 1.055 * pow(adjusted, 1 / 2.4) - 0.055
        }
        return NSColor(srgbRed: channel(target.redComponent), green: channel(target.greenComponent),
                       blue: channel(target.blueComponent), alpha: sampled.alphaComponent)
    }
}

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
    var highContrast: Bool
    var cameraBody: NSColor
    var cameraOutline: NSColor

    @MainActor init(colors: RiftTrayColors, appearance: NSAppearance, clearGlass: Bool,
         transparency: Double? = nil, cameraBodyColor: String? = nil) {
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ||
            appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
                .map { $0 == .accessibilityHighContrastAqua || $0 == .accessibilityHighContrastDarkAqua } == true
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let baseAlpha = 1 - (transparency ?? (clearGlass ? 0.47 : 0.32))
        let glassAlpha = opaque ? 1 : max(contrast ? 0.86 : 0, baseAlpha)
        highContrast = contrast
        let violet = colors != .system
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
            material = colors.tint(material)
            key = colors.tint(key)
            ink = colors.tint(ink)
            keyFoot = colors.tint(keyFoot)
        } else {
            material = NSColor.windowBackgroundColor.withAlphaComponent(glassAlpha)
            key = NSColor.controlBackgroundColor.withAlphaComponent(keyAlpha)
            ink = .labelColor
            keyFoot = (dark ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
                            : NSColor.controlColor).withAlphaComponent(keyAlpha)
        }
        if contrast { ink = .labelColor }
        cameraBody = cameraBodyColor.flatMap { text -> NSColor? in
            guard text.hasPrefix("#"), text.count == 7, let hex = UInt32(text.dropFirst(), radix: 16) else { return nil }
            return RiftThumbnailAppearance.color(hex)
        } ?? ink
        cameraOutline = dark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.22, alpha: 1)
        rim = contrast ? .labelColor : .separatorColor
        keyRim = contrast ? .labelColor : NSColor.white.withAlphaComponent(dark ? 0.27 : 0.42)
        blurOpacity = opaque ? 0 : (clearGlass ? 1 : 0.22)
    }
}

@MainActor
final class RiftTrayGlass: NSView {
    private let backdrop: NSView
    static var defaultTransparency: Double {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return 0.47 }
        #endif
        return 0.32
    }
    let usesClearGlass: Bool
    private var highContrast = false
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
        highContrast = palette.highContrast
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
        wash.borderWidth = highContrast ? 1 : 1 / (window?.backingScaleFactor ?? 1)
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
