import RiftletCore
import RiftletUI

/// Explicit capabilities avoid making "not ordinary capture" mean synthetic.
/// No setting, permission reply, page JSON or persisted click changes a mode.
enum ApplicationMode: CaseIterable, Equatable {
    case capture, simulation, webAcceptance, systemScreenshotCandidate

    static func resolve(_ arguments: [String]) throws -> ApplicationMode {
        let selections: [(String, ApplicationMode)] = [
            ("--simulate", .simulation), ("--web-acceptance", .webAcceptance),
            ("--system-screenshot-candidate", .systemScreenshotCandidate)
        ]
        let selected = selections.filter { arguments.contains($0.0) }
        guard !OrdinaryCaptureConfiguration.isInternalAcceptance || selected.isEmpty else { throw RiftletError.modeMismatch }
        guard selected.count <= 1 else { throw RiftletError.modeMismatch }
        return selected.first?.1 ?? .capture
    }

    var collectsSystemScreenshots: Bool { self == .capture || self == .systemScreenshotCandidate }
    var usesWebAdapter: Bool { usesWebAdapter(ordinary: OrdinaryCaptureConfiguration.admission) }
    func usesWebAdapter(ordinary: OrdinaryAttachmentAdmission) -> Bool {
        self == .webAcceptance || self == .systemScreenshotCandidate || (self == .capture && ordinary.allowsInput)
    }
    var observesAttachments: Bool { self != .capture || usesWebAdapter }
    var generatesSyntheticImages: Bool { self == .simulation || self == .webAcceptance }
    var storeMode: StoreMode { self == .simulation ? .simulation : .production }
    var directoryName: String {
        switch self {
        case .capture: return OrdinaryCaptureConfiguration.dataDirectoryName
        case .simulation: return "Riftlet-Simulation"
        case .webAcceptance: return "Riftlet-Web-Acceptance"
        case .systemScreenshotCandidate: return "Riftlet-System-Screenshot-Candidate"
        }
    }
    var attachmentState: SetupAttachmentState {
        switch self {
        case .capture: return usesWebAdapter ? .available : .productionDisabled
        case .simulation: return .offlineSimulation
        case .webAcceptance: return .syntheticWeb
        case .systemScreenshotCandidate: return .systemScreenshotCandidate
        }
    }
    var menuTitle: String {
        switch self {
        case .capture: return OrdinaryCaptureConfiguration.menuTitle
        case .simulation: return "Riftlet SIM"
        case .webAcceptance: return "Riftlet WEB TEST"
        case .systemScreenshotCandidate: return "Riftlet REAL TEST"
        }
    }
}
