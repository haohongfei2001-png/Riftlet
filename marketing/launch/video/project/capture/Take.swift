import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
func saveJSON(_ object: Any, _ path: String) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: path), options: .atomic)
}
typealias Window = [String: Any]
func owner(_ window: Window) -> Int { (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue ?? -1 }
func number(_ window: Window) -> Int { (window[kCGWindowNumber as String] as? NSNumber)?.intValue ?? -1 }
func bounds(_ window: Window) -> CGRect {
    guard let raw = window[kCGWindowBounds as String] as? [String: Any] else { return .null }
    return CGRect(dictionaryRepresentation: raw as CFDictionary) ?? .null
}
func property(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
    return value
}
func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute]
        .compactMap { property(element, $0 as String) as? String }.filter { !$0.isEmpty }
}
func control(_ args: [String]) throws {
    guard args.count == 3, let pid = Int32(args[1]) else { throw Failure("control PID exact-label-prefix | escape | list") }
    guard AXIsProcessTrusted() else { throw Failure("macOS Accessibility access unavailable") }
    let app = AXUIElementCreateApplication(pid)
    let wantsMouse = args[2].hasPrefix("mouse:")
    let wantsEscape = args[2] == "escape"
    let target = wantsMouse ? String(args[2].dropFirst(6)) : (wantsEscape ? "默认截图" : args[2])
    var pending = (property(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    var visited = Set<CFHashCode>(), found = [AXUIElement](), seen = [[String]]()
    while let node = pending.popLast() {
        guard visited.insert(CFHash(node)).inserted, visited.count <= 2500 else { continue }
        let names = labels(node)
        let role = property(node, kAXRoleAttribute as String) as? String ?? ""
        if role == (kAXButtonRole as String), !names.isEmpty {
            seen.append(names)
            if names.contains(where: { $0.hasPrefix(target) }) { found.append(node) }
        }
        pending.append(contentsOf: (property(node, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [])
    }
    if args[2] == "list" {
        print(String(decoding: try JSONSerialization.data(withJSONObject: seen), as: UTF8.self))
        return
    }
    guard found.count == 1 else { throw Failure("expected one matching review button; found \(found.count) among \(seen)") }
    if wantsMouse || wantsEscape {
        let node = found[0]
        guard let position = property(node, kAXPositionAttribute as String),
              let size = property(node, kAXSizeAttribute as String) else { throw Failure("missing AX geometry") }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { throw Failure("invalid AX geometry") }
        let targetRect = CGRect(origin: origin, size: dimensions)
        let point = CGPoint(x: targetRect.midX, y: targetRect.midY)
        let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [Window] ?? []
        let hit = all.filter { owner($0) == Int(pid) && bounds($0).contains(point) }
        guard let window = hit.first, let primary = NSScreen.screens.first else { throw Failure("no owned window at AX button") }
        let id = number(window), rect = bounds(window)
        guard id > 0 else { throw Failure("empty receiver") }
        let local = CGPoint(x: point.x-rect.minX, y: rect.maxY-point.y)
        let receipt: [String:Any] = ["control": target, "screenPoint": [point.x,point.y],
            "accessibilityBounds": [targetRect.minX,targetRect.minY,targetRect.width,targetRect.height],
            "hitBounds": [rect.minX,rect.minY,rect.width,rect.height], "stageHeight": primary.frame.height,
            "windowsAtPointOwnedByReview": hit.count]
        for down in [true,false] {
            let event: NSEvent?
            if wantsEscape {
                event = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: local, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: id, context: nil,
                    characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)
            } else {
                event = NSEvent.mouseEvent(with: down ? .leftMouseDown : .leftMouseUp, location: local,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: id,
                    context: nil, eventNumber: 18, clickCount: 1, pressure: down ? 1 : 0)
            }
            guard let cg = event?.cgEvent else { throw Failure("AppKit event creation failed") }
            cg.location = point
            cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(id))
            cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(id))
            cg.postToPid(pid)
            if down { Thread.sleep(forTimeInterval: wantsEscape ? 0.06 : 0.27) }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: receipt), as: UTF8.self))
        return
    }
    let status = AXUIElementPerformAction(found[0], kAXPressAction as CFString)
    guard status == .success else { throw Failure("AXPress status \(status.rawValue)") }
    print("AXPress " + labels(found[0]).joined(separator: " / "))
}
struct StageInfo: Decodable { let windows: [String: Int]; let crop: [CGFloat]; let owner: Int }
func capture(_ args: [String]) throws {
    guard args.count == 5, let productPID = Int(args[1]), let duration = Double(args[4]),
          duration > 0, duration <= 90, CGPreflightScreenCaptureAccess() else { throw Failure("record PID stage.json times.json seconds or Screen Recording permission unavailable") }
    let stage = try JSONDecoder().decode(StageInfo.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
    guard let backdropID = stage.windows["paper"], stage.crop.count == 4 else { throw Failure("invalid stage") }
    let crop = CGRect(x: stage.crop[0], y: stage.crop[1], width: stage.crop[2], height: stage.crop[3])
    let start = ProcessInfo.processInfo.systemUptime
    let fps = 30.0
    let displayScale = NSScreen.screens.first?.backingScaleFactor ?? 1
    let width = Int(crop.width * displayScale), height = Int(crop.height * displayScale)
    let color = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: color,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
          let data = context.data else { throw Failure("frame storage") }
    var times = [Double]()
    var firstIDs = [Int]()
    let frameCount = Int(duration * fps)
    try saveJSON(["start": start, "width": width, "height": height, "fps": fps], args[3] + ".start")
    for index in 0..<frameCount {
        let deadline = start + Double(index) / fps
        let delay = deadline - ProcessInfo.processInfo.systemUptime
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        try autoreleasepool {
            let listed = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [Window] ?? []
            let allowed = listed.filter { window in
                if number(window) == backdropID, owner(window) == stage.owner { return true }
                let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
                return owner(window) == productPID && (1...20).contains(layer) && bounds(window).intersects(crop)
            }
            guard allowed.contains(where: { number($0) == backdropID }), let ids = CFArrayCreateMutable(nil,0,nil) else { throw Failure("paper window unavailable") }
            for item in allowed {
                guard let id = UnsafeRawPointer(bitPattern: number(item)) else { throw Failure("invalid permitted window") }
                CFArrayAppendValue(ids, id)
            }
            guard let frame = CGImage(windowListFromArrayScreenBounds: crop, windowArray: ids, imageOption: [.boundsIgnoreFraming, .bestResolution]),
                  frame.width == width, frame.height == height else { throw Failure("owned window region frame unavailable or scale changed") }
            if index == 0 { firstIDs = allowed.map(number) }
            context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
            times.append(ProcessInfo.processInfo.systemUptime - start)
            FileHandle.standardOutput.write(Data(bytesNoCopy: data, count: width * height * 4, deallocator: .none))
        }
    }
    try saveJSON(["start": start, "times": times, "width": width, "height": height,
                  "fps": fps, "crop": stage.crop, "firstWindowCount": firstIDs.count,
                  "pixelScope": "exact PID floating layers plus owned paper; screen pointer excluded"], args[3])
}
do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let mode = args.first else { throw Failure("missing mode") }
    switch mode {
    case "control": try control(args)
    case "record": try capture(args)
    default: throw Failure("unknown mode")
    }
} catch {
    FileHandle.standardError.write(Data(("Take: " + String(describing: error) + "\n").utf8))
    exit(1)
}
