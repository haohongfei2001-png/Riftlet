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
    var excludedContactBands: [CGRect] = [] { didSet { needsDisplay = true } }
    override func draw(_ rect: NSRect) {
        RiftVisualStyle.edge.setFill()
        let path = NSBezierPath(rect: bounds)
        path.windingRule = .evenOdd
        for band in excludedContactBands {
            let clipped = band.intersection(bounds)
            if !clipped.isEmpty { path.appendRect(clipped) }
        }
        path.fill()
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
            let b = NSButton(title: index == 0 ? "⌃" : "⌄", target: self, action: #selector(step(_:)))
            b.tag = index == 0 ? -1 : 1; b.isBordered = false; b.font = .systemFont(ofSize: 16)
            b.contentTintColor = RiftVisualStyle.secondary
            b.setAccessibilityLabel(index == 0 ? "查看前面的截图" : "查看后面的截图")
            b.toolTip = index == 0 ? "上一组截图" : "下一组截图"
            p.contentView = b; buttons.append(b); panels.append(p)
        }
    }
    @objc private func step(_ sender: NSButton) { onStep?(sender.tag) }
    func update(_ layout: RiftLayoutResult, hidden: Bool, level: NSWindow.Level) {
        countPanel.orderOut(nil)
        for (i, panel) in panels.enumerated() {
            let frame = i == 0 ? layout.earlierArrowFrame : layout.laterArrowFrame
            guard !hidden, !frame.isEmpty else { panel.orderOut(nil); continue }
            buttons[i].isEnabled = true
            panel.setFrame(frame, display: true); panel.level = level; panel.orderFrontRegardless()
        }
    }

    func hide() { countPanel.orderOut(nil); panels.forEach { $0.orderOut(nil) } }
    func close() { countPanel.close(); panels.forEach { $0.close() } }
}

