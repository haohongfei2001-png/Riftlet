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
        let label = NSAttributedString(string: "位置示意 · 不读取截图", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: SettingsNativeStyle.color(.secondary)])
        label.draw(at: NSPoint(x: (bounds.width - label.size().width) / 2, y: bounds.height - 23))
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// The introductory diagram teaches the normal product flow, not the current
/// permission state. The adjacent native capability label carries that state.
@MainActor
final class RiftOnboardingWorkflowPreview: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        heightAnchor.constraint(equalToConstant: 156).isActive = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let gap: CGFloat = 26
        let width = max(0, (bounds.width - gap * 2) / 3)
        let names = ["1  照常截图", "2  点击边缘微图", "3  进入聊天附件"]
        for index in 0..<3 {
            let box = NSRect(x: CGFloat(index) * (width + gap), y: 4, width: width, height: 112)
            fill(box, role: .sidebar, radius: 8)
            let paper: NSRect
            switch index {
            case 0:
                paper = NSRect(x: box.midX - 35, y: box.midY - 28, width: 70, height: 56)
                fill(paper, role: .surface, radius: 5)
                lines(in: paper.insetBy(dx: 10, dy: 12))
            case 1:
                let edge = NSBezierPath()
                edge.move(to: NSPoint(x: box.maxX - 18, y: box.minY + 18))
                edge.line(to: NSPoint(x: box.maxX - 18, y: box.maxY - 18))
                SettingsNativeStyle.color(.secondary).setStroke(); edge.lineWidth = 1; edge.stroke()
                paper = NSRect(x: box.maxX - 72, y: box.midY - 18, width: 54, height: 36)
                fill(paper, role: .surface, radius: 4)
                lines(in: paper.insetBy(dx: 8, dy: 8))
                let point = NSBezierPath(ovalIn: NSRect(x: paper.minX - 5, y: paper.maxY - 4, width: 8, height: 8))
                SettingsNativeStyle.color(.accent).setFill(); point.fill()
            default:
                text("ChatGPT", at: NSPoint(x: box.minX + 12, y: box.minY + 13), size: 11)
                paper = NSRect(x: box.minX + 12, y: box.minY + 39, width: max(0, width - 24), height: 49)
                fill(paper, role: .surface, radius: 6)
                let attachment = NSRect(x: paper.minX + 7, y: paper.minY + 7, width: 31, height: 25)
                fill(attachment, role: .selection, radius: 3)
                lines(in: attachment.insetBy(dx: 5, dy: 6))
            }
            let caption = NSAttributedString(string: names[index], attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: SettingsNativeStyle.color(.ink)])
            caption.draw(at: NSPoint(x: box.midX - caption.size().width / 2, y: 126))
            if index < 2 {
                let x = box.maxX + 7, y = box.midY
                let arrow = NSBezierPath()
                arrow.move(to: NSPoint(x: x, y: y)); arrow.line(to: NSPoint(x: x + 12, y: y))
                arrow.move(to: NSPoint(x: x + 8, y: y - 4)); arrow.line(to: NSPoint(x: x + 12, y: y))
                arrow.line(to: NSPoint(x: x + 8, y: y + 4))
                SettingsNativeStyle.color(.secondary).setStroke(); arrow.lineWidth = 1.5; arrow.stroke()
            }
        }
    }

    private func fill(_ rect: NSRect, role: SettingsColorRole, radius: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        SettingsNativeStyle.color(role).setFill(); path.fill()
        SettingsNativeStyle.color(.border).setStroke(); path.lineWidth = 0.5; path.stroke()
    }
    private func lines(in rect: NSRect) {
        SettingsNativeStyle.color(.accent).withAlphaComponent(0.35).setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width * 0.7, height: 3).fill()
        SettingsNativeStyle.color(.border).setFill()
        NSRect(x: rect.minX, y: rect.minY + 8, width: rect.width, height: 2).fill()
        NSRect(x: rect.minX, y: rect.minY + 14, width: rect.width * 0.8, height: 2).fill()
    }
    private func text(_ value: String, at point: NSPoint, size: CGFloat) {
        NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: SettingsNativeStyle.color(.secondary)]).draw(at: point)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
