import AppKit

/// Static, synthetic three-card placement illustration. No image file, queue,
/// source directory, or upload capability is available to this view.
@MainActor
final class RiftOnboardingPlacementPreview: NSView {
    var configuration = RiftConfiguration() { didSet { needsDisplay = true } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        heightAnchor.constraint(equalToConstant: 151).isActive = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let desk = bounds.insetBy(dx: 1, dy: 1)
        let background = NSBezierPath(roundedRect: desk, xRadius: 9, yRadius: 9)
        SettingsNativeStyle.color(.sidebar).setFill(); background.fill()
        SettingsNativeStyle.color(.border).setStroke(); background.lineWidth = 1; background.stroke()
        let placement = configuration.placement
        let left = placement?.side == .left
        let firstY: CGFloat
        switch placement?.vertical {
        case .top: firstY = 21
        case .bottom: firstY = bounds.height - 91
        case .middle, nil: firstY = 40
        }
        let x = left ? 12.0 : bounds.width - 68
        for index in 0..<3 {
            let card = NSRect(x: x, y: firstY + CGFloat(index * 26), width: 56, height: 22)
            let shape = NSBezierPath(roundedRect: card, xRadius: 3, yRadius: 3)
            SettingsNativeStyle.color(.surface).setFill(); shape.fill()
            SettingsNativeStyle.color(.border).setStroke(); shape.stroke()
            SettingsNativeStyle.color(.accent).withAlphaComponent(0.3).setFill()
            NSRect(x: card.minX + 7, y: card.minY + 6, width: 28, height: 3).fill()
            SettingsNativeStyle.color(.border).setFill()
            NSRect(x: card.minX + 7, y: card.minY + 13, width: 39, height: 2).fill()
            let number = NSAttributedString(string: "\(index + 1)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: SettingsNativeStyle.color(.secondary)])
            number.draw(at: NSPoint(x: left ? card.maxX + 5 : card.minX - 11, y: card.midY - 6))
        }
        let label = NSAttributedString(string: "合成三图预览 · 不读取真实截图", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: SettingsNativeStyle.color(.secondary)])
        label.draw(at: NSPoint(x: (bounds.width - label.size().width) / 2, y: bounds.height - 23))
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
