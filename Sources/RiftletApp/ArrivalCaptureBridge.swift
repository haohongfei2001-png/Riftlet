import AppKit
import CoreGraphics
import Darwin
import RiftletCapture
import RiftletCore
import RiftletUI

/// Coordinate interpretation is an empirical OS contract. No real build was
/// verified in this Linux authoring session, so ordinary collection fails closed.
/// Add an exact build only after the source-geometry Mac checklist is evidenced.
enum ArrivalSourceProfile {
    static let admittedOSBuilds: Set<String> = []
    static let candidateArgument = "--arrival-metadata-candidate"

    static var currentOSBuild: String? {
        var count = 0
        guard sysctlbyname("kern.osversion", nil, &count, nil, 0) == 0, (2...256).contains(count) else { return nil }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("kern.osversion", &bytes, &count, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }

    static func allowsMetadata(arguments: [String]) -> Bool {
        arguments.contains(candidateArgument) || currentOSBuild.map { admittedOSBuilds.contains($0) } == true
    }
}

private actor ArrivalMetadataReader {
    func read(_ observation: ScreenshotSourceObservation)
        -> Result<ScreenshotSourceMetadata, ScreenshotSourceFailure>? {
        guard !Task.isCancelled else { return nil }
        // A slow filesystem syscall cannot be forcibly cancelled. Actor
        // serialization guarantees a burst cannot create concurrent readers;
        // cancelled queued requests are skipped before opening a file.
        return observation.readMetadata()
    }
}

/// One optional metadata read in flight. Queue publication and every business
/// operation remain independent of this object and of its task's completion.
@MainActor
final class ArrivalCaptureBridge {
    private weak var panel: RiftPanelController?
    private let allowsMetadata: Bool
    private let metadataReader = ArrivalMetadataReader()
    private var task: Task<Void, Never>?
    private var epoch: UInt = 0
    private var topologyObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lastTopologyChange = ProcessInfo.processInfo.systemUptime

    init(panel: RiftPanelController, allowsMetadata: Bool) {
        self.panel = panel; self.allowsMetadata = allowsMetadata
        observe(NSApplication.didChangeScreenParametersNotification, center: .default)
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.willSleepNotification, center: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter)
    }

    func imported(_ record: AssetRecord, observation: ScreenshotSourceObservation) {
        task?.cancel(); task = nil; epoch &+= 1
        guard let panel else { return }
        // Even a malformed/missing source or rapid new capture settles the old
        // decoration; cancellation never discards either durable screenshot.
        panel.cancelDecorations(reason: .captureObserved)
        guard allowsMetadata, record.id == observation.assetID,
              record.image.origin == .systemScreenshot,
              record.visibility == .visible, record.status == .pending,
              Date().timeIntervalSince(record.image.firstSeenAt) >= 0,
              Date().timeIntervalSince(record.image.firstSeenAt) <= 2,
              observation.readyUptime - lastTopologyChange >= 2,
              let token = panel.noteCaptureReady(record.id, uptime: observation.readyUptime) else { return }
        let screens = Self.displays()
        guard let target = panel.arrivalDestinationDisplayID else {
            panel.resolveArrivalSource(nil, assetID: record.id, token: token); return
        }
        let owner = epoch
        let reader = metadataReader
        task = Task(priority: .utility) { [weak self] in
            let result = await reader.read(observation)
            guard let self, !Task.isCancelled, self.epoch == owner,
                  screens == Self.displays(), let panel = self.panel else { return }
            let source: RiftArrivalSource?
            if case .some(.success(let metadata)) = result,
               case .success(let geometry) = ScreenshotSourceGeometryResolver.resolve(metadata,
                    pixelWidth: record.image.pixelWidth, pixelHeight: record.image.pixelHeight,
                    displays: screens, targetDisplayID: target),
               let display = screens.first(where: { $0.id == geometry.displayID }) {
                source = RiftArrivalSource(rect: geometry.appKitRect, displayID: geometry.displayID,
                    displayFrame: display.appKitFrame, backingScale: CGFloat(geometry.backingScale))
            } else { source = nil }
            panel.resolveArrivalSource(source, assetID: record.id, token: token)
            self.task = nil
        }
    }

    func cancel() {
        epoch &+= 1; task?.cancel(); task = nil
        panel?.cancelDecorations(reason: .geometryChanged)
    }

    func close() {
        cancel(); panel = nil
        topologyObservers.forEach { $0.0.removeObserver($0.1) }; topologyObservers.removeAll()
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastTopologyChange = ProcessInfo.processInfo.systemUptime
                self?.cancel()
            }
        }
        topologyObservers.append((center, token))
    }

    private static func displays() -> [ScreenshotDisplayGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return ScreenshotDisplayGeometry(id: id, quartzBounds: CGDisplayBounds(id),
                appKitFrame: screen.frame, backingScale: Double(screen.backingScaleFactor),
                isMirrored: CGDisplayIsInMirrorSet(id) != 0)
        }.sorted { $0.id < $1.id }
    }

    deinit {
        task?.cancel()
        topologyObservers.forEach { $0.0.removeObserver($0.1) }
    }
}
