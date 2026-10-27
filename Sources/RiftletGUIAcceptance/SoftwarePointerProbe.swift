import AppKit

/// Acceptance-only arithmetic and observations. This never grants input authority
/// to a product operation, and never identifies untagged events as human input.
enum SoftwarePointerProbe {
    static let names = ["IMAGE", "NUMBER", "CLEAR", "GAP"]

    static func quartzPoint(_ point: CGPoint, primaryFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryFrame.maxY - point.y)
    }

    /// Reposition only the existing helper control/probe window. Use actual
    /// AppKit screen frames; a portrait or negative-origin display needs no scale.
    static func probeControlFrame(current: CGRect, visibleScreen: CGRect) -> CGRect {
        let width = min(current.width, visibleScreen.width)
        let height = min(current.height, visibleScreen.height)
        return CGRect(x: visibleScreen.maxX - width,
                      y: min(max(current.minY, visibleScreen.minY), visibleScreen.maxY - height),
                      width: width, height: height)
    }

    static func selfCheck() throws {
        enum Failure: Error { case geometry, verdict }
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        guard quartzPoint(CGPoint(x: 20, y: 850), primaryFrame: primary) == CGPoint(x: 20, y: 50),
              quartzPoint(CGPoint(x: -50, y: 950), primaryFrame: primary) == CGPoint(x: -50, y: -50) else {
            throw Failure.geometry
        }
        let narrowed = CGRect(x: 223, y: 0, width: 1474, height: 1080)
        let fitted = probeControlFrame(current: narrowed, visibleScreen: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        guard fitted == CGRect(x: 446, y: 0, width: 1474, height: 1080),
              fitted.contains(CGPoint(x: 1884.15, y: 900)),
              !narrowed.contains(CGPoint(x: 1884.15, y: 900)) else { throw Failure.geometry }
        for screen in [CGRect(x: -1080, y: 0, width: 1080, height: 1920),
                       CGRect(x: 1920, y: -900, width: 900, height: 1440),
                       CGRect(x: 0, y: 1080, width: 1920, height: 1080)] {
            let frame = probeControlFrame(current: narrowed, visibleScreen: screen)
            guard screen.contains(frame), frame.maxX == screen.maxX else { throw Failure.geometry }
        }
        let row = Receipt(name: "IMAGE", expectedAsset: UUID(), expectedWindow: 11,
                          expectedPoint: CGPoint(x: 20, y: 30), radius: 2)
        guard row.verdict(focusStable: true) == "INCONCLUSIVE" else { throw Failure.verdict }
        row.downCount = 1; row.upCount = 1; row.coordinatesMatch = true; row.receivedWindows = [11, 11]
        row.acceptedAssets = [row.expectedAsset]; row.selectedAssets = [row.expectedAsset]
        guard row.verdict(focusStable: true) == "PASS_SOFTWARE_ROUTING",
              row.verdict(focusStable: false) == "FAIL" else { throw Failure.verdict }
        let gap = Receipt(name: "GAP", expectedAsset: UUID(), expectedWindow: 12,
                          expectedPoint: CGPoint(x: 20, y: 30), radius: 2)
        gap.downCount = 1; gap.upCount = 1; gap.probeDownCount = 1; gap.probeUpCount = 1; gap.receivedWindows = [12, 12]
        guard gap.verdict(focusStable: true) == "PASS_SOFTWARE_ROUTING" else { throw Failure.verdict }
        gap.selectedAssets = [gap.expectedAsset]
        guard gap.verdict(focusStable: true) == "FAIL" else { throw Failure.verdict }
        gap.selectedAssets = []; gap.coordinatesMatch = false
        guard gap.verdict(focusStable: true) == "INCONCLUSIVE" else { throw Failure.verdict }
        let held = Receipt(name: "HOLD", expectedAsset: UUID(), expectedWindow: 13,
                           expectedPoint: CGPoint(x: 20, y: 30), radius: 2)
        held.downCount = 1; held.upCount = 1; held.receivedWindows = [13, 13]
        held.acceptedAssets = [held.expectedAsset]; held.selectedAssets = [held.expectedAsset]
        guard held.holdVerdict(focusStable: true, heldLayoutStable: true, reorderObserved: true,
                              compactionCorrect: true) == "PASS_SOFTWARE_HOLD",
              held.holdVerdict(focusStable: true, heldLayoutStable: false, reorderObserved: true,
                              compactionCorrect: true) == "FAIL",
              held.holdVerdict(focusStable: true, heldLayoutStable: true, reorderObserved: false,
                              compactionCorrect: true) == "FAIL",
              held.holdVerdict(focusStable: true, heldLayoutStable: true, reorderObserved: true,
                              compactionCorrect: false) == "FAIL" else { throw Failure.verdict }
        held.selectedAssets.append(held.expectedAsset)
        guard held.holdVerdict(focusStable: true, heldLayoutStable: true, reorderObserved: true,
                              compactionCorrect: true) == "FAIL" else { throw Failure.verdict }
        let first = Receipt(name: "DOUBLE_FIRST", expectedAsset: UUID(), expectedWindow: 21,
                            expectedPoint: CGPoint(x: 20, y: 30), radius: 1.5)
        let second = Receipt(name: "DOUBLE_SECOND", expectedAsset: UUID(), expectedWindow: 22,
                             expectedPoint: first.expectedPoint, radius: 1.5)
        first.downCount = 1; first.upCount = 1; first.receivedWindows = [21, 21]
        first.downIdentity = (10, 1, 21); first.downClickCount = 1
        first.acceptedAssets = [first.expectedAsset]; first.selectedAssets = [first.expectedAsset]
        second.downCount = 1; second.upCount = 1; second.receivedWindows = [22, 22]
        second.downIdentity = (10.2, 2, 22); second.downClickCount = 2
        guard doubleVerdict(first: first, second: second, interval: 0.5, focusStable: true) == "PASS_SOFTWARE_DOUBLE_REPLACEMENT"
        else { throw Failure.verdict }
        second.selectedAssets = [second.expectedAsset]
        guard doubleVerdict(first: first, second: second, interval: 0.5, focusStable: true) == "FAIL" else { throw Failure.verdict }
        second.selectedAssets = []; second.downIdentity = (10.6, 2, 22)
        guard doubleVerdict(first: first, second: second, interval: 0.5, focusStable: true) == "INCONCLUSIVE" else { throw Failure.verdict }
        second.downIdentity = (10.2, 2, 22); second.receivedWindows = [21, 21]
        guard doubleVerdict(first: first, second: second, interval: 0.5, focusStable: true) == "INCONCLUSIVE" else { throw Failure.verdict }
    }

    /// CGEvent-supplied clickState=2 tests rejection on a replacement window.
    /// It does not establish that hardware/WindowServer classified a double-click.
    static func doubleVerdict(first: Receipt, second: Receipt, interval: TimeInterval,
                              focusStable: Bool) -> String {
        guard let start = first.downIdentity, let next = second.downIdentity,
              interval > 0, next.time >= start.time, next.time - start.time <= interval,
              first.expectedAsset != second.expectedAsset, first.expectedWindow != second.expectedWindow,
              first.expectedPoint == second.expectedPoint, first.downClickCount == 1, second.downClickCount == 2,
              !second.interference, second.coordinatesMatch, second.downCount == 1, second.upCount == 1,
              second.receivedWindows == [second.expectedWindow, second.expectedWindow] else { return "INCONCLUSIVE" }
        guard first.verdict(focusStable: focusStable) == "PASS_SOFTWARE_ROUTING" else { return "INCONCLUSIVE" }
        return second.acceptedAssets.isEmpty && second.selectedAssets.isEmpty
            && second.probeDownCount == 0 && second.probeUpCount == 0
            ? "PASS_SOFTWARE_DOUBLE_REPLACEMENT" : "FAIL"
    }

    final class Receipt {
        let name: String
        let expectedAsset: UUID
        let expectedWindow: Int
        let expectedPoint: CGPoint
        let radius: CGFloat
        let token = Int64.random(in: 1...(1 << 52))
        var downCount = 0
        var upCount = 0
        var probeDownCount = 0
        var probeUpCount = 0
        var coordinatesMatch = true
        var downIdentity: (time: TimeInterval, number: Int, window: Int)?
        var downClickCount: Int?
        var acceptedAssets: [UUID] = []
        var selectedAssets: [UUID] = []
        var receivedWindows: [Int] = []
        var interference = false

        init(name: String, expectedAsset: UUID, expectedWindow: Int, expectedPoint: CGPoint, radius: CGFloat) {
            self.name = name; self.expectedAsset = expectedAsset; self.expectedWindow = expectedWindow
            self.expectedPoint = expectedPoint; self.radius = radius
        }

        func matches(_ event: NSEvent) -> Bool {
            event.cgEvent?.getIntegerValueField(.eventSourceUserData) == token
        }

        func observe(_ event: NSEvent) {
            guard matches(event) else { interference = true; return }
            guard let window = event.window else { coordinatesMatch = false; return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            coordinatesMatch = coordinatesMatch && window.frame.contains(point)
                && hypot(point.x - expectedPoint.x, point.y - expectedPoint.y) <= radius
            receivedWindows.append(window.windowNumber)
            if event.type == .leftMouseDown {
                downCount += 1
                downIdentity = (event.timestamp, event.eventNumber, event.windowNumber)
                downClickCount = event.clickCount
            } else if event.type == .leftMouseUp { upCount += 1 }
        }

        func verdict(focusStable: Bool) -> String {
            guard !interference, coordinatesMatch, downCount == 1, upCount == 1, receivedWindows.count == 2 else { return "INCONCLUSIVE" }
            let selectsRow = name == "IMAGE" || name == "NUMBER" || name == "HOLD" || name == "DOUBLE_FIRST"
            let routing = selectsRow
                ? acceptedAssets == [expectedAsset] && selectedAssets == [expectedAsset]
                    && probeDownCount == 0 && probeUpCount == 0 && receivedWindows.allSatisfy { $0 == expectedWindow }
                : probeDownCount == 1 && probeUpCount == 1 && acceptedAssets.isEmpty && selectedAssets.isEmpty
                    && receivedWindows.allSatisfy { $0 == expectedWindow }
            return routing && focusStable ? "PASS_SOFTWARE_ROUTING" : "FAIL"
        }

        func holdVerdict(focusStable: Bool, heldLayoutStable: Bool,
                         reorderObserved: Bool, compactionCorrect: Bool) -> String {
            let routing = verdict(focusStable: focusStable)
            guard routing == "PASS_SOFTWARE_ROUTING" else { return routing }
            return heldLayoutStable && reorderObserved && compactionCorrect ? "PASS_SOFTWARE_HOLD" : "FAIL"
        }
    }
}
