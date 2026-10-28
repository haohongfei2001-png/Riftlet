import AppKit
import QuartzCore

/// Pointer-free presentation. It never becomes key and never receives clicks.
private final class EdgeDecorationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true; isReleasedWhenClosed = false; hidesOnDeactivate = false
        level = .floating; animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

final class RiftLineView: NSView {
    override func draw(_ rect: NSRect) {
        RiftVisualStyle.edge.setFill()
        bounds.fill()
    }
}

/// Input islands are precisely the two 20-point arrow buttons. The count between
/// them is a separate, pointer-free panel, so their transparent gap stays native.
@MainActor final class RiftPager {
    private final class ButtonPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private let countPanel = EdgeDecorationPanel()
    private let count = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []
    private var panels: [NSPanel] = []
    var onStep: ((Int) -> Void)?
    init() {
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = RiftVisualStyle.secondary; count.alignment = .center
        countPanel.contentView = count
        for index in 0..<2 {
            let p = ButtonPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false; p.level = .floating
            p.collectionBehavior = countPanel.collectionBehavior
            let b = NSButton(title: index == 0 ? "‹" : "›", target: self, action: #selector(step(_:)))
            b.tag = index == 0 ? -1 : 1; b.isBordered = false; b.font = .systemFont(ofSize: 16)
            b.contentTintColor = RiftVisualStyle.secondary
            b.setAccessibilityLabel(index == 0 ? "查看前面的截图" : "查看后面的截图")
            b.toolTip = index == 0 ? "上一组截图" : "下一组截图"
            p.contentView = b; buttons.append(b); panels.append(p)
        }
    }
    @objc private func step(_ sender: NSButton) { onStep?(sender.tag) }
    func update(_ layout: RiftLayoutResult, hidden: Bool, level: NSWindow.Level) {
        guard !hidden, !layout.pagerFrame.isEmpty else { hide(); return }
        let f = layout.pagerFrame
        count.stringValue = "\(layout.firstVisibleIndex + 1)–\(layout.firstVisibleIndex + layout.rows.count) / \(layout.totalCount)"
        countPanel.setFrame(CGRect(x: f.minX + 22, y: f.minY + 2, width: f.width - 44, height: 16), display: true)
        countPanel.level = level; countPanel.orderFrontRegardless()
        for (i, p) in panels.enumerated() {
            p.setFrame(CGRect(x: i == 0 ? f.minX : f.maxX - 20, y: f.minY, width: 20, height: 20), display: true)
            buttons[i].isEnabled = i == 0 ? layout.hasEarlier : layout.hasLater
            p.level = level; p.orderFrontRegardless()
        }
    }
    func hide() { countPanel.orderOut(nil); panels.forEach { $0.orderOut(nil) } }
    func close() { countPanel.close(); panels.forEach { $0.close() } }
}

/// Keep the full preview clear of every visible thumbnail/number input island,
/// while its vertical position continues to belong to the hovered row.
enum RiftPeekGeometry {
    static func frame(imageSize: CGSize, owner: CGRect, visible: CGRect, leadingInputEdge: CGFloat) -> CGRect? {
        guard [imageSize.width, imageSize.height, owner.midY, visible.minX, visible.minY,
               visible.maxX, visible.maxY, leadingInputEdge].allSatisfy(\.isFinite),
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let right = min(visible.maxX - 12, leadingInputEdge - 12)
        let availableWidth = right - (visible.minX + 12) - 16
        let availableHeight = visible.height - 24 - 16
        // The design sizes are maxima. Preserve the complete aspect ratio on
        // a narrow display instead of clamping the preview over input islands.
        let ratio = min(min(320 / imageSize.width, 240 / imageSize.height),
                        min(availableWidth / imageSize.width, availableHeight / imageSize.height))
        guard ratio.isFinite, ratio > 0 else { return nil }
        let width = imageSize.width * ratio + 16, height = imageSize.height * ratio + 16
        let y = max(visible.minY + 12, min(visible.maxY - height - 12, owner.midY - height / 2))
        return CGRect(x: right - width, y: y, width: width, height: height)
    }
}

/// Bounded, full-aspect hover preview; no source mutation or attachment API.
@MainActor final class RiftPeek {
    private let panel = EdgeDecorationPanel()
    private let image = NSImageView()
    private var epoch: UInt = 0
    private var leaveEpoch: UInt = 0
    private(set) var assetID: UUID?
    init() {
        let surface = RiftSurfaceView(); surface.cornerRadius = 10
        surface.addSubview(image)
        image.imageScaling = .scaleProportionallyUpOrDown
        panel.contentView = surface
        panel.setAccessibilityHidden(true)
    }
    func cancel() {
        epoch &+= 1; leaveEpoch &+= 1; assetID = nil; panel.orderOut(nil); panel.alphaValue = 1
        image.image = nil
    }
    func leave() {
        leaveEpoch &+= 1; let token = leaveEpoch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.leaveEpoch == token else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08; self.panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.leaveEpoch == token else { return }
                    self.cancel()
                }
            }
        }
    }
    func schedule(id: UUID, immediate: Bool = false, stillValid: @escaping () -> Bool,
                  load: @escaping (@escaping (CGImage?) -> Void) -> Void,
                  anchor: @escaping () -> (CGRect, CGRect, CGFloat)?) {
        leaveEpoch &+= 1
        if assetID == id && panel.isVisible { panel.alphaValue = 1; return }
        // A pending/abandoned decode must be rescheduled after re-entry.
        // The leave timer has its own epoch and cannot invalidate the new hover.
        cancel(); assetID = id; let token = epoch
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.45)) { [weak self] in
            guard let self, self.epoch == token, stillValid() else { return }
            load { [weak self] cg in
                guard let self, self.epoch == token, stillValid(), let cg, let (row, visible, leading) = anchor() else { return }
                guard let frame = RiftPeekGeometry.frame(imageSize: CGSize(width: cg.width, height: cg.height),
                    owner: row, visible: visible, leadingInputEdge: leading) else { self.cancel(); return }
                let size = CGSize(width: frame.width - 16, height: frame.height - 16)
                self.panel.setFrame(frame, display: true)
                self.image.frame = CGRect(origin: CGPoint(x: 8, y: 8), size: size)
                self.image.image = NSImage(cgImage: cg, size: size)
                self.panel.alphaValue = 0; self.panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.08
                    self.panel.animator().alphaValue = 1
                }
            }
        }
    }
    func close() { cancel(); panel.close() }
}
