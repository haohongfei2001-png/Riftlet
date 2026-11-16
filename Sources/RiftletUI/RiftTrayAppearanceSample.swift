import AppKit
import RiftletCore

/// A noninteractive specimen of the real tray. Its only images ship inside the app.
@MainActor
final class RiftTrayAppearanceSample: NSView {
    private let glass = RiftTrayGlass(frame: .zero)
    private let cards = Cards(frame: .zero)
    private var configuration = RiftConfiguration()
    private var entryEnabled = true
    private var observer: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glass)
        addSubview(cards)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(ProductCopy.text("截图托盘预览", "Screenshot Tray Preview"))
        cards.setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(configuration: RiftConfiguration, entryEnabled: Bool) {
        self.configuration = configuration
        self.entryEnabled = entryEnabled
        refreshMaterial()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshMaterial()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NSWorkspace.shared.notificationCenter
        if let observer { center.removeObserver(observer); self.observer = nil }
        if window != nil {
            observer = center.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                         object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshMaterial() }
            }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func refreshMaterial() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let palette = RiftTrayGlassPalette(colors: configuration.trayColors, appearance: effectiveAppearance,
                                               clearGlass: glass.usesClearGlass,
                                               transparency: configuration.trayBackgroundTransparency,
                                               cameraBodyColor: configuration.trayCameraBodyColor)
            glass.apply(palette)
            cards.palette = palette
            cards.needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        let width = min(bounds.width, bounds.height * 246 / 212)
        let display = CGRect(x: 0, y: 0, width: width * 8, height: max(480, bounds.height))
        let layout = RiftTrayLayout.make(records: Array(Cards.records.prefix(configuration.visibleCountPreference)),
                                         visibleFrame: display, configuration: configuration, firstVisibleIndex: 0,
                                         backingScale: Double(window?.backingScaleFactor ?? 1), captureEnabled: entryEnabled)
        let size = layout.surfaceFrame.size
        glass.frame = CGRect(origin: .init(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), size: size)
        cards.frame = glass.frame
        cards.tray = layout
        cards.needsDisplay = true
    }

    private final class Cards: NSView {
        static let images = [("glass-study","png"), ("reading","svg"), ("error","svg")].map { name,ext in
            Bundle.main.url(forResource: name, withExtension: ext).flatMap(NSImage.init(contentsOf:))
        }
        static let records = images.enumerated().map { index, image in
            let size = image?.size ?? CGSize(width: 160, height: 110)
            return AssetRecord(image: ImportedAsset(sourceKey: "tray-preview-\(index)", fileName: "Sample \(index + 1)",
                sha256: "", byteCount: 0, pixelWidth: Int(size.width), pixelHeight: Int(size.height),
                mediaType: "image/png", origin: .synthetic), sequence: Int64(index + 1), status: .pending, activeOperationID: nil)
        }
        var palette: RiftTrayGlassPalette?
        var tray: RiftLayoutResult?

        override func draw(_ dirtyRect: NSRect) {
            guard let tray, let palette else { return }
            let origin = tray.surfaceFrame.origin
            for row in tray.rows {
                guard let image = Self.images[row.ordinal - 1] else { continue }
                NSGraphicsContext.saveGraphicsState()
                let dx = row.frame.minX-origin.x, dy = row.frame.minY-origin.y
                if let card = row.trayCardFrame {
                    let shape = NSBezierPath(roundedRect: card.offsetBy(dx: dx, dy: dy), xRadius: 3, yRadius: 3)
                    NSColor.white.withAlphaComponent(0.9).setFill()
                    shape.fill(); shape.addClip()
                }
                row.imageClipFrame.offsetBy(dx: dx, dy: dy).clip()
                image.draw(in: row.imageFrame.offsetBy(dx: dx, dy: dy))
                NSGraphicsContext.restoreGraphicsState()
            }
            let slot = tray.captureSlot.offsetBy(dx: -origin.x, dy: -origin.y)
            guard !slot.isEmpty else { return }
            let unit = bounds.width / 246
            let center = RiftTrayKeyDrawing.drawFace(palette: palette, bounds: slot, unit: unit,
                scale: window?.backingScaleFactor ?? 1, isFlipped: false, highlighted: false)
            RiftTrayKeyDrawing.drawCamera(palette: palette, bounds: slot, unit: unit, centerY: center, isFlipped: false)
        }
    }
}
