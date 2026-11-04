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
        /// Beginning of this uninterrupted observed native route epoch.
        let observedUptime: TimeInterval
    }
    struct Snapshot: Sendable {
        fileprivate let route: Route?
        fileprivate let targets: [(TargetLease, TimeInterval)]
        /// Last usable ChatGPT target before this press, even if another app
        /// now owns focus. The caller still checks Chrome's exact native route.
        func lastTarget(eventUptime: TimeInterval) -> TargetLease? {
            guard let route else { return nil }
            return target(session: route.session, window: route.window, tab: route.tab, eventUptime: eventUptime)
        }
        func target(session: String, window: String, tab: String, eventUptime: TimeInterval) -> TargetLease? {
            guard eventUptime.isFinite, eventUptime >= 0, let route, route.observedUptime < eventUptime,
                  route.session == session, route.window == window, route.tab == tab else { return nil }
            return targets.last { $0.0.sessionID == session && $0.0.windowID == window && $0.0.tabID == tab
                && $0.1 < eventUptime }?.0
        }
    }
    private let lock = NSLock()
    private var targets: [(TargetLease, TimeInterval)] = []
    private var route: Route?
    func recordRoute(session: String, window: String, tab: String, uptime: TimeInterval) {
        guard uptime.isFinite, uptime >= 0 else { return }
        lock.lock(); defer { lock.unlock() }
        // A same-route poll that finishes after the physical mouse event must
        // not erase the earlier observation that already preceded that event.
        if let route, route.session == session && route.window == window && route.tab == tab { return }
        // A→B→A is a new observation epoch. Returning to an old tab cannot
        // revive a target that was captured before the intervening selection.
        targets.removeAll(keepingCapacity: true)
        route = Route(session: session, window: window, tab: tab, observedUptime: uptime)
    }
    func record(_ target: TargetLease, uptime: TimeInterval) {
        guard target.clickBindingID == nil, uptime.isFinite, uptime >= 0 else { return }
        lock.lock(); defer { lock.unlock() }
        guard let route, target.sessionID == route.session, target.windowID == route.window,
              target.tabID == route.tab, uptime >= route.observedUptime else { return }
        targets.append((target, uptime))
        if targets.count > 64 { targets.removeFirst(targets.count - 64) }
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(route: route, targets: targets)
    }
}

/// Native event time and uptime share a clock. No page performance timestamp is
/// compared with either. This bounds replay of an old mouse event while allowing
/// an old, continuously monitored target to be pinned by a fresh real press.
enum NativePressTiming {
    static let maximumEventAge: TimeInterval = 0.75
    static func accepts(eventUptime: TimeInterval, startedUptime: TimeInterval) -> Bool {
        eventUptime.isFinite && startedUptime.isFinite && eventUptime >= 0
            && eventUptime <= startedUptime && startedUptime - eventUptime <= maximumEventAge
    }
}
