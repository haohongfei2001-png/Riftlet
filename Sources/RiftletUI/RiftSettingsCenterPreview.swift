import AppKit
import RiftletCore
import QuartzCore

/// Drawn fixtures only. No image URL, filesystem, capture, queue or upload owner.
@MainActor
final class RiftSettingsCenterPreview: NSView {
    private(set) var configuration = RiftConfiguration()
    private let drawing = RiftSettingsDesktopIllustration(frame: .zero)
    var geometrySummary: String {
        let count = min(configuration.visibleCountPreference, 4)
        let title = configuration.placement?.title ?? "旧版位置"
        let countText = configuration.visibleCountPreference > count
            ? "\(configuration.visibleCountPreference) 张（示意前 \(count) 张）" : "\(count) 张"
        if configuration.desktopForm == .windChime {
            return title + " · " + countText + " · 风铃 · " + configuration.windChimeArrangement.title
        }
        return title + " · " + countText
    }

    init() {
        super.init(frame: .zero)
        drawing.frame = bounds
        drawing.autoresizingMask = [.width, .height]
        drawing.setAccessibilityElement(false)
        addSubview(drawing)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("截图布局预览")
    }
    required init?(coder: NSCoder) { nil }
    func update(configuration: RiftConfiguration, entryEnabled: Bool = false) {
        self.configuration = configuration
        drawing.configuration = configuration
        drawing.includesEntry = entryEnabled
        drawing.needsDisplay = true
        setAccessibilityValue(geometrySummary)
    }
}

@MainActor
private final class RiftSettingsDesktopIllustration: NSView {
    var configuration = RiftConfiguration()
    var includesEntry = true
    private static let thumbnails = [("glass-study","png"),("reading","svg"),("error","svg")].map { name,ext in
        Bundle.main.url(forResource:name,withExtension:ext).flatMap(NSImage.init(contentsOf:))
    }

    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let clip = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        clip.addClip()
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
            let f: CGFloat = dark ? 0.50 : 1
            return NSColor(srgbRed: r*f, green: g*f, blue: b*f, alpha: 1)
        }
        NSGradient(colors: [rgb(0.84, 0.95, 0.94), rgb(0.72, 0.80, 0.96), rgb(0.66, 0.66, 0.88)])?.draw(in: rect, angle: 8)
        let w = rect.width, h = rect.height
        func wave(_ start: CGFloat, _ first: NSPoint, _ second: NSPoint, _ end: CGFloat, _ c: NSColor) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: start*h))
            path.curve(to: CGPoint(x: w, y: end*h), controlPoint1: CGPoint(x: first.x*w, y: first.y*h),
                       controlPoint2: CGPoint(x: second.x*w, y: second.y*h))
            path.line(to: CGPoint(x: w, y: h)); path.line(to: CGPoint(x: 0, y: h)); path.close()
            c.setFill(); path.fill()
        }
        wave(0.85, CGPoint(x: 0.32,y: -0.52), CGPoint(x: 0.59,y: 1.65), 0.22, rgb(0.50,0.74,0.77))
        wave(0.67, CGPoint(x: 0.43,y: 1.39), CGPoint(x: 0.56,y: -0.52), 0.66, rgb(0.42,0.62,0.73))
        wave(0.93, CGPoint(x: 0.39,y: 1.25), CGPoint(x: 0.67,y: 0.34), 0.86, rgb(0.29,0.52,0.64))
        if configuration.desktopForm == .windChime {
            WindChimePlacementIllustration.draw(in: rect, configuration: configuration, flipped: isFlipped)
            NSColor.separatorColor.setStroke(); clip.lineWidth = 1; clip.stroke()
            return
        }
        let records = Array(WindChimePlacementIllustration.records.prefix(configuration.visibleCountPreference))
        let scale = rect.height / 480
        let desktop = CGRect(origin: .zero, size: CGSize(width: rect.width / scale, height: rect.height / scale))
        let layout: RiftLayoutResult
        switch configuration.desktopForm {
        case .tray:
            layout = RiftTrayLayout.make(records: records, visibleFrame: desktop, configuration: configuration,
                firstVisibleIndex: 0, backingScale: 1, captureEnabled: includesEntry)
        case .microSlit:
            layout = RiftLayout.make(records: records, visibleFrame: desktop, configuration: configuration)
        case .windChime: return
        }
        func placed(_ frame: CGRect) -> CGRect {
            CGRect(x: rect.minX + frame.minX * scale, y: rect.maxY - frame.maxY * scale,
                   width: frame.width * scale, height: frame.height * scale)
        }
        if !layout.surfaceFrame.isEmpty {
            let shell = NSBezierPath(roundedRect: placed(layout.surfaceFrame), xRadius: 4, yRadius: 4)
            switch configuration.trayTheme {
            case .system: NSColor.windowBackgroundColor.withAlphaComponent(0.8).setFill()
            case .violetGlass: NSColor(hue: 0.71, saturation: 0.21, brightness: 0.96, alpha: 0.75).setFill()
            case .custom: NSColor(hue: configuration.trayTintHue / 360, saturation: configuration.trayTintStrength * 0.30,
                                  brightness: 0.96, alpha: 0.75).setFill()
            }
            shell.fill()
        }
        if !layout.lineFrame.isEmpty {
            NSColor.secondaryLabelColor.setFill()
            placed(layout.lineFrame).fill()
        }
        for (index, row) in layout.rows.enumerated() {
            NSGraphicsContext.saveGraphicsState()
            placed(row.imageClipFrame.offsetBy(dx: row.frame.minX, dy: row.frame.minY)).clip()
            drawThumbnail(placed(row.imageFrame.offsetBy(dx: row.frame.minX, dy: row.frame.minY)),
                          rgb(0.33,0.68,0.62), index: index)
            NSGraphicsContext.restoreGraphicsState()
            if !row.numberFrame.isEmpty {
                let number = placed(row.numberFrame.offsetBy(dx: row.frame.minX, dy: row.frame.minY))
                ("\(row.ordinal)" as NSString).draw(in: number, withAttributes: [.font: NSFont.systemFont(ofSize: max(1, configuration.numberFontSize * scale)), .foregroundColor: NSColor.labelColor])
            }
        }
        if !layout.captureSlot.isEmpty {
            let slot = placed(layout.captureSlot)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: slot, xRadius: 2, yRadius: 2).fill()
            NSImage(systemSymbolName: "camera", accessibilityDescription: nil)?.draw(in: slot.insetBy(dx: slot.width * 0.22, dy: slot.height * 0.15))
        }
        NSColor.separatorColor.setStroke(); clip.lineWidth=1;clip.stroke()
    }

    private func drawThumbnail(_ rect: CGRect, _ tint: NSColor, index:Int) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect:rect,xRadius:1.5,yRadius:1.5).addClip()
        if let image=Self.thumbnails[index % Self.thumbnails.count], image.size.width>0, image.size.height>0 {
            NSColor.white.withAlphaComponent(0.72).setFill();rect.fill()
            let scale=min(rect.width/image.size.width,rect.height/image.size.height)
            let w=image.size.width*scale,h=image.size.height*scale
            image.draw(in:CGRect(x:rect.midX-w/2,y:rect.midY-h/2,width:w,height:h),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            return
        }
        tint.setFill();rect.fill()
        let path=NSBezierPath()
        path.move(to:CGPoint(x:rect.minX,y:rect.maxY))
        path.line(to:CGPoint(x:rect.midX-rect.width*0.14,y:rect.minY+rect.height*0.32))
        path.line(to:CGPoint(x:rect.midX+rect.width*0.10,y:rect.midY+rect.height*0.08))
        path.line(to:CGPoint(x:rect.maxX,y:rect.minY+rect.height*0.23))
        path.line(to:CGPoint(x:rect.maxX,y:rect.maxY));path.close()
        NSColor.black.withAlphaComponent(0.18).setFill();path.fill()
    }
}

