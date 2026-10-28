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
              SystemScreenshotCandidateConfiguration.uploadStartProfiles == [SystemScreenshotWebCandidate.admittedUploadStartProfileID: .webChat],
              SystemScreenshotCandidateConfiguration.completedAttachmentProfiles == [SystemScreenshotWebCandidate.admittedCompletionProfileID: .webChat],
              SystemScreenshotCandidateConfiguration.safeFailureProfiles.isEmpty else { throw RiftletError.modeMismatch }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-system-candidate-check-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("private")
        let source = directory.appendingPathComponent("generated-fixture.png")
        try writeFixture(to: source)
        let bytes = try Data(contentsOf: source)
        guard bytes.count > 33, bytes[24] == 8, bytes[25] == 6, bytes[28] == 0 else {
            throw RiftletError.invalidAsset("Software fixture must exercise the admitted PNG representation")
        }
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
              started.visibility == .swallowed, started.visibilityReason == .uploadStarted,
              started.status != .used, try await store.operation(id: id)?.phase != .succeeded,
              try await store.uploadStartReceipt(for: id)?.uploadStartEvidence?.profileID == SystemScreenshotWebCandidate.admittedUploadStartProfileID,
              try await store.receipt(for: id)?.outcome == .uploadStarted else { throw RiftletError.invalidTransition }
        let startKey = "system-screenshot-candidate-observation-v1:\(id.uuidString.lowercased()):1:start"
        let admissionKey = "system-screenshot-admission-v2:\(id.uuidString.lowercased()):1"
        guard let firstStart = try await store.checkpoint(for: startKey),
              let registration = try await store.checkpoint(for: admissionKey),
              await bridge.actions.filter({ $0 == .observe }).isEmpty else { throw RiftletError.invalidTransition }
        // Start returns immediately through the existing Core/UI lifecycle.
        // Recovery preserves that exit and only observes the original operation.
        await bridge.setState(.unknown)
        let reopened = try QueueStore(databaseURL: database)
        let recoveredComposition = try ApplicationAttachmentComposition.make(mode: mode, root: root, store: reopened,
            executor: bridge, polling: .disabled)
        let recovered = TransferCoordinator(store: reopened, adapter: recoveredComposition.adapter,
            mediaDirectory: root.appendingPathComponent("media"), policy: recoveredComposition.policy)
        try await recovered.recover()
        guard try await reopened.operation(id: id)?.phase == .unknown,
              try await reopened.asset(id: record.id)?.visibility == .swallowed,
              try await reopened.asset(id: record.id)?.visibilityRevision == started.visibilityRevision else {
            throw RiftletError.invalidTransition
        }
        await bridge.setState(.attached)
        try await recovered.observePending()
        guard try await reopened.receipt(for: id)?.profileID == SystemScreenshotWebCandidate.admittedCompletionProfileID,
              try await reopened.operation(id: id)?.phase == .succeeded,
              try await reopened.asset(id: record.id)?.status == .used,
              try await reopened.asset(id: record.id)?.visibilityRevision == started.visibilityRevision else {
            throw RiftletError.invalidTransition
        }

        // A historical F-like UNKNOWN has no registration. Even a fully valid
        // attached observation must leave it visible/locked, without new input.
        let oldFileName = "software-historical-\(UUID()).png"
        try bytes.write(to: root.appendingPathComponent("media").appendingPathComponent(oldFileName))
        let oldImage = ImportedAsset(sourceKey: "software-historical-\(UUID())", fileName: oldFileName,
            sha256: record.image.sha256, byteCount: record.image.byteCount,
            pixelWidth: record.image.pixelWidth, pixelHeight: record.image.pixelHeight,
            mediaType: record.image.mediaType, origin: .systemScreenshot)
        _ = try await reopened.importAsset(oldImage)
        let old = try await reopened.prepare(assetID: oldImage.id, target: CandidateCheckBridge.target)
        try await reopened.markDispatchIntent(old.id)
        try await reopened.markUnknown(old.id, reason: "Software legacy F-like fixture")
        try await recovered.select(oldImage.id, frozenTarget: nil)
        let oldKey = "system-screenshot-admission-v2:\(old.id.uuidString.lowercased()):1"
        guard try await reopened.operation(id: old.id)?.phase == .unknown,
              try await reopened.asset(id: oldImage.id)?.visibility == .visible,
              try await reopened.asset(id: oldImage.id)?.activeOperationID == old.id,
              try await reopened.receipt(for: old.id)?.profileID == SystemScreenshotWebCandidate.completionProfileID,
              try await reopened.checkpoint(for: oldKey) == nil,
              try await reopened.uploadStartReceipt(for: old.id) == nil else { throw RiftletError.invalidTransition }
        let actions = await bridge.actions
        let transferred = await bridge.bytes
        guard actions.filter({ $0 == .begin }).count == 1, actions.filter({ $0 == .commit }).count == 1,
              !actions.contains(.captureTarget), transferred == bytes,
              try await reopened.asset(id: record.id)?.activeOperationID == id,
              try await reopened.checkpoint(for: startKey) == firstStart,
              try await reopened.checkpoint(for: admissionKey) == registration,
              try await reopened.uploadStartReceipt(for: id) != nil,
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
        context.setFillColor(CGColor(red: 0.3, green: 0.7, blue: 0.2, alpha: 0.75))
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
        composerID: "software-composer", draftGeneration: "original",
        logicalDraftIdentity: .init(profileID: "chatgpt-composer-react-persisted-20261027-v1",
            id: "11111111-1111-4111-8111-111111111111"))
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
