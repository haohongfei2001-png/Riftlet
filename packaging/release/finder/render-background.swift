// Regenerate the checked-in installer artwork with Swift/AppKit, without opening a window.
// Usage: swift render-background.swift packaging/release/finder/Install.tiff
import AppKit
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.tiff.identifier as CFString, 2, nil)!
let width = 620
let height = 328
func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale,
        pixelsHigh: height * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    NSGradient(colors: [color(250, 252, 251), color(228, 242, 238)])!
        .draw(in: bounds, angle: -25)
    func label(_ value: String, _ x: CGFloat, _ top: CGFloat, _ size: CGFloat,
               _ weight: NSFont.Weight, _ ink: NSColor) {
        let text = NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: ink
        ])
        text.draw(at: NSPoint(x: x, y: CGFloat(height) - top - text.size().height))
    }
    let ink = color(18, 44, 39)
    label("Riftlet", 40, 24, 31, .bold, ink)
    label("Drag Riftlet to Applications.", 41, 71, 17, .medium, ink)
    label("将 Riftlet 拖入「应用程序」。", 41, 97, 14, .regular, color(52, 83, 75))

    // The arrow points from the real App icon to Finder's real Applications link.
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    let y = CGFloat(height - 202)
    arrow.move(to: NSPoint(x: 285, y: y))
    arrow.line(to: NSPoint(x: 335, y: y))
    arrow.move(to: NSPoint(x: 325, y: y - 10))
    arrow.line(to: NSPoint(x: 335, y: y))
    arrow.line(to: NSPoint(x: 325, y: y + 10))
    color(26, 112, 94).setStroke()
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let dpi = 72 * scale
    let properties: [CFString: Any] = [
        kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5,
            kCGImagePropertyTIFFXResolution: dpi, kCGImagePropertyTIFFYResolution: dpi,
            kCGImagePropertyTIFFResolutionUnit: 2]
    ]
    CGImageDestinationAddImage(destination, rep.cgImage!, properties as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { exit(1) }