/// Keep the full preview clear of every visible thumbnail/number input island,
/// while its vertical position continues to belong to the hovered row.
enum RiftPeekGeometry {
    static func frame(imageSize: CGSize, owner: CGRect, visible: CGRect, leadingInputEdge: CGFloat, leftSide: Bool = false) -> CGRect? {
        guard [imageSize.width, imageSize.height, owner.midY, visible.minX, visible.minY,
               visible.maxX, visible.maxY, leadingInputEdge].allSatisfy(\.isFinite),
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        if leftSide {
            let mirror = visible.minX + visible.maxX
            guard let r = frame(imageSize: imageSize, owner: owner, visible: visible,
                leadingInputEdge: mirror - leadingInputEdge) else { return nil }
            return CGRect(x: mirror - r.maxX, y: r.minY, width: r.width, height: r.height)
        }
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
    static func sessionFrame(canvas: CGSize, owner: CGRect, visible: CGRect,
                             leading: CGFloat, leftSide: Bool) -> CGRect? {
        if leftSide {
            let mirror = visible.minX + visible.maxX
            guard let result = sessionFrame(canvas: canvas, owner: owner, visible: visible,
                leading: mirror - leading, leftSide: false) else { return nil }
            return CGRect(x: mirror - result.maxX, y: result.minY, width: result.width, height: result.height)
        }
        let right = min(visible.maxX - 12, leading - 12)
        let available = CGSize(width: right - visible.minX - 28, height: visible.height - 56)
        guard canvas.width > 0, canvas.height > 0,
              [canvas.width, canvas.height, available.width, available.height, owner.midY].allSatisfy(\.isFinite) else { return nil }
        let scale = min(1, min(available.width / canvas.width, available.height / canvas.height))
        guard scale > 0 else { return nil }
        let size = CGSize(width: canvas.width * scale + 16, height: canvas.height * scale + 32)
        let y = max(visible.minY + 12, min(visible.maxY - size.height - 12, owner.midY - size.height / 2))
        return CGRect(x: right - size.width, y: y, width: size.width, height: size.height)
    }

}

struct RiftPeekItem: Equatable {
    let id: UUID
    let visibilityRevision: Int64
    let imageSize: CGSize
}

/// Bounded, full-aspect hover preview; no source mutation or attachment API.
@MainActor final class RiftPeek {
    private let panel = EdgeDecorationPanel()
    private let surface = RiftSurfaceView()
    private let image = NSImageView()
    private let note = NSTextField(wrappingLabelWithString: "")
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let later: Scheduler
    private let rankLabel = NSTextField(labelWithString: "")
    private var page: [RiftPeekItem] = []
    private var fixedFrame: CGRect?
    private var warm = false
    private var candidate: UUID?
    private var requestEpoch: UInt = 0
    private var eligible = false
    private var decoded: CGImage?
    private var present: (() -> Void)?
    private var runningDecode = false
    private var pendingDecode: (() -> Void)?
    private(set) var displayedAssetID: UUID?
    private(set) var displayedRank: Int?
    private var epoch: UInt = 0
    private var leaveEpoch: UInt = 0
    private(set) var assetID: UUID?
    private(set) var noteText: String?
    var onNoteVisibilityChange: ((UUID, Bool) -> Void)?
    var presentationPanel: NSPanel { panel }
    var isNoteVisible: Bool { noteText != nil && panel.isVisible }
    init(schedule: @escaping Scheduler = { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
    }) {
        later = schedule
        surface.addSubview(rankLabel)
        rankLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        rankLabel.textColor = RiftVisualStyle.secondary
        rankLabel.alignment = .center
        rankLabel.isHidden = true
        surface.cornerRadius = 10
        surface.addSubview(image)
        surface.addSubview(note)
        note.font = .systemFont(ofSize: 13)
        note.textColor = RiftVisualStyle.ink
        note.isHidden = true
        note.setAccessibilityElement(false)
        image.imageScaling = .scaleProportionallyUpOrDown
        panel.contentView = surface
        panel.setAccessibilityHidden(true)
    }
    func cancel() {
        let visibleNote = isNoteVisible ? assetID : nil
        epoch &+= 1; leaveEpoch &+= 1; assetID = nil; panel.orderOut(nil); panel.alphaValue = 1
        image.image = nil; noteText = nil; note.isHidden = true
        requestEpoch &+= 1; candidate = nil; decoded = nil; eligible = false
        present = nil; pendingDecode = nil; page = []; fixedFrame = nil; warm = false
        displayedAssetID = nil; displayedRank = nil; rankLabel.isHidden = true
        if let visibleNote { onNoteVisibilityChange?(visibleNote, false) }
    }
    func leave() {
        // A waiting explanation is only valid on its original input island.
        // It must not survive the image-preview leave animation.
        if noteText != nil { cancel(); return }
        leaveEpoch &+= 1; let token = leaveEpoch
        later(0.1) { [weak self] in
            guard let self, self.leaveEpoch == token else { return }
            // Bounded, epoch-guarded opacity steps cannot outlive re-entry.
            // NSWindow's animator otherwise keeps writing alpha after cancellation.
            for step in 1...5 {
                self.later(Double(step) * 0.016) { [weak self] in
                    guard let self, self.leaveEpoch == token else { return }
                    self.panel.alphaValue = 1 - Double(step) / 5
                    if step == 5 { self.cancel() }
                }
            }
        }
    }
    func schedule(id: UUID, immediate: Bool = false, leftSide: Bool = false,
                  rank: Int = 0, page incomingPage: [RiftPeekItem] = [],
                  stillValid: @escaping () -> Bool,
                  load: @escaping (@escaping (CGImage?) -> Void) -> Void,
                  anchor: @escaping () -> (CGRect, CGRect, CGFloat)?) {
        guard stillValid() else { cancel(); return }
        leaveEpoch &+= 1
        if noteText != nil || page != incomingPage { cancel() }
        page = incomingPage
        if candidate == id { panel.alphaValue = 1; present?(); return }
        requestEpoch &+= 1
        let request = requestEpoch, session = epoch
        candidate = id; assetID = id; eligible = immediate; decoded = nil
        displayedAssetID = nil; displayedRank = nil; image.image = nil
        rankLabel.stringValue = rank > 0 ? "\(rank)" : ""
        rankLabel.isHidden = false
        let valid = { [weak self] in
            guard let self else { return false }
            return self.epoch == session && self.requestEpoch == request
                && self.candidate == id && self.noteText == nil
        }
        present = { [weak self] in
            guard let self, valid(), stillValid(), self.eligible,
                  let (row, visible, leading) = anchor() else { return }
            if self.fixedFrame == nil {
                let sizes: [CGSize]
                if !incomingPage.isEmpty { sizes = incomingPage.map(\.imageSize) }
                else if let cg = self.decoded { sizes = [CGSize(width: cg.width, height: cg.height)] }
                else { return }
                let fits = sizes.filter { $0.width > 0 && $0.height > 0 && $0.width.isFinite && $0.height.isFinite }.map { size in
                    let scale = min(320 / size.width, 240 / size.height)
                    return CGSize(width: size.width * scale, height: size.height * scale)
                }
                let canvas = CGSize(width: fits.map(\.width).max() ?? 0, height: fits.map(\.height).max() ?? 0)
                guard let frame = RiftPeekGeometry.sessionFrame(canvas: canvas, owner: row,
                    visible: visible, leading: leading, leftSide: leftSide) else { self.cancel(); return }
                self.fixedFrame = frame
            }
            guard let frame = self.fixedFrame else { return }
            self.surface.cornerRadius = 10; self.image.isHidden = false
            self.panel.setFrame(frame, display: true)
            self.image.frame = CGRect(x: 8, y: 24, width: frame.width - 16, height: frame.height - 32)
            self.rankLabel.frame = CGRect(x: 8, y: 8, width: frame.width - 16, height: 16)
            // One main-actor transaction owns all three values; never crossfade text images.
            if let cg = self.decoded {
                self.image.image = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
                self.displayedAssetID = id; self.displayedRank = rank
            } else {
                self.image.image = nil; self.displayedAssetID = nil; self.displayedRank = nil
            }
            self.rankLabel.stringValue = rank > 0 ? "\(rank)" : ""
            self.panel.alphaValue = 1; self.panel.orderFrontRegardless(); self.warm = true
        }
        let delay: TimeInterval = immediate ? 0 : (warm ? 0.09 : 0.45)
        later(delay) { [weak self] in
            guard let self, valid() else { return }
            self.eligible = true; self.present?()
        }
        // Only one actual cache/decode request may run; intermediate hover intents
        // replace this slot rather than accumulating on ImageIO's serial queue.
        pendingDecode = { [weak self] in
            guard let self, valid() else { return }
            self.runningDecode = true
            load { [weak self] cg in
                guard let self else { return }
                self.runningDecode = false
                if valid() { self.decoded = cg; self.present?() }
                self.startLatestDecode()
            }
        }
        startLatestDecode()
    }

