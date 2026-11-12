import AppKit
import RiftletCore
import QuartzCore

/// Drawn fixtures only. No image URL, filesystem, capture, queue or upload owner.
@MainActor
final class RiftSettingsCenterPreview: NSView {
    enum Kind { case geometry, arrival, swallow }
    let kind: Kind
    private(set) var playCount = 0
    private(set) var lastDuration: Double = 0
    private(set) var configuration = RiftConfiguration()
    private var mode = ArrivalMotionMode.none
    private var reduceMotion = false
    private var desktopIllustration: RiftSettingsDesktopIllustration?
    private let clip = CALayer()
    private let tile = CALayer()
    private let titleBand = CALayer()
    private let lines = (0..<3).map { _ in CALayer() }
    private let edge = CALayer()
    private var drawnBounds = NSRect.zero
    var isAnimating: Bool { tile.animation(forKey: "settings.preview") != nil }
    var geometrySummary: String {
        let count = min(configuration.visibleCountPreference, 4)
        let title = configuration.placement?.title ?? "旧版位置"
        let countText = configuration.visibleCountPreference > count
            ? "\(configuration.visibleCountPreference) 张（示意前 \(count) 张）" : "\(count) 张"
        if configuration.desktopForm == .windChime {
            return title + " · " + countText + " · 风铃 · " + configuration.windChimeArrangement.title
        }
        if configuration.desktopForm == .tray && configuration.trayFollowsSaytile {
            return "同屏示意 · Saytile 下方 · " + countText
        }
        return title + " · " + countText
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7; layer?.masksToBounds = true
        layer?.addSublayer(clip); layer?.addSublayer(edge)
        clip.masksToBounds = true; clip.addSublayer(tile)
        tile.cornerRadius = 4; tile.masksToBounds = true
        tile.addSublayer(titleBand)
        lines.forEach { tile.addSublayer($0) }
        setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel(kind == .geometry ? "布局示意，不是真实截图" : kind == .arrival ? "入缝动效示意图" : "快速吞噬示意图")
        if kind == .geometry {
            clip.isHidden = true; edge.isHidden = true
            let drawing = RiftSettingsDesktopIllustration(frame: bounds)
            drawing.autoresizingMask = [.width, .height]
            drawing.setAccessibilityElement(false)
            addSubview(drawing)
            desktopIllustration = drawing
        }
    }
    required init?(coder: NSCoder) { nil }
    func update(configuration: RiftConfiguration, mode: ArrivalMotionMode, reduceMotion: Bool, entryEnabled: Bool = false) {
        let changed = self.configuration != configuration || self.mode != mode || self.reduceMotion != reduceMotion
        self.configuration = configuration; self.mode = mode; self.reduceMotion = reduceMotion
        if let drawing = desktopIllustration {
            drawing.configuration = configuration
            drawing.visible = configuration.visibleCountPreference
            drawing.includesEntry = entryEnabled
            drawing.placement = RiftPlacement.allCases.firstIndex(of: configuration.placement ?? .rightMiddle) ?? 4
            drawing.hue = configuration.trayTheme == .custom ? configuration.trayTintHue / 360 : 0.71
            switch configuration.trayTheme {
            case .system: drawing.saturation = 0.02
            case .violetGlass: drawing.saturation = 0.21
            case .custom: drawing.saturation = configuration.trayTintStrength * 0.30
            }
            drawing.needsDisplay = true
            setAccessibilityValue(geometrySummary)
        }
        // An unrelated status refresh must neither restart nor stop a preview.
        if changed { stop(); positionLayers() }
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors(); needsDisplay = true }
    override func layout() {
        super.layout()
        if bounds != drawnBounds { stop(); positionLayers() }
    }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.backgroundColor = SettingsNativeStyle.color(.window).cgColor
            layer?.borderColor = SettingsNativeStyle.color(.border).cgColor
            layer?.borderWidth = 1
            tile.backgroundColor = SettingsNativeStyle.color(.surface).cgColor
            tile.borderColor = SettingsNativeStyle.color(.border).cgColor; tile.borderWidth = 1
            titleBand.backgroundColor = SettingsNativeStyle.color(.accent).withAlphaComponent(0.7).cgColor
            lines.forEach { $0.backgroundColor = SettingsNativeStyle.color(.secondary).withAlphaComponent(0.4).cgColor }
            edge.backgroundColor = SettingsNativeStyle.color(.secondary).withAlphaComponent(0.5).cgColor
            CATransaction.commit()
        }
    }
    private func positionLayers() {
        drawnBounds = bounds
        guard kind != .geometry else { colors(); return }
        let seam = bounds.maxX - 26
        let target = CGRect(x: seam - 56, y: bounds.midY - 25, width: 74, height: 50)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        clip.frame = CGRect(x: 0, y: 0, width: max(0, seam), height: bounds.height)
        tile.frame = target
        edge.frame = CGRect(x: seam - 0.5, y: bounds.midY - 35, width: 1, height: 70)
        titleBand.frame = CGRect(x: 0, y: 39, width: 74, height: 11)
        for (index, line) in lines.enumerated() { line.frame = CGRect(x: 9, y: 10 + index * 8, width: 45 - index * 6, height: 3) }
        CATransaction.commit()
        colors()
    }
    func play() {
        guard kind != .geometry, window?.isVisible == true, bounds.width > 100 else { return }
        stop(); positionLayers(); playCount += 1
        if kind == .arrival {
            guard mode.effective(reduceMotion: reduceMotion) == .magnet else { lastDuration = 0; return }
            let target = tile.frame
            guard let plan = MagnetMotionPlan(sourceRect: CGRect(x: 24, y: bounds.midY - 42, width: 135, height: 84),
                    targetImageFrame: target, clippingEdgeX: clip.frame.maxX, screenFrame: bounds) else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            plan.applyFinalState(to: tile, relativeTo: .zero)
            let animation = plan.makeLayerAnimation(relativeTo: .zero)
            lastDuration = plan.totalDuration
            tile.add(animation, forKey: "settings.preview")
            CATransaction.commit()
        } else {
            let duration = reduceMotion ? min(0.08, configuration.swallowDuration) : configuration.swallowDuration
            lastDuration = duration
            guard duration > 0 else { return }
            let movement = CABasicAnimation(keyPath: "position.x")
            movement.fromValue = tile.position.x
            movement.toValue = tile.position.x + 90
            movement.duration = duration
            movement.timingFunction = CAMediaTimingFunction(name: .easeIn)
            // Presentation-only motion returns to its model position on finish,
            // ready for another explicit preview; it never changes a queue item.
            tile.add(movement, forKey: "settings.preview")
        }
    }
    func stop() { tile.removeAllAnimations() }

}

