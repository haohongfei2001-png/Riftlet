import AppKit
import CoreGraphics
import Foundation
import QuartzCore

// This source window is independent of the browser destination. Only this
// process's own WindowServer surface can be passed to screencapture.
let app = NSApplication.shared
if app.activationPolicy() != .prohibited { app.setActivationPolicy(.prohibited) }
guard app.activationPolicy() == .prohibited else { print("NONACTIVATING_POLICY_UNAVAILABLE"); exit(77) }
guard CGPreflightScreenCaptureAccess() else { print("SCREEN_CAPTURE_ACCESS_UNAVAILABLE"); exit(77) }
guard CommandLine.arguments.count == 2 else { exit(64) }
let output = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard output.lastPathComponent == "Neutral-1.png",
      !FileManager.default.fileExists(atPath: output.path),
      let screen = NSScreen.main else { exit(64) }

app.finishLaunching()
let size = CGSize(width: 160, height: 96)
let panel = NSPanel(contentRect: NSRect(origin: screen.visibleFrame.origin, size: size),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isReleasedWhenClosed = false
panel.hidesOnDeactivate = false
panel.ignoresMouseEvents = true
panel.hasShadow = false
panel.isOpaque = true
panel.backgroundColor = NSColor(srgbRed: 0.10, green: 0.35, blue: 0.80, alpha: 1)
let swatch = NSView(frame: NSRect(x: 80, y: 0, width: 80, height: 96))
swatch.wantsLayer = true
swatch.layer?.backgroundColor = NSColor(srgbRed: 0.90, green: 0.40, blue: 0.12, alpha: 1).cgColor
panel.contentView?.addSubview(swatch)
panel.orderFrontRegardless()
panel.display()
CATransaction.flush()
defer { panel.orderOut(nil) }

guard let number = CGWindowID(exactly: panel.windowNumber), number != 0 else {
    print("SOURCE_WINDOW_IDENTITY_UNAVAILABLE"); exit(2)
}
func sourceIsOwned() -> Bool {
    guard panel.isVisible, panel.windowNumber == Int(number) else { return false }
    guard let entries = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] else { return false }
    let own = entries.filter {
        ($0[kCGWindowNumber as String] as? UInt32) == number && ($0[kCGWindowOwnerPID as String] as? Int32) == getpid()
    }
    guard own.count == 1, let bounds = own[0][kCGWindowBounds as String] as? NSDictionary,
          let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
    return frame.size == size
}
let deadline = ProcessInfo.processInfo.systemUptime + 3
while !sourceIsOwned() && ProcessInfo.processInfo.systemUptime < deadline {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
}
guard sourceIsOwned() else { print("SOURCE_WINDOW_IDENTITY_UNAVAILABLE"); exit(2) }
let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x", "-t", "png", "-o", "-l" + String(number), output.path]
try capture.run()
capture.waitUntilExit()
guard capture.terminationStatus == 0, sourceIsOwned(),
      let data = try? Data(contentsOf: output), let bitmap = NSBitmapImageRep(data: data),
      bitmap.pixelsWide >= 160, bitmap.pixelsHigh >= 96, bitmap.pixelsWide * 96 == bitmap.pixelsHigh * 160,
      let blue = bitmap.colorAt(x: bitmap.pixelsWide / 4, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB),
      let orange = bitmap.colorAt(x: bitmap.pixelsWide * 3 / 4, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB),
      blue.alphaComponent > 0.95, orange.alphaComponent > 0.95,
      blue.blueComponent - blue.redComponent > 0.4, orange.redComponent - orange.blueComponent > 0.4
else { print("SOURCE_PIXELS_UNVERIFIED"); exit(3) }
print("OWNED_WINDOW_TWO_SWATCHES_VERIFIED")
