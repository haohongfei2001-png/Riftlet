import Foundation
import RiftletCore

/// Lightweight route and page-receipt observations; neither is click authority.
/// Freeze before any press-time AE, then require that same route/page to pin.
/// A later active tab must never be chosen from an older multi-tab cache.
final class ObservedClickRoutes: @unchecked Sendable {
    struct Route: Equatable, Sendable {
        let session: String
        let window: String
        let tab: String
        let observedUptime: TimeInterval
    }
    struct Snapshot: Sendable {
        fileprivate let route: Route?
        fileprivate let targets: [(TargetLease, TimeInterval)]
        func target(session: String, window: String, tab: String, eventUptime: TimeInterval) -> TargetLease? {
            guard eventUptime.isFinite, let route, route.observedUptime <= eventUptime,
                  route.session == session, route.window == window, route.tab == tab else { return nil }
            return targets.last { $0.0.sessionID == session && $0.0.windowID == window && $0.0.tabID == tab
                && $0.1 <= eventUptime }?.0
        }
    }
    private let lock = NSLock()
    private var targets: [(TargetLease, TimeInterval)] = []
    private var route: Route?
    func recordRoute(session: String, window: String, tab: String, uptime: TimeInterval) {
        guard uptime.isFinite, uptime >= 0 else { return }
        lock.lock(); defer { lock.unlock() }
        route = Route(session: session, window: window, tab: tab, observedUptime: uptime)
    }
    func record(_ target: TargetLease, uptime: TimeInterval) {
        guard target.clickBindingID == nil, uptime.isFinite, uptime >= 0 else { return }
        lock.lock(); defer { lock.unlock() }
        targets.append((target, uptime))
        if targets.count > 64 { targets.removeFirst(targets.count - 64) }
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(route: route, targets: targets)
    }
}
