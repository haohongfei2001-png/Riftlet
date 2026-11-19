import AppKit
import CoreGraphics
import Foundation

// This accessory presents only the two original campaign plates. The separate
// paper panel is the physical backdrop behind the released app's glass.
let args = CommandLine.arguments
guard args.count == 4 else { exit(64) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.screens.first else { exit(2) }
let mainFrame = screen.frame
let crop = CGRect(x: mainFrame.minX + mainFrame.width - 326,
                  y: mainFrame.height / 2 - 100, width: 326, height: 304)
let paper = NSPanel(contentRect: CGRect(x: crop.minX, y: mainFrame.maxY - crop.maxY,
                                        width: crop.width, height: crop.height),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
paper.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 2)
paper.backgroundColor = NSColor(srgbRed: 252/255, green: 251/255, blue: 248/255, alpha: 1)
paper.hasShadow = false
paper.isOpaque = true
paper.ignoresMouseEvents = true
paper.hidesOnDeactivate = false
paper.collectionBehavior = [.canJoinAllSpaces, .stationary]
paper.orderFrontRegardless()

var panels = [NSPanel]()
var ids = [String: Int]()
for (index, name) in ["low", "high"].enumerated() {
    guard let plate = NSImage(contentsOfFile: args[index + 1]) else { exit(3) }
    let window = NSPanel(contentRect: CGRect(x: mainFrame.midX - 300, y: mainFrame.midY - 200,
                                              width: 600, height: 400),
                         styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    window.title = index == 0 ? "Meridian Inlet  —  Low water" : "Meridian Inlet  —  High water"
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.preventsApplicationTerminationWhenModal = false
    window.ignoresMouseEvents = true
    window.hasShadow = false
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    let image = NSImageView(image: plate)
    image.imageScaling = .scaleAxesIndependently
    window.contentView = image
    window.orderBack(nil)
    window.displayIfNeeded()
    panels.append(window)
    ids[name] = window.windowNumber
}
ids["paper"] = paper.windowNumber
let meta: [String: Any] = ["windows": ids, "crop": [crop.minX, crop.minY, crop.width, crop.height],
                          "scale": screen.backingScaleFactor, "owner": getpid()]
try JSONSerialization.data(withJSONObject: meta).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
withExtendedLifetime((paper, panels)) { app.run() }
