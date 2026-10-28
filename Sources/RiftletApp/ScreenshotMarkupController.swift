import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The reference's small, optional rectangle editor. The system-generated
/// original is immutable; an edited result is a distinct application image.
@MainActor
final class ScreenshotMarkupController: NSWindowController, NSWindowDelegate {
    var onFinish: ((Data?) -> Void)?
    private let canvas: ScreenshotMarkupCanvas
    private let undoButton = NSButton(title: "撤销", target: nil, action: nil)
    private var finished = false

    init?(pngData: Data) {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              Self.supportsMarkup(image) else { return nil }
        canvas = ScreenshotMarkupCanvas(image: image)
        let panel = ScreenshotMarkupPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "截图标注"; panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.minSize = NSSize(width: 360, height: 260)
        super.init(window: panel)
        panel.delegate = self
        let content = NSView(); content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content
        let hint = NSTextField(labelWithString: "拖动添加矩形标注")
        hint.textColor = .secondaryLabelColor
        let original = NSButton(title: "保留原图", target: self, action: #selector(keepOriginal))
        let done = NSButton(title: "完成", target: self, action: #selector(finishEditing))
        done.keyEquivalent = "\r"
        undoButton.target = self; undoButton.action = #selector(undoMark)
        undoButton.keyEquivalent = "z"; undoButton.keyEquivalentModifierMask = .command
        undoButton.isEnabled = false
        for button in [undoButton, original, done] { button.bezelStyle = .rounded }
        let actions = NSStackView(views: [undoButton, original, NSView(), done])
        actions.orientation = .horizontal; actions.spacing = 8
        for view in [hint, canvas, actions] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            canvas.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            actions.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 12),
            actions.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
        canvas.onChange = { [weak self] hasMarks in self?.undoButton.isEnabled = hasMarks }
        canvas.onEscape = { [weak self] in self?.keepOriginal() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The small editor renders an 8-bit SDR RGB derivative. Restrict it to
    /// recognized sRGB / Display P3 profiles; unknown transfer functions and
    /// high-bit-depth sources take the byte-preserving original path.
    static func supportsMarkup(_ image: CGImage) -> Bool {
        guard image.bitsPerComponent == 8, let space = image.colorSpace,
              space.model == .rgb, let name = space.name else { return false }
        return name == CGColorSpace.sRGB || name == CGColorSpace.displayP3
    }

    func present() {
        window?.center(); window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
    }

    @objc private func undoMark() { canvas.undoMark() }
    @objc private func keepOriginal() { complete(nil) }
    @objc private func finishEditing() {
        guard !canvas.marks.isEmpty else { complete(nil); return }
        guard let data = canvas.encodedPNG() else { NSSound.beep(); return }
        complete(data)
    }

    /// Cancelling capture while annotating keeps the already captured original.
    func keepOriginalAndClose() { complete(nil) }

    func windowShouldClose(_ sender: NSWindow) -> Bool { complete(nil); return false }

    private func complete(_ data: Data?) {
        guard !finished else { return }
        finished = true
        window?.orderOut(nil)
        let callback = onFinish; onFinish = nil
        callback?(data)
        window?.close()
    }
}

private final class ScreenshotMarkupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ScreenshotMarkupCanvas: NSView {
    let image: CGImage
    private(set) var marks: [CGRect] = []
    private var start: CGPoint?
    private var draft: CGRect?
    var onChange: ((Bool) -> Void)?
    var onEscape: (() -> Void)?

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityLabel("拖动添加截图矩形标注")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var acceptsFirstResponder: Bool { true }

    var imageRect: CGRect {
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = imageRect
        context.draw(image, in: rect)
        context.setStrokeColor(NSColor.systemRed.cgColor); context.setLineWidth(2)
        for mark in marks + (draft.map { [$0] } ?? []) {
            context.stroke(CGRect(x: rect.minX + mark.minX * rect.width,
                                  y: rect.minY + mark.minY * rect.height,
                                  width: mark.width * rect.width, height: mark.height * rect.height))
        }
    }

    private func normalized(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        return CGPoint(x: max(0, min(1, (p.x - r.minX) / max(1, r.width))),
                       y: max(0, min(1, (p.y - r.minY) / max(1, r.height))))
    }

    override func mouseDown(with event: NSEvent) {
        guard imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self); start = normalized(event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = normalized(event)
        draft = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                       width: abs(start.x - p.x), height: abs(start.y - p.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if let draft, draft.width * CGFloat(image.width) >= 2,
           draft.height * CGFloat(image.height) >= 2 { marks.append(draft) }
        start = nil; draft = nil; needsDisplay = true; onChange?(!marks.isEmpty)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
    func undoMark() {
        if !marks.isEmpty { marks.removeLast() }
        draft = nil; start = nil; needsDisplay = true; onChange?(!marks.isEmpty)
    }

    func encodedPNG() -> Data? {
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setStrokeColor(CGColor(red: 0.89, green: 0.26, blue: 0.24, alpha: 1))
        context.setLineWidth(max(3, CGFloat(image.width) / 230))
        for mark in marks {
            context.stroke(CGRect(x: mark.minX * CGFloat(image.width), y: mark.minY * CGFloat(image.height),
                                  width: mark.width * CGFloat(image.width), height: mark.height * CGFloat(image.height)))
        }
        guard let output = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
