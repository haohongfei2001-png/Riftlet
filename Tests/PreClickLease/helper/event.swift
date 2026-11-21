import AppKit
// The public AppKit constructor takes a native uptime timestamp. This is a
// controlled unposted event; the timestamp comes from macOS, not the document.
let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
    eventNumber: 1, clickCount: 1, pressure: 1)
guard let native = event, native.timestamp > 0 else { exit(1) }
print(UInt64(native.timestamp * 1_000_000_000))
