import AppKit

/// Static native counterpart of the approved first-use paper → edge sketch.
/// It is decorative, contains no real screenshot and confers no input ability.
@MainActor
final class RiftFirstUseIllustration: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        heightAnchor.constraint(equalToConstant: 112).isActive = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { return nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let origin = max(0, (bounds.width - 308) / 2)
        drawPaper(in: NSRect(x: origin, y: bounds.midY - 39.5, width: 128, height: 79), includeTitle: true)
        if let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .light)
                .applying(NSImage.SymbolConfiguration(paletteColors: [RiftVisualStyle.secondary]))) {
            arrow.draw(in: NSRect(x: origin + 165, y: bounds.midY - 13, width: 26, height: 26))
        }
        let scale = max(1, window?.backingScaleFactor ?? 1)
        let seamX = floor((origin + 308) * scale) / scale
        let full = NSRect(x: seamX - 42, y: bounds.midY - 79 * 56 / 128 / 2, width: 56, height: 79 * 56 / 128)
        NSGraphicsContext.saveGraphicsState()
        // Exactly three quarters are exposed, while the source keeps its ratio.
        NSBezierPath(rect: NSRect(x: full.minX, y: full.minY, width: 42, height: full.height)).addClip()
        drawPaper(in: full, includeTitle: false)
        NSGraphicsContext.restoreGraphicsState()
        RiftVisualStyle.edge.setFill()
        let lineWidth: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 1 / scale
        NSRect(x: seamX - lineWidth, y: bounds.midY - 41.5, width: lineWidth, height: 83).fill()
        let ordinal = NSAttributedString(string: "1", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: RiftVisualStyle.secondary])
        ordinal.draw(at: NSPoint(x: full.minX - 8 - ordinal.size().width, y: bounds.midY - ordinal.size().height / 2))
    }

    private func drawPaper(in rect: NSRect, includeTitle: Bool) {
        let scale = rect.width / 128
        let paper = NSBezierPath(roundedRect: rect, xRadius: 3 * scale, yRadius: 3 * scale)
        RiftVisualStyle.surface.setFill(); paper.fill()
        RiftVisualStyle.separator.setStroke(); paper.lineWidth = 1 / max(1, window?.backingScaleFactor ?? 1); paper.stroke()
        if includeTitle {
            NSAttributedString(string: "关于今天的一个想法", attributes: [
                .font: NSFont.systemFont(ofSize: 8), .foregroundColor: RiftVisualStyle.ink])
                .draw(at: NSPoint(x: rect.minX + 12, y: rect.maxY - 24))
        } else {
            RiftVisualStyle.accent.withAlphaComponent(0.25).setFill()
            NSRect(x: rect.minX + 12 * scale, y: rect.maxY - 22 * scale, width: 76 * scale, height: 4 * scale).fill()
        }
        RiftVisualStyle.separator.setFill()
        for index in 0..<3 {
            NSRect(x: rect.minX + 12 * scale, y: rect.maxY - CGFloat(38 + index * 9) * scale,
                   width: (index == 2 ? 68 : 96) * scale, height: 3 * scale).fill()
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsDisplay = true }
}
