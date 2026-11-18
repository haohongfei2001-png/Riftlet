import AppKit

@MainActor
enum RiftTrayKeyDrawing {
    static func drawFace(palette: RiftTrayGlassPalette, bounds: CGRect, unit: CGFloat, scale: CGFloat,
                         isFlipped: Bool, highlighted: Bool) -> CGFloat {
        let radius = min(unit * 12, min(bounds.width, bounds.height) / 2)
        let stroke = max(1 / scale, unit * 0.68)
        let outline = bounds.insetBy(dx: stroke / 2, dy: stroke / 2)
        let foot = min(4.5 * unit, bounds.height * 0.08)
        let upper = CGRect(x: outline.minX, y: outline.minY + (isFlipped ? 0 : foot),
                           width: outline.width, height: max(0, outline.height - foot))
        let face = NSBezierPath(roundedRect: upper, xRadius: radius, yRadius: radius)
        let base = NSBezierPath(roundedRect: outline, xRadius: radius, yRadius: radius)
        base.windingRule = .evenOdd
        base.append(face)
        palette.keyFoot.setFill()
        base.fill()
        palette.key.setFill()
        face.fill()
        if highlighted {
            palette.ink.withAlphaComponent(0.08).setFill()
            face.fill()
        }
        palette.keyRim.setStroke()
        face.lineWidth = stroke
        face.stroke()

        return upper.midY
    }
    /// The selected reference has a raised viewfinder above a centered lens.
    /// Trace the 28 × 24 silhouette in top-down coordinates even on a flipped NSButton.
    static func drawCamera(palette: RiftTrayGlassPalette, bounds: CGRect, unit: CGFloat, centerY: CGFloat, isFlipped: Bool) {
        let scale = min(unit, bounds.width / 36, bounds.height / 32)
        guard scale > 0 else { return }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: bounds.midX + (x - 14) * scale,
                    y: centerY + (isFlipped ? 1 : -1) * (y - 12) * scale)
        }
        let path = NSBezierPath()
        path.move(to: point(3, 5.5))
        path.line(to: point(8.3, 5.5))
        path.line(to: point(10.8, 1.4))
        path.line(to: point(17.2, 1.4))
        path.line(to: point(19.8, 5.5))
        path.line(to: point(25.2, 5.5))
        path.curve(to: point(26.8, 7.2), controlPoint1: point(26.4, 5.5), controlPoint2: point(26.8, 5.9))
        path.line(to: point(26.8, 20.9))
        path.curve(to: point(25.2, 22.5), controlPoint1: point(26.8, 22.1), controlPoint2: point(26.4, 22.5))
        path.line(to: point(2.8, 22.5))
        path.curve(to: point(1.2, 20.9), controlPoint1: point(1.6, 22.5), controlPoint2: point(1.2, 22.1))
        path.line(to: point(1.2, 7.2))
        path.curve(to: point(3, 5.5), controlPoint1: point(1.2, 5.9), controlPoint2: point(1.6, 5.5))
        path.close()
        let body = palette.cameraBody.usingColorSpace(.sRGB) ?? palette.ink
        let rgb = body.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        func relief(_ transform: (CGFloat) -> CGFloat) -> NSColor {
            func channel(_ c: CGFloat) -> CGFloat {
                let linear = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
                let adjusted = transform(linear)
                return adjusted <= 0.0031308 ? 12.92 * adjusted : 1.055 * pow(adjusted, 1 / 2.4) - 0.055
            }
            return NSColor(srgbRed: channel(rgb.redComponent), green: channel(rgb.greenComponent),
                           blue: channel(rgb.blueComponent), alpha: 1)
        }

        let light = relief { $0 + 0.22 * (1 - $0) }
        let edge = relief { 0.72 * $0 }
        path.lineJoinStyle = .round
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0.3 * scale, height: -0.8 * scale)
        shadow.shadowBlurRadius = 0.65 * scale
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.set()
        edge.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [light, rgb, edge], atLocations: [0, 0.30, 1], colorSpace: .sRGB)?
            .draw(in: path, angle: isFlipped ? 70 : -70)
        palette.cameraOutline.setStroke()
        path.lineWidth = 1.05 * scale
        path.stroke()

        let lens = point(14, 13.8)
        func circle(_ center: CGPoint, _ radius: CGFloat, _ color: NSColor) {
            let r = radius * scale
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x-r, y: center.y-r, width: 2*r, height: 2*r)).fill()
        }
        circle(lens, 5.0, NSColor(white: 0.84, alpha: 1))
        circle(lens, 4.05, NSColor(white: 0.18, alpha: 1))
        circle(lens, 2.75, NSColor(white: 0.31, alpha: 1))
        circle(point(12.9, 12.55), 0.85, NSColor(white: 0.91, alpha: 1))
    }
}
