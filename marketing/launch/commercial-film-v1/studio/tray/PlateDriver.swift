// This harness is compiled in the same temporary source as the tagged private
// TrayButton. It only draws the key into a transparent local bitmap.
@main
struct PlateDriver {
    @MainActor static func main() {
        let padded = CGSize(width: 127.5, height: 94)
        let scale: CGFloat = 4
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let canvas = CGContext(data: nil, width: Int(padded.width * scale),
                               height: Int(padded.height * scale), bitsPerComponent: 8,
                               bytesPerRow: 0, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        canvas.scaleBy(x: scale, y: scale)
        let slot = NSRect(x: 0, y: 0, width: 113.5, height: 80)
        let look = NSAppearance(named: .aqua)!
        look.performAsCurrentDrawingAppearance {
            let button = TrayButton(frame: slot)
            button.appearance = look
            button.assign(.expand, title: "展开截图方式", symbol: "camera")
            let palette = RiftTrayGlassPalette(colors: .violetGlass, appearance: look,
                                               clearGlass: true)
            button.apply(palette, unit: 1)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            // The button is flipped. Its ordinary draw() including the original
            // camera Bezier is run literally; the CALayer shadow is composited in Python.
            if button.isFlipped {
                canvas.translateBy(x: 7, y: 87)
                canvas.scaleBy(x: 1, y: -1)
            } else {
                canvas.translateBy(x: 7, y: 7)
            }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: button.isFlipped)
            button.draw(slot)
        }
        let data = NSBitmapImageRep(cgImage: canvas.makeImage()!).representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
