import AppKit

/// First-use illustration drawn from the bundled, public design sample.
/// Reading it never opens a screen, capture folder, queue or browser.
@MainActor
final class RiftOnboardingPlacementPreview: NSView {
    private let workflow: Bool
    private static let example = Bundle.main.url(forResource: "glass-study", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }
    var configuration = RiftConfiguration() { didSet { needsDisplay = true } }
    var entryEnabled = true { didSet { needsDisplay = true } }

    init(workflow: Bool = false) {
        self.workflow = workflow
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: workflow ? 155 : 103).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(workflow ? "截图进入当前聊天草稿的示意" : "桌面边缘位置预览")
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        guard rect.width > 20, rect.height > 20 else { return }
        let outline = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        outline.addClip()
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c1 = dark ? NSColor(srgbRed: 0.10, green: 0.21, blue: 0.22, alpha: 1) : NSColor(srgbRed: 0.76, green: 0.89, blue: 0.86, alpha: 1)
        let c2 = dark ? NSColor(srgbRed: 0.22, green: 0.25, blue: 0.34, alpha: 1) : NSColor(srgbRed: 0.85, green: 0.86, blue: 0.94, alpha: 1)
        NSGradient(starting: c1, ending: c2)?.draw(in: rect, angle: 15)
        for i in 0..<4 {
            let x = rect.width * CGFloat(i - 1) * 0.24
            let curve = NSBezierPath()
            curve.move(to: CGPoint(x: x, y: 0))
            curve.curve(to: CGPoint(x: x + rect.width * 0.72, y: rect.height),
                        controlPoint1: CGPoint(x: x + rect.width * 0.13, y: rect.height * 0.24),
                        controlPoint2: CGPoint(x: x + rect.width * 0.66, y: rect.height * 0.30))
            NSColor.white.withAlphaComponent(0.30).setStroke()
            curve.lineWidth = 1.2
            curve.stroke()
        }
        let browserWidth = rect.width * 0.61
        let browser = CGRect(x: (rect.width - browserWidth) / 2, y: rect.height * 0.15, width: browserWidth, height: rect.height * 0.69)
        let chrome = NSBezierPath(roundedRect: browser, xRadius: 7, yRadius: 7)
        NSColor.windowBackgroundColor.setFill()
        chrome.fill()
        NSColor.separatorColor.setStroke()
        chrome.stroke()
        for i in 0..<3 {
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: browser.minX + 9 + CGFloat(i) * 7, y: browser.maxY - 11, width: 4, height: 4)).fill()
        }
        let composer = browser.insetBy(dx: 12, dy: 11)
        let entry = CGRect(x: composer.minX, y: composer.minY, width: composer.width, height: min(34, composer.height * 0.52))
        let bubble = NSBezierPath(roundedRect: entry, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        bubble.fill()
        NSColor.separatorColor.setStroke()
        bubble.stroke()
        let words: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor]
        ("ChatGPT" as NSString).draw(at: CGPoint(x: composer.minX + 19, y: browser.maxY - 14), withAttributes: words)
        if workflow, let image = Self.example {
            image.draw(in: CGRect(x: entry.minX + 5, y: entry.minY + 4, width: min(34, entry.height), height: entry.height - 8))
        } else {
            ("给 ChatGPT 发送消息" as NSString).draw(at: CGPoint(x: entry.minX + 8, y: entry.midY - 6), withAttributes: words)
        }
        guard let placement = workflow ? RiftPlacement.rightMiddle : configuration.placement else { return }
        let tray = workflow || configuration.desktopForm == .tray
        let width = tray ? rect.width / 8 : 34.0
        let height = tray ? width * 0.53 : 23.0
        let y: CGFloat
        switch placement.vertical {
        case .top: y = rect.maxY - height - 8
        case .middle: y = rect.midY - height / 2
        case .bottom: y = rect.minY + 8
        }
        let frame = CGRect(x: placement.side == .right ? rect.maxX - width - 3 : rect.minX + 3,
                           y: y, width: width, height: height)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4)
        NSColor.white.withAlphaComponent(0.82).setFill(); shape.fill()
        NSColor.separatorColor.setStroke(); shape.stroke()
        let slot = frame.insetBy(dx: 3, dy: 3)
        let photo = CGRect(x: slot.minX, y: slot.minY,
                           width: tray && entryEnabled ? slot.width * 0.49 : slot.width, height: slot.height)
        if let image = Self.example {
            let scale = min(photo.width / image.size.width, photo.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: photo.midX - size.width / 2, y: photo.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
        if tray && entryEnabled {
            let icon = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
            icon?.draw(in: CGRect(x: slot.midX + 3, y: slot.midY - 4, width: 11, height: 8))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