/// Both settings and onboarding project the desktop renderer’s layout with bundled
/// sample images. There is no media store, screenshot source or input window here.
@MainActor
enum WindChimePlacementIllustration {
    private static let samples = [("glass-study", "png"), ("reading", "svg"), ("error", "svg"), ("glass-study", "png")]
    private static let images = samples.map { name, ext in
        Bundle.main.url(forResource: name, withExtension: ext).flatMap(NSImage.init(contentsOf:))
    }
    fileprivate static let records: [AssetRecord] = samples.indices.map { index in
        let size = images[index]?.size ?? NSSize(width: 160, height: 110)
        let image = ImportedAsset(sourceKey: "illustration-\(index)", fileName: samples[index].0,
            sha256: "", byteCount: 0, pixelWidth: Int(size.width), pixelHeight: Int(size.height),
            mediaType: "image/png", origin: .synthetic)
        return AssetRecord(image: image, sequence: Int64(index + 1), status: .pending, activeOperationID: nil)
    }

    static func draw(in rect: CGRect, configuration: RiftConfiguration, flipped: Bool) {
        guard rect.width > 0, rect.height > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        var sample = configuration
        sample.visibleCountPreference = min(records.count, configuration.visibleCountPreference)
        // Show up to four details at a legible scale within each short landscape schematic.
        let scale = rect.height / 444
        let display = CGRect(origin: .zero, size: CGSize(width: rect.width / scale, height: rect.height / scale))
        let layout = RiftWindChimeLayout.make(records: records, visibleFrame: display, configuration: sample)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.clip(to: rect)
        context.translateBy(x: rect.minX, y: flipped ? rect.maxY : rect.minY)
        context.scaleBy(x: scale, y: flipped ? -scale : scale)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let line = layout.lineFrame
        if !line.isEmpty {
            NSGradient(colors: [.clear, .secondaryLabelColor, .secondaryLabelColor, .clear],
                       atLocations: [0, 0.14, 0.93, 1], colorSpace: .deviceRGB)?
                .draw(in: line, angle: 90)
        }
        for row in layout.rows {
            guard let card = row.windChime else { continue }
            NSGraphicsContext.saveGraphicsState()
            context.translateBy(x: row.frame.minX, y: row.frame.minY)
            context.saveGState()
            context.concatenate(card.rotation)
            let outline = NSBezierPath(roundedRect: card.cardFrame, xRadius: RiftWindChimeLayout.corner,
                                       yRadius: RiftWindChimeLayout.corner)
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                              color: NSColor.black.withAlphaComponent(0.22).cgColor)
            NSColor.white.setFill()
            outline.fill()
            context.setShadow(offset: .zero, blur: 0)
            let innerRadius = max(0, RiftWindChimeLayout.corner - RiftWindChimeLayout.border)
            NSBezierPath(roundedRect: row.imageFrame, xRadius: innerRadius, yRadius: innerRadius).addClip()
            if let image = images[row.ordinal - 1] {
                image.draw(in: row.imageFrame, from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                NSColor.systemGray.setFill()
                row.imageFrame.fill()
            }
            context.restoreGState()
            (String(row.ordinal) as NSString).draw(in: row.numberFrame, withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: sample.numberFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ])
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
