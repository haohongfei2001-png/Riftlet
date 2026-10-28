import AppKit

/// Quiet Edge implementation candidate. These tokens do not grant product,
/// upload or source-geometry admission; founder visual adjudication is pending.
@MainActor
public enum RiftVisualStyle {
    public static let titleFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
    public static let headingFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    public static let bodyFont = NSFont.systemFont(ofSize: 13)
    public static let secondaryFont = NSFont.systemFont(ofSize: 11)
    public static let spacing: [CGFloat] = [4, 8, 12, 16, 24, 32]
    public static let window = adaptive("window", 0xF7F9F8, 0x171E1C)
    public static let surface = adaptive("surface", 0xFFFFFF, 0x222B27)
    public static let ink = adaptive("ink", 0x172521, 0xEEF4F0)
    public static let secondary = adaptive("secondary", 0x65716B, 0xA9B6AE)
    public static let accent = adaptive("accent", 0x087F73, 0x58CDB8)
    public static var edge: NSColor {
        NSColor(name: NSColor.Name("Riftlet.QuietEdge.edge")) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast { return dark ? NSColor(srgbRed: 238/255, green: 244/255, blue: 240/255, alpha: 1) : NSColor(srgbRed: 23/255, green: 37/255, blue: 33/255, alpha: 1) }
            return NSColor(srgbRed: dark ? 224 / 255 : 24 / 255,
                green: dark ? 237 / 255 : 40 / 255, blue: dark ? 226 / 255 : 33 / 255,
                alpha: dark ? 0.28 : 0.62)
        }
    }
    public static var separator: NSColor { themedAlpha("separator", base: ink, light: 0.12, dark: 0.16) }
    public static var selection: NSColor { themedAlpha("selection", base: accent, light: 0.10, dark: 0.16) }
    private static func themedAlpha(_ name: String, base: NSColor, light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: NSColor.Name("Riftlet.QuietEdge." + name)) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return base.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.65 : (isDark ? dark : light))
        }
    }

    private static func adaptive(_ name: String, _ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("Riftlet.QuietEdge." + name)) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
    public static func window(outerSize: NSSize, minimum: NSSize, title: String) -> NSWindow {
        let mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let rect = NSWindow.contentRect(forFrameRect: NSRect(origin: .zero, size: outerSize), styleMask: mask)
        let value = NSWindow(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
        value.title = title; value.minSize = minimum; value.isReleasedWhenClosed = false
        value.backgroundColor = window
        return value
    }
    /// Apply the intended outer size after Auto Layout has established the
    /// native minimum. Keep the entire frame on its current screen when it fits,
    /// so WindowServer does not narrow a straddling first presentation.
    public static func restoreWindowSize(_ window: NSWindow, size: NSSize) {
        window.contentView?.layoutSubtreeIfNeeded()
        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if size.width <= visible.width { frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - size.width)) }
            if size.height <= visible.height { frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - size.height)) }
        }
        window.setFrame(frame, display: true)
    }

    /// Both coordinates are top-down. A short document stays at the top rather
    /// than being bottom-aligned by an unflipped NSClipView.
    public static func documentStack(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = RiftDocumentStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        return stack
    }
    public static func topAlignedScrollView() -> NSScrollView {
        let scroll = NSScrollView()
        let clip = RiftTopAlignedClipView(); clip.drawsBackground = false
        scroll.contentView = clip; scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        return scroll
    }
    public static func label(_ text: String, role: String = "body") -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = role == "title" ? titleFont : role == "heading" ? headingFont : role == "secondary" ? secondaryFont : bodyFont
        value.textColor = role == "secondary" ? secondary : ink
        value.maximumNumberOfLines = 0; value.lineBreakMode = .byWordWrapping
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyTextStyle(value)
        return value
    }
    public static func applyTextStyle(_ field: NSTextField) {
        let font = field.font ?? bodyFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = font.pointSize >= 20 ? 26 : font.pointSize <= 11 ? 15 : 18
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        paragraph.lineBreakMode = field.lineBreakMode
        field.attributedStringValue = NSAttributedString(string: field.stringValue, attributes: [
            .font: font, .foregroundColor: field.textColor ?? ink, .paragraphStyle: paragraph
        ])
    }
    public static func style(_ button: NSButton, prominent: Bool = false) {
        button.bezelStyle = .rounded; button.font = bodyFont
        if prominent { button.bezelColor = accent }
    }
    public static func vertical(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        return stack
    }
    public static func card(_ views: [NSView]) -> NSView {
        let card = RiftSurfaceView(); let stack = vertical(views)
        stack.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(stack)
        for view in views where view is NSTextField {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }
}

/// Draw with dynamic colors, so appearance/accessibility changes do not retain
/// stale CGColors. This is an opaque auxiliary surface, never an input overlay.
@MainActor
public final class RiftSurfaceView: NSView {
    public var cornerRadius: CGFloat = 8
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        RiftVisualStyle.surface.setFill(); path.fill()
        RiftVisualStyle.separator.setStroke(); path.lineWidth = 1 / max(1, window?.backingScaleFactor ?? 1); path.stroke()
    }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}


@MainActor
private final class RiftDocumentStackView: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class RiftTopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        if let documentView, documentView.frame.height <= bounds.height { constrained.origin.y = 0 }
        return constrained
    }
}

/// Native button event handling, keyboard focus and AX semantics with a single
/// selected-row background. macOS inline bezels otherwise draw every row as a pill.
@MainActor
public final class RiftSidebarButton: NSButton {
    public override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    public override var focusRingMaskBounds: NSRect { bounds }

    public convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        isBordered = false; bezelStyle = .regularSquare; setButtonType(.pushOnPushOff)
        font = RiftVisualStyle.bodyFont; alignment = .left; focusRingType = .exterior
        setAccessibilityLabel(title)
    }
    public override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        if selected || cell?.isHighlighted == true {
            (selected ? RiftVisualStyle.selection : RiftVisualStyle.selection.withAlphaComponent(0.08)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).fill()
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let color = selected ? RiftVisualStyle.accent : RiftVisualStyle.ink
        let text = NSAttributedString(string: title, attributes: [.font: selected ? RiftVisualStyle.headingFont : RiftVisualStyle.bodyFont,
            .foregroundColor: isEnabled ? color : color.withAlphaComponent(0.45), .paragraphStyle: paragraph])
        text.draw(in: CGRect(x: 12, y: bounds.midY - text.size().height / 2, width: max(0, bounds.width - 24), height: text.size().height))
    }
    public override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
