import AppKit
import CryptoKit
import RiftletCore
@testable import RiftletUI

private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

private func verify(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(message) }
}

private func sha256(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

@MainActor private final class Receiver: NSView {
    var accepting = true
    var entries = 0
    var copies: [(url: URL, hash: String)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        entries += 1
        return draggingUpdated(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepting && sender.draggingSourceOperationMask == .copy ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard accepting, sender.draggingSource is RiftFileDrag,
              let files = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL], files.count == 1,
              let data = try? Data(contentsOf: files[0]) else { return false }
        copies.append((files[0], sha256(data)))
        return true
    }
}

/// AppKit tracks the drag in a nested event loop. A separate worker feeds only
/// the corridor between this process's two known panels. Any foreign covering
/// window stops the attempt before the next input.
private struct ScopedPointer: Sendable {
    let pid: pid_t
    let displayTop: CGFloat
    let sourceWindow: Int
    let start: CGPoint
    let finish: CGPoint

    func run(cancel: Bool) throws {
        try post(.mouseMoved, at: start)
        Thread.sleep(forTimeInterval: 0.05)
        try post(.leftMouseDown, at: start)
        var released = false
        defer {
            if !released {
                if (try? post(.leftMouseUp, at: start)) == nil {
                    event(.leftMouseUp, at: start)?.postToPid(pid)
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.10)
        try post(.leftMouseDragged, at: CGPoint(x: start.x - 7, y: start.y))
        Thread.sleep(forTimeInterval: 0.14)
        for step in 1...10 {
            let share = CGFloat(step) / 10
            try post(.leftMouseDragged, at: CGPoint(x: start.x + (finish.x - start.x) * share,
                                                    y: start.y + (finish.y - start.y) * share))
            Thread.sleep(forTimeInterval: 0.045)
        }
        if cancel {
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.postToPid(pid)
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.postToPid(pid)
            Thread.sleep(forTimeInterval: 0.12)
        }
        try post(.leftMouseUp, at: finish)
        released = true
    }

    private func event(_ kind: CGEventType, at point: CGPoint) -> CGEvent? {
        let position = CGPoint(x: point.x, y: displayTop - point.y)
        let event = CGEvent(mouseEventSource: nil, mouseType: kind, mouseCursorPosition: position, mouseButton: .left)
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        event?.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(sourceWindow))
        event?.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(sourceWindow))
        return event
    }

    private func post(_ kind: CGEventType, at point: CGPoint) throws {
        guard let event = event(kind, at: point),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] else { throw Failure("WindowServer unavailable") }
        let covering = windows.first { info in
            guard (info[kCGWindowAlpha as String] as? Double ?? 0) > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"]
            else { return false }
            return CGRect(x: x, y: y, width: w, height: h).contains(event.location)
        }
        guard (covering?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid else {
            throw Failure("An unrelated window covers the test position")
        }
        event.post(tap: .cghidEventTap)
    }
}

@main @MainActor private struct DragAcceptance {
    static func main() async {
        do { try await run() }
        catch { print("FAIL \(error)"); exit(1) }
    }

    private static func pump(_ duration: TimeInterval) {
        let end = Date().addingTimeInterval(duration)
        repeat {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.004),
                                           inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        } while Date() < end
    }

    private static func waitForDriver(_ completion: DispatchSemaphore) {
        while completion.wait(timeout: .now()) != .success { pump(0.04) }
    }

    private static func run() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        guard let display = NSScreen.screens.first else { throw Failure("No interactive display") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageID = UUID(), url = root.appendingPathComponent("\(imageID).png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 60, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let teal = NSColor(deviceRed: 0, green: 0.7, blue: 0.6, alpha: 1)
        let orange = NSColor(deviceRed: 1, green: 0.6, blue: 0.2, alpha: 1)
        for x in 0..<100 { for y in 0..<60 { bitmap.setColor(x < 50 ? teal : orange, atX: x, y: y) } }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure("Missing test PNG") }
        try png.write(to: url)
        let hash = sha256(png)
        let image = ImportedAsset(id: imageID, sourceKey: "native-drag-qa", fileName: url.lastPathComponent,
            sha256: hash, byteCount: Int64(png.count), pixelWidth: 100, pixelHeight: 60, mediaType: "image/png", origin: .synthetic)
        let active = AssetRecord(image: image, sequence: 1, status: .pending, visibility: .visible,
                                 visibilityRevision: 7, visibilityReason: .capture)
        let history = AssetRecord(image: image, sequence: 1, status: .unknown, visibility: .swallowed,
                                  visibilityRevision: 8, visibilityReason: .traySelection)
        var frozen: [UUID] = [], cancelled: [UUID] = [], selected: [UUID] = [], accepted: [(UUID, Int64)] = []
        var config = RiftConfiguration()
        config.desktopForm = .tray
        config.placement = .rightMiddle
        config.outerInset = 48
        let tray = RiftPanelController(mediaDirectory: root, configuration: config, reduceMotionOverride: { true },
            onPress: { id, _ in frozen.append(id) }, onCancelledPress: { cancelled.append($0) }, onSelect: { selected.append($0) })
        defer { tray.close() }
        tray.onFileDropAccepted = { accepted.append(($0, $1)) }
        tray.setTrayCapture(enabled: true, defaultMode: .window)
        tray.render([active], timeline: [active], hasOlder: false)
        pump(0.16)
        guard let first = tray.diagnosticSnapshot.rows.first else { throw Failure("Missing source row") }
        let receiver = Receiver(frame: .zero)
        let target = NSPanel(contentRect: CGRect(x: first.frame.minX - 260, y: first.frame.midY - 56, width: 270, height: 112),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        target.isReleasedWhenClosed = false
        target.contentView = receiver
        target.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        target.orderFrontRegardless()
        defer { target.close() }
        let originalCursor = CGEvent(source: nil)?.location
        defer { if let originalCursor { CGWarpMouseCursorPosition(originalCursor) } }

        for action in ["reject", "escape", "copy", "history-copy"] {
            if action == "history-copy" {
                tray.render([], timeline: [history], hasOlder: false)
                tray.showRecentHistory(true)
                pump(0.04)
            }
            guard let row = tray.diagnosticSnapshot.rows.first(where: { $0.assetID == imageID }),
                  let source = NSApp.window(withWindowNumber: row.imageInputWindowNumber), source.isVisible,
                  source !== target, target.contentView === receiver, target.isVisible else { throw Failure("Unverified test panels") }
            receiver.accepting = action != "reject"
            let entries = receiver.entries, copies = receiver.copies.count, acceptedBefore = accepted.count
            let pointer = ScopedPointer(pid: ProcessInfo.processInfo.processIdentifier, displayTop: display.frame.maxY,
                                        sourceWindow: source.windowNumber,
                                        start: CGPoint(x: row.imageInputFrame.midX, y: row.imageInputFrame.midY),
                                        finish: CGPoint(x: target.frame.midX, y: target.frame.midY))
            let completed = DispatchSemaphore(value: 0)
            let worker = Task.detached {
                defer { completed.signal() }
                try pointer.run(cancel: action == "escape")
            }
            waitForDriver(completed)
            try await worker.value
            pump(0.24)
            let expected = action == "copy" || action == "history-copy" ? 1 : 0
            try verify(!tray.isDraggingFile && receiver.entries == entries + 1, "Unfinished or missing destination entry")
            try verify(receiver.copies.count == copies + expected, "Wrong number of destination copies")
            try verify(accepted.count == acceptedBefore + (action == "copy" ? 1 : 0), "Wrong active-tray callback count")
            try verify(selected.isEmpty && (try Data(contentsOf: url)) == png, "Unexpected click or changed original")
            print("PASS \(action) entries=1 receiverCopies=\(expected) activeCallbacks=\(accepted.count - acceptedBefore)")
        }
        try verify(receiver.copies.allSatisfy { $0.url.standardizedFileURL == url.standardizedFileURL && $0.hash == hash },
                   "Receiver read different bytes or a temporary copy")
        try verify(frozen == Array(repeating: imageID, count: 4) && cancelled == frozen, "Incorrect press/cancel boundary")
        try verify(accepted.count == 1 && accepted[0].0 == imageID && accepted[0].1 == 7, "Wrong asset or revision")
        print("PASS originalSHA256=\(hash) originalFileURLs=2 frozenMouseDowns=4 suppressedClicks=4 clickDispatches=0")
    }
}
