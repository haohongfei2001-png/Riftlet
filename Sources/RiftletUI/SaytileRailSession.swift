import AppKit

/// The voice app owns the visual rail and its preference. Only process/window
/// identifiers and two presentation flags cross the login session; no media,
/// titles, coordinates, settings file or input rights are exchanged.
@MainActor final class SaytileRailSession {
    private static let request = Notification.Name("app.saytile.riftlet.rail.request.v1")
    private static let state = Notification.Name("app.saytile.riftlet.rail.state.v1")
    private let center = DistributedNotificationCenter.default()
    private let localPID = ProcessInfo.processInfo.processIdentifier
    private var token: NSObjectProtocol?
    private var voice: SaytilePanelGeometry.Window?
    private var trayNumber = 0
    private var confirmedBorder: Bool?
    private var confirmedAt: TimeInterval = 0
    private var lastPost: TimeInterval = -.infinity

    var anchor: SaytileTrayAnchor? {
        guard let voice, let confirmedBorder, ProcessInfo.processInfo.systemUptime - confirmedAt < 4 else { return nil }
        return SaytileTrayAnchor(outerFrame: voice.frame, framed: confirmedBorder)
    }

    func track(_ next: SaytilePanelGeometry.Window?, tray: NSWindow) {
        if token == nil {
            token = center.addObserver(forName: Self.state, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.receive(note) }
            }
        }
        if next?.pid != voice?.pid || next?.number != voice?.number || tray.windowNumber != trayNumber {
            detach()
        }
        voice = next
        trayNumber = tray.windowNumber
        if tray.isVisible { pulse() }
    }

    private func receive(_ note: Notification) {
        guard let voice, let data = note.userInfo,
              let border = Self.border(in: data, from: voice, to: localPID) else { return }
        confirmedBorder = border
        confirmedAt = ProcessInfo.processInfo.systemUptime
    }

    static func border(in data: [AnyHashable: Any], from voice: SaytilePanelGeometry.Window, to target: pid_t) -> Bool? {
        guard data["version"] as? Int == 1, data["targetPID"] as? Int32 == target,
              data["sourcePID"] as? Int32 == voice.pid, data["voiceWindow"] as? UInt32 == voice.number,
              let framed = data["framed"] as? Bool, let joined = data["joined"] as? Bool,
              framed || !joined else { return nil }
        return framed
    }

    func pulse() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPost >= 1.0 / 30, voice != nil, trayNumber > 0 else { return }
        lastPost = now
        post(join: true)
    }

    private func post(join: Bool) {
        guard let voice, trayNumber > 0 else { return }
        let data: [String: Any] = ["version": 1, "sourcePID": localPID, "voicePID": voice.pid,
            "voiceWindow": voice.number, "trayWindow": trayNumber, "join": join]
        center.postNotificationName(Self.request, object: nil, userInfo: data, deliverImmediately: true)
    }

    func detach() {
        post(join: false)
        voice = nil; confirmedBorder = nil; confirmedAt = 0; trayNumber = 0; lastPost = -.infinity
    }

    func stop() {
        detach()
        if let token { center.removeObserver(token); self.token = nil }
    }

    deinit { if let token { center.removeObserver(token) } }
}
