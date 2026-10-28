import AppKit
import QuartzCore

/// Native settings preview. It owns no asset, queue, adapter or screenshot file.
@MainActor
public final class ArrivalMotionSettingsController: NSWindowController, NSWindowDelegate {
    private let choice = NSPopUpButton(frame: .zero, pullsDown: false)
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let preview = ArrivalPreviewView(frame: .zero)
    private var observer: NSObjectProtocol?
    private var mode: ArrivalMotionMode
    private var hasSelection: Bool
    private let onChoose: (ArrivalMotionMode) throws -> Void

    public init(mode: ArrivalMotionMode, hasExplicitSelection: Bool,
                onChoose: @escaping (ArrivalMotionMode) throws -> Void) {
        self.mode = mode; hasSelection = hasExplicitSelection; self.onChoose = onChoose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 468, height: 344),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "入缝动效 · 实施候选"
        window.isReleasedWhenClosed = false; window.backgroundColor = RiftVisualStyle.window
        super.init(window: window)
        window.delegate = self
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = root
        let title = RiftVisualStyle.label("截图到达边缘时", role: "title")
        let hint = RiftVisualStyle.label("仅改变新截图的入缝装饰，不关闭上传开始后的快速吞噬。截图始终可立即点击。")
        choice.addItems(withTitles: ArrivalMotionMode.allCases.map(\.title))
        choice.target = self; choice.action = #selector(choose)
        choice.setAccessibilityLabel("入缝动效")
        choice.font = RiftVisualStyle.bodyFont; choice.contentTintColor = RiftVisualStyle.accent
        let replay = NSButton(title: "再次预览", target: self, action: #selector(replay))
        RiftVisualStyle.style(replay)
        let caption = RiftVisualStyle.label("示意图预览", role: "secondary")
        let card = RiftSurfaceView()
        for view in [card, title, hint, choice, replay, preview, caption, detail] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        detail.font = RiftVisualStyle.secondaryFont; detail.textColor = RiftVisualStyle.secondary
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: hint.trailingAnchor),
            card.topAnchor.constraint(equalTo: choice.topAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: caption.bottomAnchor, constant: 12),
            choice.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            choice.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 20),
            choice.widthAnchor.constraint(equalToConstant: 170),
            replay.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            replay.centerYAnchor.constraint(equalTo: choice.centerYAnchor),
            preview.leadingAnchor.constraint(equalTo: choice.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: replay.trailingAnchor),
            preview.topAnchor.constraint(equalTo: choice.bottomAnchor, constant: 8),
            preview.heightAnchor.constraint(equalToConstant: 104),
            caption.leadingAnchor.constraint(equalTo: choice.leadingAnchor),
            caption.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 4),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: hint.trailingAnchor),
            detail.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
            detail.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16)
        ])
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh(play: true) }
            }
        refresh(play: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public func show() {
        window?.center(); showWindow(nil); window?.makeKeyAndOrderFront(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        refresh(play: true)
    }

    public func update(mode: ArrivalMotionMode, hasExplicitSelection: Bool) {
        self.mode = mode; hasSelection = hasExplicitSelection; refresh(play: true)
    }

    @objc private func choose() {
        guard ArrivalMotionMode.allCases.indices.contains(choice.indexOfSelectedItem) else { return }
        let value = ArrivalMotionMode.allCases[choice.indexOfSelectedItem]
        do {
            try onChoose(value)
            mode = value; hasSelection = true; refresh(play: true)
        } catch {
            choice.selectItem(at: ArrivalMotionMode.allCases.firstIndex(of: mode) ?? 0)
            detail.stringValue = "未能保存，仍使用原来的动效设置。请稍后重试。"
            RiftVisualStyle.applyTextStyle(detail)
        }
    }

    @objc private func replay() { refresh(play: true) }

    private func refresh(play: Bool) {
        choice.selectItem(at: ArrivalMotionMode.allCases.firstIndex(of: mode) ?? 0)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduced { detail.stringValue = "系统已开启“减少动态效果”，该次入缝静态呈现，仍保留已选偏好。" }
        else if !hasSelection { detail.stringValue = "尚未选择入缝动效，当前暂用“无”；不是正式默认裁决。" }
        else { detail.stringValue = "已保存。源位置无法确认时，截图会直接呈现。" }
        RiftVisualStyle.applyTextStyle(detail)
        preview.show(mode.effective(reduceMotion: reduced), animate: play && window?.isVisible == true)
    }

    public func windowWillClose(_ notification: Notification) { preview.stop() }
    public override func close() { preview.stop(); super.close() }
    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

@MainActor
private final class ArrivalPreviewView: NSView {
    private let clip = CALayer()
    private let imageLayer = CALayer()
    private let line = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        clip.masksToBounds = true
        layer?.addSublayer(clip); clip.addSublayer(imageLayer); layer?.addSublayer(line)
        imageLayer.contents = Self.makeImage()
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.magnificationFilter = .linear; imageLayer.minificationFilter = .trilinear
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("截图动效示意图")
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAppearance() }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.backgroundColor = RiftVisualStyle.window.cgColor
            layer?.borderColor = RiftVisualStyle.separator.cgColor
            layer?.borderWidth = 1 / max(1, window?.backingScaleFactor ?? 1)
            line.backgroundColor = RiftVisualStyle.secondary.withAlphaComponent(0.48).cgColor
            CATransaction.commit()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ mode: ArrivalMotionMode, animate: Bool) {
        guard bounds.width > 100, bounds.height > 80 else { return }
        stop(); updateAppearance()
        let edge = bounds.maxX - 20
        let target = CGRect(x: edge - 54, y: bounds.midY - 22.5, width: 72, height: 45)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        clip.frame = CGRect(x: 0, y: 0, width: edge, height: bounds.height)
        let lineWidth: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 1 / (window?.backingScaleFactor ?? 2)
        line.frame = CGRect(x: edge - lineWidth, y: target.minY - 8, width: lineWidth, height: target.height + 16)
        imageLayer.frame = target
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
        guard mode == .magnet, animate,
              let plan = MagnetMotionPlan(
                sourceRect: CGRect(x: 28, y: bounds.midY - 44, width: 140.8, height: 88),
                targetImageFrame: target, clippingEdgeX: edge, screenFrame: bounds) else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        plan.applyFinalState(to: imageLayer, relativeTo: .zero)
        imageLayer.add(plan.makeLayerAnimation(relativeTo: .zero), forKey: "arrival.preview")
        CATransaction.commit()
    }

    func stop() { imageLayer.removeAllAnimations() }

    private static func makeImage() -> CGImage? {
        // Readable neutral window fixture; no real screenshot or private content.
        let image = NSImage(size: NSSize(width: 640, height: 400))
        image.lockFocus()
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 640, height: 400).fill()
        NSColor(calibratedRed: 0.16, green: 0.25, blue: 0.34, alpha: 1).setFill()
        NSRect(x: 0, y: 330, width: 640, height: 70).fill()
        NSColor(calibratedRed: 0.66, green: 0.78, blue: 0.80, alpha: 1).setFill()
        NSRect(x: 36, y: 40, width: 180, height: 250).fill()
        NSColor(calibratedWhite: 0.52, alpha: 1).setFill()
        for (y, width) in [(270, 330), (228, 270), (186, 310), (102, 230)] {
            NSRect(x: 252, y: y, width: width, height: 16).fill()
        }
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
