import Foundation
import RiftletCapture

/// Shared by the product settings owner, its native controller and the historical fixture.
public struct RiftSettingsDisplay: Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public let uuid: String?
    public init(id: UInt32, name: String, uuid: String? = nil) { self.id = id; self.name = name; self.uuid = uuid }
}

public struct RiftSettingsSnapshot: Equatable, Sendable {
    public var entryAvailable: Bool
    public var entryEnabled: Bool
    public var capturePreferencesSaveFailed: Bool
    public var defaultCaptureMode: ScreenshotMode
    public var arrivalMode: ArrivalMotionMode
    public var hasArrivalSelection: Bool
    public var displays: [RiftSettingsDisplay]
    public var preferredDisplayID: UInt32?
    public var configuration: RiftConfiguration
    public var displayRestoreAvailable: Bool
    public var archiveAfterMinutes: Double?

    public init(entryAvailable: Bool = false, entryEnabled: Bool = true,
                capturePreferencesSaveFailed: Bool = false,
                defaultCaptureMode: ScreenshotMode = .window, arrivalMode: ArrivalMotionMode = .none,
                hasArrivalSelection: Bool = false, displays: [RiftSettingsDisplay] = [],
                preferredDisplayID: UInt32? = nil, archiveAfterMinutes: Double? = QueueArchivePolicy.defaultMinutes,
                configuration: RiftConfiguration = .init(), displayRestoreAvailable: Bool = false) {
        self.entryAvailable = entryAvailable; self.entryEnabled = entryEnabled
        self.capturePreferencesSaveFailed = capturePreferencesSaveFailed
        self.defaultCaptureMode = defaultCaptureMode; self.arrivalMode = arrivalMode
        self.hasArrivalSelection = hasArrivalSelection; self.displays = displays
        self.preferredDisplayID = preferredDisplayID; self.archiveAfterMinutes = archiveAfterMinutes
        self.configuration = configuration; self.displayRestoreAvailable = displayRestoreAvailable
    }
}

public enum RiftSettingsChange: Equatable, Sendable {
    case entryEnabled(Bool), defaultCaptureMode(ScreenshotMode), arrivalMode(ArrivalMotionMode)
    case preferredDisplay(UInt32?), archiveAfterMinutes(Double?)
    case geometry(hiddenFraction: Double, outerInset: Double, visibleCount: Int)
    case placement(RiftPlacement), restorePreferredDisplay
}
