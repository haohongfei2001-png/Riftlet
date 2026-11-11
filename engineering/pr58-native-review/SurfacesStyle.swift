import AppKit

@MainActor
enum SurfaceStyle {
    static var teal: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.24, green: 0.81, blue: 0.74, alpha: 1)
                : NSColor(srgbRed: 0.031, green: 0.486, blue: 0.439, alpha: 1)
        }
    }

    static func label(_ string: String, _ size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let v = NSTextField(wrappingLabelWithString: string)
        v.font = .systemFont(ofSize: size, weight: weight)
        v.textColor = color
        v.setContentCompressionResistancePriority(.required, for: .vertical)
        return v
    }

    static func stack(_ views: [NSView], horizontal: Bool = false, gap: CGFloat = 8) -> NSStackView {
        let v = NSStackView(views: views)
        v.orientation = horizontal ? .horizontal : .vertical
        v.alignment = horizontal ? .centerY : .leading
        v.spacing = gap
        v.detachesHiddenViews = true
        return v
    }

    static func symbol(_ name: String, size: CGFloat = 17, color: NSColor? = nil) -> NSImageView {
        let v = NSImageView()
        v.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
        v.contentTintColor = color ?? teal
        v.setAccessibilityElement(false)
        v.setContentCompressionResistancePriority(.required, for: .horizontal)
        return v
    }

    static func series(_ views: [NSView], gap: CGFloat = 0) -> NSStackView {
        let v = stack(views, gap: gap)
        for sub in views { sub.widthAnchor.constraint(equalTo: v.widthAnchor).isActive = true }
        return v
    }

    static func button(_ title: String, image: String? = nil, plain: Bool = false, action: @escaping () -> Void) -> NSButton {
        let b = SurfaceAction(title: title, target: nil, action: nil)
        b.target = b
        b.action = #selector(SurfaceAction.invoke)
        b.clicked = action
        b.bezelStyle = .rounded
        b.isBordered = !plain
        b.controlSize = .regular
        if let image {
            b.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
            b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        return b
    }

    static func line(vertical: Bool = false) -> NSBox {
        let v = NSBox()
        v.boxType = .separator
        if vertical { v.widthAnchor.constraint(equalToConstant: 1).isActive = true }
        else { v.heightAnchor.constraint(equalToConstant: 1).isActive = true }
        return v
    }

    static func material(_ material: NSVisualEffectView.Material) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    static func fill(_ child: NSView, in parent: NSView, inset: CGFloat = 0) {
        parent.addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
                                    child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
                                    child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
                                    child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
    }

    static func pad(_ view: NSView, _ gap: CGFloat, material: NSVisualEffectView.Material? = nil) -> NSView {
        let v: NSView = material.map { self.material($0) } ?? NSView()
        fill(view, in: v, inset: gap)
        return v
    }

    static func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        return v
    }

    static func row(_ icon: String, _ title: String, _ detail: String? = nil, trailing: NSView? = nil) -> NSStackView {
        let s = symbol(icon)
        s.widthAnchor.constraint(equalToConstant: 22).isActive = true
        var labels: [NSView] = [label(title, 13, weight: .medium)]
        if let detail { labels.append(label(detail, 12, color: .secondaryLabelColor)) }
        let left = stack(labels, gap: 3)
        var views: [NSView] = [s, left, spacer()]
        if let trailing { views.append(trailing) }
        return stack(views, horizontal: true, gap: 10)
    }
}

// The preview fits its split pane; the underlying bitmap must not set the
// minimum width of the history window.
@MainActor
final class SurfaceDetailImage: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

@MainActor
final class SurfacePopoverBody: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(rect: dirtyRect).fill()
    }
}

@MainActor
final class SurfaceAction: NSButton {
    var clicked: (() -> Void)?
    @objc func invoke() { clicked?() }
}

@MainActor
final class SurfaceMenuAction: NSMenuItem {
    var clicked: (() -> Void)?
    @objc func invoke() { clicked?() }
}

@MainActor
enum SurfaceImages {
    static func load(_ name: String) -> NSImage? {
        let parts = name.split(separator: ".")
        guard parts.count == 2,
              let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])) else { return nil }
        return NSImage(contentsOf: url)
    }

    static var items: [(String, String, String, String)] {
        [("glass-study.png", "玻璃材质研究", "10:42", "已归档"),
         ("reading.svg", "切线与局部近似", "10:36", "已附加"),
         ("error.svg", "错误响应", "09:58", "待核实")]
    }

    static func preview(_ index: Int, size: CGSize) -> NSImageView {
        let v = NSImageView()
        v.image = load(items[index].0)
        v.imageScaling = .scaleProportionallyUpOrDown
        v.setAccessibilityLabel(items[index].1)
        v.widthAnchor.constraint(equalToConstant: size.width).isActive = true
        v.heightAnchor.constraint(equalToConstant: size.height).isActive = true
        return v
    }
}

// A small interactive diagram of the desktop. The placement corresponds to one
// of the six real screen positions. All illustration content is bundled.
@MainActor
final class SurfaceDesktopDiagram: NSView {
    let stage: Int
    let placement: Int
    init(stage: Int, placement: Int) {
        self.stage = stage
        self.placement = placement
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(stage == 2 ? "桌面边缘位置预览" : "截图进入当前聊天草稿的示意")
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let outline = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        NSGraphicsContext.saveGraphicsState()
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
        let width = rect.width * 0.61
        let browser = CGRect(x: (rect.width - width) / 2, y: rect.height * 0.15, width: width, height: rect.height * 0.69)
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
        if stage == 0, let image = SurfaceImages.load("glass-study.png") {
            image.draw(in: CGRect(x: entry.minX + 5, y: entry.minY + 4, width: min(34, entry.height), height: entry.height - 8))
        } else {
            ("给 ChatGPT 发送消息" as NSString).draw(at: CGPoint(x: entry.minX + 8, y: entry.midY - 6), withAttributes: words)
        }
        let w = rect.width / 8
        let h = w * 0.53
        let right = placement >= 3
        let ys = [rect.maxY - h - 8, rect.midY - h / 2, rect.minY + 8]
        let tray = CGRect(x: right ? rect.maxX - w - 5 : rect.minX + 5, y: ys[placement % 3], width: w, height: h)
        let trayPath = NSBezierPath(roundedRect: tray, xRadius: 4, yRadius: 4)
        NSColor.white.withAlphaComponent(0.78).setFill()
        trayPath.fill()
        NSColor.white.setStroke()
        trayPath.stroke()
        let slot = tray.insetBy(dx: 3, dy: 3)
        SurfaceImages.load("glass-study.png")?.draw(in: CGRect(x: slot.minX, y: slot.midY - slot.width * 0.18, width: slot.width * 0.48, height: slot.width * 0.36))
        let sym = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        sym?.draw(in: CGRect(x: slot.midX + 2, y: slot.midY - 4, width: 11, height: 8))
        NSGraphicsContext.restoreGraphicsState()
    }
}
