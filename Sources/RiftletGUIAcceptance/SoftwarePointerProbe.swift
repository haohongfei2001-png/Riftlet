import AppKit

/// Acceptance-only arithmetic and observations. This never grants input authority
/// to a product operation, and never identifies untagged events as human input.
enum SoftwarePointerProbe {
    static let names = ["IMAGE", "NUMBER", "CLEAR", "GAP"]

    static func quartzPoint(_ point: CGPoint, primaryFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryFrame.maxY - point.y)
    }

    static func selfCheck() throws {
        enum Failure: Error { case geometry, verdict }
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        guard quartzPoint(CGPoint(x: 20, y: 850), primaryFrame: primary) == CGPoint(x: 20, y: 50),
              quartzPoint(CGPoint(x: -50, y: 950), primaryFrame: primary) == CGPoint(x: -50, y: -50) else {
            throw Failure.geometry
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
            } else if event.type == .leftMouseUp { upCount += 1 }
        }

        func verdict(focusStable: Bool) -> String {
            guard !interference, coordinatesMatch, downCount == 1, upCount == 1, receivedWindows.count == 2 else { return "INCONCLUSIVE" }
            let selectsRow = name == "IMAGE" || name == "NUMBER"
            let routing = selectsRow
                ? acceptedAssets == [expectedAsset] && selectedAssets == [expectedAsset]
                    && probeDownCount == 0 && probeUpCount == 0 && receivedWindows.allSatisfy { $0 == expectedWindow }
                : probeDownCount == 1 && probeUpCount == 1 && acceptedAssets.isEmpty && selectedAssets.isEmpty
                    && receivedWindows.allSatisfy { $0 == expectedWindow }
            return routing && focusStable ? "PASS_SOFTWARE_ROUTING" : "FAIL"
        }
    }
}
