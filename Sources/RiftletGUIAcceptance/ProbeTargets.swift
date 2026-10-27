import AppKit
import RiftletUI

/// Markers are drawn by the underlying probe, never by an input overlay.
struct ProbeTarget {
    let name: String
    let screenPoint: CGPoint
    let radius: CGFloat

    func contains(_ point: CGPoint) -> Bool {
        hypot(point.x - screenPoint.x, point.y - screenPoint.y) <= radius
    }

    static func make(snapshot: RiftDiagnosticSnapshot, screen: CGRect) -> [ProbeTarget] {
        guard !snapshot.isTransitioning, let row = snapshot.rows.first else { return [] }
        var targets = [
            ProbeTarget(name: "IMAGE 图片", screenPoint: CGPoint(x: row.imageClipFrame.midX, y: row.imageClipFrame.midY), radius: 5),
            ProbeTarget(name: "NUMBER 数字", screenPoint: CGPoint(x: row.numberFrame.midX, y: row.numberFrame.midY), radius: 3),
            ProbeTarget(name: "CLEAR 透明角", screenPoint: CGPoint(x: row.frame.minX + 1.5, y: row.frame.minY + 2), radius: 1.25)
        ]
        if screen.maxX - row.frame.maxX >= 4 {
            targets.append(ProbeTarget(name: "OUTER 外侧", screenPoint: CGPoint(x: (screen.maxX + row.frame.maxX) / 2, y: row.frame.midY), radius: 1.5))
        }
        if snapshot.rows.count > 1 {
            let second = snapshot.rows[1]
            targets.append(ProbeTarget(name: "HOLD 按住第二张", screenPoint: CGPoint(x: second.imageClipFrame.midX, y: second.imageClipFrame.midY), radius: 5))
            let gapY = (row.frame.minY + second.frame.maxY) / 2
            if row.frame.minY - second.frame.maxY >= 4 {
                targets.append(ProbeTarget(name: "GAP 间隙", screenPoint: CGPoint(x: row.imageClipFrame.midX, y: gapY), radius: 1.5))
                targets.append(ProbeTarget(name: "LINE 细线", screenPoint: CGPoint(x: snapshot.lineFrame.midX, y: gapY), radius: 0.3))
            }
        }
        return targets.filter { screen.contains($0.screenPoint) }
    }
}
