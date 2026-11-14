import AppKit
import CryptoKit
import RiftletUI

/// Read-only observations for the external mouse probe. No input is accepted here.
@MainActor final class AcceptanceHitMap {
    private struct Row: Encodable {
        let assetIDDigest: String
        let ordinal, windowNumber: Int
        let x, y, width, height: CGFloat
    }

    private struct Snapshot: Encodable {
        let pid: Int32
        let uptime: TimeInterval
        let rows: [Row]
        let ignoringWindowNumbers: [Int]
    }

    private let file: URL
    private var sampler: Task<Void, Never>?

    init?(panel: RiftPanelController, directory: URL, arguments: [String], buildChannel: String?) {
        guard buildChannel == "development", arguments.contains("--acceptance-trace"),
              arguments.contains("--acceptance-hit-map") else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        file = directory.appendingPathComponent("acceptance-hit-map.json")
        panel.readsAcceptanceMouseTag = true
        sampler = Task { [weak self, weak panel] in
            while !Task.isCancelled {
                guard let panel else { return }
                self?.publish(panel)
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            }
        }
    }

    func stop() {
        sampler?.cancel()
        sampler = nil
        try? FileManager.default.removeItem(at: file)
    }

    private func publish(_ panel: RiftPanelController) {
        // AppKit uses bottom-left points, Quartz uses top-left points on the main display.
        guard let primary = NSScreen.screens.first else { return }
        let rows = panel.diagnosticThumbnailHitRegions.map { region in
            let digest = SHA256.hash(data: Data(region.assetID.uuidString.lowercased().utf8))
            return Row(assetIDDigest: digest.map { String(format: "%02x", $0) }.joined(),
                       ordinal: region.ordinal, windowNumber: region.windowNumber, x: region.frame.minX,
                       y: primary.frame.maxY - region.frame.maxY, width: region.frame.width, height: region.frame.height)
        }
        let ignoring = NSApp.windows.filter { $0.isVisible && $0.ignoresMouseEvents && $0.windowNumber > 0 }
        let snapshot = Snapshot(pid: ProcessInfo.processInfo.processIdentifier,
                                uptime: ProcessInfo.processInfo.systemUptime, rows: rows,
                                ignoringWindowNumbers: ignoring.map(\.windowNumber).sorted())
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
    }
}
