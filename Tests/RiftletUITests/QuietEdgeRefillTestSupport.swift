import AppKit
@testable import RiftletUI

@MainActor func advanceQuietEdgeRefill(_ panel: RiftPanelController) {
    let now = ProcessInfo.processInfo.systemUptime + 10
    let outside = CGPoint(x: -1_000_000, y: -1_000_000)
    panel.evaluateRefillBoundary(now: now, pointer: outside)
    panel.evaluateRefillBoundary(now: now + 0.36, pointer: outside)
}