    private func startLatestDecode() {
        guard !runningDecode, let next = pendingDecode else { return }
        pendingDecode = nil; next()
    }

    /// Reuses the same pointer-free surface as image peek. The caller owns the
    /// selection/operation identity and validates it again at the deadline.
    func scheduleNote(id: UUID, text: String, delay: TimeInterval, leftSide: Bool = false,
                      stillValid: @escaping () -> Bool,
                      anchor: @escaping () -> (CGRect, CGRect, CGFloat)?) {
        if assetID == id, noteText == text { return }
        cancel(); assetID = id; noteText = text
        let token = epoch
        later(max(0, delay)) { [weak self] in
            guard let self, self.epoch == token else { return }
            guard stillValid(), let (row, visible, leading) = anchor() else { self.cancel(); return }
            let right = leftSide ? visible.maxX - 12 : min(visible.maxX - 12, leading - 12)
            let width = min(240, leftSide ? right - leading - 12 : right - visible.minX - 12)
            guard width >= 96 else { self.cancel(); return }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.minimumLineHeight = 18; paragraph.maximumLineHeight = 18
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: RiftVisualStyle.ink,
                .paragraphStyle: paragraph])
            let measured = attributed.boundingRect(with: CGSize(width: width - 24, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            let height = ceil(measured.height) + 26
            guard height <= visible.height - 24 else { self.cancel(); return }
            let y = max(visible.minY + 12, min(visible.maxY - height - 12, row.midY - height / 2))
            self.surface.cornerRadius = 8; self.image.isHidden = true
            self.note.attributedStringValue = attributed; self.note.isHidden = false
            self.panel.setFrame(CGRect(x: leftSide ? leading + 12 : right - width, y: y, width: width, height: height), display: true)
            self.note.frame = CGRect(x: 12, y: 12, width: width - 24, height: height - 24)
            self.surface.needsDisplay = true
            self.panel.alphaValue = 1; self.panel.orderFrontRegardless()
            self.onNoteVisibilityChange?(id, true)
            self.later(2.4) { [weak self] in
                guard let self, self.epoch == token else { return }
                self.cancel()
            }
        }
    }
    func close() { cancel(); panel.close() }
}
