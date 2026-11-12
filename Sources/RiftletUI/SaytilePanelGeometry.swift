import AppKit

/// WindowServer exposes window bounds in desktop points with a top-left origin.
/// The voice window bounds are the rail slot, not necessarily the card. Query
/// only geometry: no AX events, screen capture or access to its preferences.
enum SaytilePanelGeometry {
    struct Window: Equatable {
        let pid: pid_t
        let number: UInt32
        let frame: CGRect
    }

    static func companionID(for localID: String?) -> String? {
        switch localID {
        case "com.riftlet.app": return "app.saytile.mac"
        case "com.riftlet.local-tray-preview": return "app.saytile.local-rail-preview"
        default: return nil
        }
    }

    @MainActor static func visibleWindow(on target: NSScreen) -> Window? {
        guard let bundleID = companionID(for: Bundle.main.bundleIdentifier) else { return nil }
        let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }.map(\.processIdentifier))
        let screens = NSScreen.screens
        guard !owners.isEmpty, let primary = screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        let frames = screens.map(\.frame)
        return voiceWindow(in: windows, owners: owners, primaryTop: primary.frame.maxY,
                          displays: frames, target: target.frame)
    }

    static func voiceWindow(in windows: [[String: Any]], owners: Set<pid_t>, primaryTop: CGFloat,
                           displays: [CGRect], target: CGRect) -> Window? {
        for info in windows {
            guard let id = info[kCGWindowNumber as String] as? UInt32, id != 0,
                  let pid = info[kCGWindowOwnerPID as String] as? NSNumber, owners.contains(pid.int32Value),
                  info[kCGWindowLayer as String] as? Int == NSWindow.Level.floating.rawValue,
                  (info[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartz = CGRect(dictionaryRepresentation: bounds),
                  quartz.width > 42, quartz.height > 42 else { continue }
            // Window names may be withheld by macOS. The other Saytile floating
            // panel is the 42-point launcher; settings and archive are at normal level.
            if let title = info[kCGWindowName as String] as? String, !title.isEmpty,
               title != "Saytile · 此刻" { continue }
            let frame = CGRect(x: quartz.minX, y: primaryTop - quartz.maxY,
                               width: quartz.width, height: quartz.height)
            func area(on display: CGRect) -> CGFloat {
                let r = display.intersection(frame)
                return r.isEmpty ? 0 : r.width * r.height
            }
            guard area(on: target) > 0, displays.max(by: { area(on: $0) < area(on: $1) }) == target else { continue }
            return Window(pid: pid.int32Value, number: id, frame: frame)
        }
        return nil
    }
}