/// Schematic display preview in Settings. Geometry is expressed in display points.
@MainActor
private final class RiftSettingsDesktopIllustration: NSView {
    var configuration = RiftConfiguration()
    private var showsTray: Bool { configuration.desktopForm == .tray }
    var placement = 4
    var visible = 3
    var hue: CGFloat = 0.71
    var saturation: CGFloat = 0.21
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
        func fill(_ r: CGRect, radius: CGFloat, color: NSColor) {
            color.setFill(); NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius).fill()
        }
        let tones:[NSColor] = [rgb(0.86,0.74,0.50),rgb(0.33,0.68,0.62),rgb(0.54,0.57,0.80),rgb(0.76,0.68,0.82)]
        if showsTray {
            let frames = TrayPlacementIllustration.frames(in: rect, configuration: configuration, twoRows: visible >= 2,
                                                          withSaytile: configuration.trayFollowsSaytile, flipped: isFlipped)
            if let companion = frames.saytile {
                fill(companion, radius: 4, color: .windowBackgroundColor.withAlphaComponent(0.90))
                let inset = companion.width * 0.10
                for (line, fraction) in [0.76, 0.54].enumerated() {
                    let bar = CGRect(x: companion.minX + inset, y: companion.minY + companion.height * (0.28 + CGFloat(line) * 0.23),
                                     width: companion.width * fraction, height: max(1, companion.height * 0.07))
                    fill(bar, radius: 1, color: .secondaryLabelColor)
                }
            }
            let shell = frames.tray
            fill(shell,radius:5,color:NSColor(srgbRed:1,green:1,blue:1,alpha:0.75))
            fill(shell.insetBy(dx:1,dy:1),radius:4,color:NSColor(hue:hue,saturation:saturation,brightness:0.96,alpha:0.65))
            let gap = shell.width * 0.035, cell = (shell.width - 3 * gap) / 2
            let rows = visible >= 2 ? 2.0 : 1.0
            let ch = (shell.height - (rows + 1) * gap) / rows
            let total = min(4, visible + (includesEntry ? 1 : 0))
            for i in 0..<total {
                let r = CGRect(x: shell.minX + gap + CGFloat(i % 2) * (cell + gap),
                               y: shell.minY + gap + CGFloat(i / 2) * (ch + gap), width: cell, height: ch)
                if includesEntry && i == min(visible,3) && visible < 4 {
                    fill(r,radius:2,color:.white.withAlphaComponent(0.72))
                    let sym=NSImage(systemSymbolName:"camera",accessibilityDescription:nil)
                    sym?.draw(in:r.insetBy(dx:cell*0.22,dy:ch*0.15))
                } else { drawThumbnail(r, tones[i], index:i) }
            }
        } else {
            let sideWidth = w * 0.065, sideHeight = sideWidth * 1.75
            let x = placement < 3 ? 9 : w - sideWidth - 9
            let y: CGFloat
            switch placement % 3 { case 0: y=8; case 2: y=h-sideHeight-8; default:y=(h-sideHeight)/2 }
            fill(CGRect(x:placement<3 ? x : x+sideWidth-1,y:y,width:1,height:sideHeight),radius:1,color:.white)
            let ch=sideWidth*0.48
            for i in 0..<min(3,visible) {
                drawThumbnail(CGRect(x:x+2,y:y+CGFloat(i)*(ch+3),width:sideWidth-4,height:ch),tones[i],index:i)
            }
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

/// Project the same point-based layout used by the desktop onto a schematic screen.
enum TrayPlacementIllustration {
    static func frames(in rect: CGRect, configuration: RiftConfiguration, twoRows: Bool,
                       withSaytile: Bool, flipped: Bool) -> (tray: CGRect, saytile: CGRect?) {
        guard rect.width > 0, rect.height > 0 else { return (.zero, nil) }
        let scale = rect.width / 1440
        let desktop = CGRect(x: 0, y: 0, width: 1440, height: rect.height / scale)
        let width = desktop.width / 8
        let height = min(desktop.height * 0.225, width * 173 / 325)
        let companion = withSaytile ? CGRect(x: desktop.maxX - 14 - width, y: desktop.maxY - 14 - height,
                                              width: width, height: height) : nil
        let geometry = RiftTrayLayout.geometry(visibleFrame: desktop, configuration: configuration, twoRows: twoRows,
                                              backingScale: 2, saytileGlassFrame: companion)
        func project(_ frame: CGRect) -> CGRect {
            CGRect(x: rect.minX + frame.minX * scale,
                   y: flipped ? rect.maxY - frame.maxY * scale : rect.minY + frame.minY * scale,
                   width: frame.width * scale, height: frame.height * scale)
        }
        return (project(geometry.frame), companion.map(project))
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
    private static let records: [AssetRecord] = samples.indices.map { index in
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
