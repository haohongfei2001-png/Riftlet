import AppKit

/// Schematic display preview in Settings. Geometry is expressed in display points.
@MainActor
final class SettingsDesktopPreview: NSView {
    var showsTray = true
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
        let sideWidth = showsTray ? w / 8 : w * 0.065
        let total = min(4, visible + (includesEntry && showsTray ? 1 : 0))
        let sideHeight = showsTray ? sideWidth * (total > 2 ? 212.0/246 : 115.0/246) : sideWidth * 1.75
        let x = placement < 3 ? 9 : w - sideWidth - 9
        let y: CGFloat
        switch placement % 3 { case 0: y=8; case 2: y=h-sideHeight-8; default:y=(h-sideHeight)/2 }
        func fill(_ r: CGRect, radius: CGFloat, color: NSColor) {
            color.setFill(); NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius).fill()
        }
        let tones:[NSColor] = [rgb(0.86,0.74,0.50),rgb(0.33,0.68,0.62),rgb(0.54,0.57,0.80),rgb(0.76,0.68,0.82)]
        if showsTray {
            let shell=CGRect(x:x,y:y,width:sideWidth,height:sideHeight)
            fill(shell,radius:5,color:NSColor(srgbRed:1,green:1,blue:1,alpha:0.75))
            fill(shell.insetBy(dx:1,dy:1),radius:4,color:NSColor(hue:hue,saturation:saturation,brightness:0.96,alpha:0.65))
            let gap=sideWidth*0.025, cell=(sideWidth-3*gap)/2, ch=cell*0.70
            for i in 0..<total {
                let r=CGRect(x:x+gap+CGFloat(i%2)*(cell+gap),y:y+sideWidth*0.065+CGFloat(i/2)*(ch+gap*2),width:cell,height:ch)
                if includesEntry && i == min(visible,3) && visible < 4 {
                    fill(r,radius:2,color:.white.withAlphaComponent(0.72))
                    let sym=NSImage(systemSymbolName:"camera",accessibilityDescription:nil)
                    sym?.draw(in:r.insetBy(dx:cell*0.22,dy:ch*0.15))
                } else { drawThumbnail(r, tones[i], index:i) }
            }
        } else {
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
