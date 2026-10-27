import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import Darwin
import RiftletCore
import RiftletCapture
import RiftletAdapters

/// Packaged software check only. A generated PNG is marked with fixture xattr
/// to exercise the real importer. The executor below is fake; no browser, TCC,
/// real system screenshot folder, user image or production profile is used.
enum SystemScreenshotCandidateSelfCheck {
    @MainActor static func run() async throws {
        let mode = try ApplicationMode.resolve(["--system-screenshot-candidate"])
        guard mode == .systemScreenshotCandidate, mode.collectsSystemScreenshots,
              mode.usesWebAdapter, !mode.generatesSyntheticImages,
              Set(ApplicationMode.allCases.map(\.directoryName)).count == 4,
              SystemScreenshotCandidateConfiguration.uploadStartProfiles.isEmpty,
              SystemScreenshotCandidateConfiguration.completedAttachmentProfiles.isEmpty,
              SystemScreenshotCandidateConfiguration.safeFailureProfiles.isEmpty else { throw RiftletError.modeMismatch }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-system-candidate-check-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("private")
        let source = directory.appendingPathComponent("generated-fixture.png")
        try writeFixture(to: source)
        let bytes = try Data(contentsOf: source)
        let database = root.appendingPathComponent("queue.sqlite")
        let store = try QueueStore(databaseURL: database)
        let importer = PrivateAssetImporter(privateRoot: root, store: store)
        let record = try await importer.importFile(at: source)
        try await SystemScreenshotCandidateConfiguration.validateStore(store)
        let bridge = CandidateCheckBridge()
        let composition = try ApplicationAttachmentComposition.make(mode: mode, root: root, store: store,
            executor: bridge, polling: .disabled)
        let coordinator = TransferCoordinator(store: store, adapter: composition.adapter,
            mediaDirectory: root.appendingPathComponent("media"), policy: composition.policy,
            validateAcceptedSelection: { _ in true }) // Software authority fixture, not TCC evidence.
        let now = ProcessInfo.processInfo.systemUptime
        let selection = AcceptedSelection(assetID: record.id, target: CandidateCheckBridge.target,
            hostEpoch: UUID(), acknowledgedUptime: now - 0.2, eventUptime: now - 0.1,
            acceptedUptime: now, visibilityRevision: record.visibilityRevision, deadlineUptime: now + 30)
        try await coordinator.select(selection)
        guard let started = try await store.asset(id: record.id), let id = started.activeOperationID,
              started.visibility == .visible, started.status == .unknown,
              try await store.uploadStartReceipt(for: id) == nil,
              try await store.receipt(for: id)?.outcome == .uploadStarted else { throw RiftletError.invalidTransition }
        let startKey = "system-screenshot-candidate-observation-v1:\(id.uuidString.lowercased()):1:start"
        guard let firstStart = try await store.checkpoint(for: startKey) else { throw RiftletError.invalidTransition }
        await bridge.setState(.attached)
        try await coordinator.observePending()
        guard try await store.receipt(for: id)?.outcome == .verifiedReady,
              try await store.operation(id: id)?.phase == .unknown,
              try await store.asset(id: record.id)?.visibility == .visible else { throw RiftletError.invalidTransition }
        // A newer observation never replaces the first unadmitted start. A
        // restart and a later reclick may only observe the original operation.
        await bridge.setState(.unknown)
        let reopened = try QueueStore(databaseURL: database)
        let recoveredComposition = try ApplicationAttachmentComposition.make(mode: mode, root: root, store: reopened,
            executor: bridge, polling: .disabled)
        let recovered = TransferCoordinator(store: reopened, adapter: recoveredComposition.adapter,
            mediaDirectory: root.appendingPathComponent("media"), policy: recoveredComposition.policy)
        try await recovered.recover()
        try await recovered.select(record.id, frozenTarget: nil)
        let actions = await bridge.actions
        let transferred = await bridge.bytes
        guard actions.filter({ $0 == .begin }).count == 1, actions.filter({ $0 == .commit }).count == 1,
              !actions.contains(.captureTarget), transferred == bytes,
              try await reopened.asset(id: record.id)?.activeOperationID == id,
              try await reopened.checkpoint(for: startKey) == firstStart,
              try await reopened.uploadStartReceipt(for: id) == nil,
              try Data(contentsOf: source) == bytes,
              try Data(contentsOf: root.appendingPathComponent("media").appendingPathComponent(record.image.fileName)) == bytes else {
            throw RiftletError.invalidTransition
        }
    }

    private static func writeFixture(to url: URL) throws {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let context = CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8,
                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RiftletError.invalidAsset("Software image fixture unavailable")
        }
        context.setFillColor(CGColor(red: 0.3, green: 0.7, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RiftletError.invalidAsset("Software image encoder unavailable")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RiftletError.invalidAsset("Software image encoding failed") }
        let flag = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        guard flag.withUnsafeBytes({ setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0) }) == 0 else {
            throw RiftletError.invalidAsset("Software screenshot metadata unavailable")
        }
    }
}

private actor CandidateCheckBridge: WebBridgeExecutor {
    static let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
        sessionID: "software-candidate-session", windowID: "1", tabID: "1", documentID: "software-document",
        composerID: "software-composer", draftGeneration: "original")
    private(set) var actions: [WebBridgeAction] = []
    private(set) var bytes = Data()
    private var state: AttachmentObservedState = .uploadStarted
    private let startID = UUID().uuidString
    func setState(_ value: AttachmentObservedState) { state = value }

    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        actions.append(command.action)
        switch command.action {
        case .captureTarget: throw WebAdapterError.invalidRequest
        case .validate:
            let target = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.target))
            return try JSONSerialization.data(withJSONObject: ["target": target, "valid": command.target == Self.target])
        case .begin, .chunk:
            guard let identity = command.identity else { throw WebAdapterError.invalidRequest }
            if command.action == .chunk {
                guard let encoded = command.chunkBase64, let chunk = Data(base64Encoded: encoded) else { throw WebAdapterError.invalidRequest }
                bytes.append(chunk)
            }
            return try JSONSerialization.data(withJSONObject: ["operationID": identity.operationID.uuidString,
                "attempt": identity.attempt, "nextChunk": command.action == .begin ? 0 : (command.chunkIndex ?? -1) + 1])
        case .commit, .observe:
            guard let identity = command.identity else { throw WebAdapterError.invalidRequest }
            let observation = AttachmentObservation(identity: identity, state: state,
                attachmentID: "software-original-card", exactImageIdentity: true, belongsToOriginalDraft: true,
                isUploading: state == .uploadStarted)
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AttachmentObservationEnvelope(
                schemaVersion: 2, provenance: .init(source: .integratedDevelopment, evidenceID: "software-candidate-no-live-evidence"),
                observation: observation))) as! [String: Any]
            if state == .uploadStarted {
                var item = value["observation"] as! [String: Any]
                item["uploadStart"] = ["version": 1, "signal": "correlatedProgress", "evidenceID": startID,
                    "inputCount": 1, "inputSequence": 1, "startSequence": 3, "previousProgress": 10,
                    "currentProgress": 30, "inputObservedAtMS": 10, "startObservedAtMS": 20] as [String: Any]
                value["observation"] = item
            }
            return try JSONSerialization.data(withJSONObject: value)
        case .discard: return Data("{}".utf8)
        }
    }
}
