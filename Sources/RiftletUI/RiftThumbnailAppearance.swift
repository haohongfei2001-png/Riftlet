#if canImport(AppKit)
import AppKit
import QuartzCore

/// R2.1 decoration only. Never owns an input region, asset, or upload decision.
@MainActor enum RiftThumbnailAppearance {
    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    static func contactWidth(exposed: CGFloat, hidden: Bool) -> CGFloat {
        hidden ? min(2, max(0, (exposed - 12) / 6)) : 0
    }
    /// Open at the seam. Full perimeter only when no pixels are occluded.
    static func contour(_ rect: CGRect, radius: CGFloat, left: Bool, hidden: Bool) -> CGPath {
        let p = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return p }
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        if !hidden { return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil) }
        // Construct in a right-side coordinate system, then mirror geometry only.
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY + r), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        guard left else { return p }
        var t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0)
        return p.copy(using: &t)!
    }
}

@MainActor final class RiftThumbnailDecoration {
    let plane = CALayer(), moving = CALayer(), matte = CAShapeLayer()
    let checker = CAShapeLayer()
    let outer = CAShapeLayer(), inner = CAShapeLayer(), contact = CAGradientLayer(), lip = CALayer()
    let primary = CAShapeLayer(), tight = CAShapeLayer()
    init(parent: CALayer, imageClip: CALayer) {
        plane.masksToBounds = true
        parent.insertSublayer(plane, at: 0)
        plane.addSublayer(moving)
        moving.addSublayer(primary); moving.addSublayer(tight); moving.addSublayer(matte); moving.addSublayer(checker)
        // Pixel content and ornaments move together behind a stationary clipping plane.
        imageClip.removeFromSuperlayer(); moving.addSublayer(imageClip)
        moving.addSublayer(outer); moving.addSublayer(inner)
        plane.addSublayer(contact); parent.addSublayer(lip)
        for s in [outer, inner] { s.fillColor = nil }
    }
    func update(view: NSView, imageClip: CALayer, rect: CGRect, left: Bool, hidden: Bool,
                hovered: Bool, pressed: Bool) {
        let scale = max(1, view.window?.backingScaleFactor ?? 1), pixel = 1 / scale
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let outerWidth: CGFloat = contrast ? 1 : pixel
        let expanded = view.convertFromBacking(view.convertToBacking(rect).integral)
        let radius = min(2, rect.width / 2, rect.height / 2)
        let corners: CACornerMask = !hidden ? [.layerMinXMinYCorner,.layerMinXMaxYCorner,.layerMaxXMinYCorner,.layerMaxXMaxYCorner] : left ? [.layerMaxXMinYCorner,.layerMaxXMaxYCorner] : [.layerMinXMinYCorner,.layerMinXMaxYCorner]
        // Plane uses host coordinates; no input geometry is rounded or expanded.
        plane.frame = view.bounds
        plane.bounds = view.bounds
        let mask = CAShapeLayer()
        var visible = view.bounds
        if hidden {
            if left { visible.origin.x = rect.minX; visible.size.width = view.bounds.maxX - rect.minX }
            else { visible.size.width = rect.maxX - view.bounds.minX }
        }
        mask.path = CGPath(rect: visible, transform: nil); plane.mask = mask
        moving.frame = view.bounds; moving.bounds = view.bounds
        imageClip.frame = rect; imageClip.cornerRadius = radius; imageClip.maskedCorners = corners
        let shape = CAShapeLayer(); shape.path = RiftThumbnailAppearance.contour(expanded, radius: radius, left: left, hidden: hidden)
        let closed = CGMutablePath(); closed.addPath(shape.path!); closed.closeSubpath()
        matte.path = closed; matte.fillColor = RiftThumbnailAppearance.color(dark ? 0x30373E : 0xF1F3F4).cgColor
        for s in [primary, tight] {
            s.path = closed; s.fillColor = RiftThumbnailAppearance.color(dark ? 0x30373E : 0xF1F3F4).cgColor
            s.shadowPath = closed; s.shadowColor = RiftThumbnailAppearance.color(0x081017).cgColor
        }
        primary.shadowRadius = pressed ? 0.5 : 1.25; primary.shadowOffset = CGSize(width: 0, height: pressed ? -0.5 : -1)
        primary.shadowOpacity = Float(pressed ? 0.07 : dark ? 0.20 : 0.12)
        tight.shadowRadius = 0.25; tight.shadowOffset = CGSize(width: 0, height: -0.5); tight.shadowOpacity = 0.06
        let cells = CGMutablePath()
        for y in stride(from: rect.minY, to: rect.maxY, by: 4) {
            for x in stride(from: rect.minX, to: rect.maxX, by: 4) where (Int((x-rect.minX)/4) + Int((y-rect.minY)/4)) % 2 == 0 {
                cells.addRect(CGRect(x:x,y:y,width:min(4,rect.maxX-x),height:min(4,rect.maxY-y)))
            }
        }
        checker.path = cells; checker.fillColor = RiftThumbnailAppearance.color(dark ? 0xDDE5EB : 0x87919C, dark ? 11.0/255 : 18.0/255).cgColor
        let checkerMask = CAShapeLayer(); checkerMask.path = closed; checker.mask = checkerMask
        outer.path = RiftThumbnailAppearance.contour(expanded.insetBy(dx: outerWidth / 2, dy: outerWidth / 2), radius: radius, left: left, hidden: hidden)
        outer.isHidden = expanded.width <= outerWidth || expanded.height <= outerWidth
        inner.isHidden = expanded.width <= 2 * outerWidth + pixel || expanded.height <= 2 * outerWidth + pixel
        inner.path = RiftThumbnailAppearance.contour(expanded.insetBy(dx: outerWidth + pixel / 2, dy: outerWidth + pixel / 2), radius: max(0, radius - outerWidth), left: left, hidden: hidden)
        outer.lineWidth = outerWidth; inner.lineWidth = pixel
        outer.strokeColor = RiftThumbnailAppearance.color(dark ? 0x000000 : 0x111B21, (contrast ? (dark ? 0.80 : 0.72) : (dark ? 0.46 : 0.30) + (pressed ? 0.12 : hovered ? 0.09 : 0))).cgColor
        inner.strokeColor = RiftThumbnailAppearance.color(dark ? 0xEEF5FA : 0xFFFFFF, contrast ? 0.85 : (dark ? 0.32 : 0.64) + (hovered ? 0.06 : 0)).cgColor
        let width = RiftThumbnailAppearance.contactWidth(exposed: rect.width, hidden: hidden)
        contact.frame = CGRect(x: left ? rect.minX : rect.maxX - width, y: rect.minY, width: width, height: rect.height)
        contact.colors = [RiftThumbnailAppearance.color(0x00080E, (dark ? 0.22 : 0.16) + (pressed ? 0.06 : hovered ? 0.03 : 0)).cgColor, RiftThumbnailAppearance.color(0x00080E,0.035).cgColor, NSColor.clear.cgColor]
        contact.locations = [0,0.65,1]; contact.startPoint = CGPoint(x: left ? 0 : 1,y: 0.5); contact.endPoint = CGPoint(x: left ? 1 : 0,y: 0.5)
        var lipRect = CGRect(x: left ? rect.minX - pixel : rect.maxX, y: rect.minY, width: pixel, height: rect.height)
        if let window = view.window, let screen = window.screen {
            let screenRect = window.convertToScreen(view.convert(lipRect, to: nil))
            let clipped = screenRect.intersection(screen.frame)
            lipRect = clipped.isNull ? .zero : view.convert(window.convertFromScreen(clipped), from: nil)
        }
        lip.frame = lipRect
        lip.backgroundColor = RiftThumbnailAppearance.color(dark ? 0 : 0x0A141A, (dark ? 0.6 : 0.38) + (pressed ? 0.1 : 0)).cgColor
        lip.isHidden = !hidden
        for l in [plane,moving,matte,checker,outer,inner,contact,lip,primary,tight,imageClip] { l.contentsScale = scale }
    }
}
#endif
