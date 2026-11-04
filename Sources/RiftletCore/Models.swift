import Foundation

public enum StoreMode: String, Codable, Sendable { case production, simulation }
public enum AssetOrigin: String, Codable, Sendable {
    case systemScreenshot, synthetic
    /// A real user image created/edited inside Riftlet. This is never synthetic
    /// evidence and cannot borrow the original-system-screenshot admission.
    case applicationScreenshot
}
public enum QueueStatus: String, Codable, Sendable {
    case pending, transferring, unknown, failed, used, missing
}

/// Presentation is independent of external upload/completion facts.
public enum QueueVisibility: String, Codable, Sendable { case visible, swallowed, archived, removed }
public enum QueueVisibilityReason: String, Codable, Sendable {
    case capture, uploadStarted, legacyCompletion, automaticArchive, userRemoved, userRestored, safeFailure
}

/// A capture occurrence, not a content-hash identity. Same pixels captured twice stay separate.
public struct ImportedAsset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceKey: String
    /// A single basename beneath the private media directory. Never an external path.
    public let fileName: String
    public let sha256: String
    public let byteCount: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let mediaType: String
    public let capturedAt: Date?
    public let firstSeenAt: Date
    public let importedAt: Date
    public let origin: AssetOrigin

    public init(id: UUID = UUID(), sourceKey: String, fileName: String, sha256: String,
                byteCount: Int64, pixelWidth: Int, pixelHeight: Int, mediaType: String,
                capturedAt: Date? = nil, firstSeenAt: Date = Date(),
                importedAt: Date = Date(), origin: AssetOrigin = .systemScreenshot) {
        self.id = id; self.sourceKey = sourceKey; self.fileName = fileName; self.sha256 = sha256
        self.byteCount = byteCount; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.mediaType = mediaType; self.capturedAt = capturedAt; self.firstSeenAt = firstSeenAt
        self.importedAt = importedAt; self.origin = origin
    }
}

public struct AssetRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { image.id }
    public let image: ImportedAsset
    public let sequence: Int64
    public let status: QueueStatus
    public let activeOperationID: UUID?
    public let visibility: QueueVisibility
    public let visibilityRevision: Int64
    public let visibilityReason: QueueVisibilityReason
    public let lastInteractionAt: Date

    public init(image: ImportedAsset, sequence: Int64, status: QueueStatus = .pending,
                activeOperationID: UUID? = nil, visibility: QueueVisibility? = nil,
                visibilityRevision: Int64 = 0, visibilityReason: QueueVisibilityReason? = nil,
                lastInteractionAt: Date? = nil) {
        self.image = image; self.sequence = sequence; self.status = status
        self.activeOperationID = activeOperationID
        self.visibility = visibility ?? (status == .used ? .swallowed : .visible)
        self.visibilityRevision = visibilityRevision
        self.visibilityReason = visibilityReason ?? (status == .used ? .legacyCompletion : .capture)
        self.lastInteractionAt = lastInteractionAt ?? image.importedAt
    }
}

public enum TargetSurface: String, Codable, Sendable {
    case webChat, webWork, macChat, macWork, macClassic, simulation
}

/// Coherent local history projection, read in one actor turn/SQLite transaction.
public struct QueueHistoryRecord: Sendable {
    public let record: AssetRecord
    public let operation: TransferOperation?
    public let receipt: TransferReceipt?
    public let canRestore: Bool
    public let reason: String?
}

/// Business identity supplied by a specific observed composer profile. This is
/// separate from the short-lived focus lease and never backfilled into old rows.
public struct LogicalDraftIdentity: Codable, Equatable, Hashable, Sendable {
    public let profileID: String
    public let id: String
    public init(profileID: String, id: String) { self.profileID = profileID; self.id = id }

    public var isRecognized: Bool {
        switch profileID {
        case "chatgpt-composer-react-20261027-v1":
            guard id.utf8.count == 50, id.hasPrefix("local-chatgpt:") else { return false }
            return UUID(uuidString: String(id.dropFirst(14))) != nil
        case "chatgpt-composer-react-persisted-20261027-v1":
            // Preserve the exact observed value and its independent profile.
            // Recognition never maps a local draft to a persisted conversation.
            guard id.utf8.count == 36 else { return false }
            return UUID(uuidString: id) != nil
        default:
            return false
        }
    }
}

/// Captured at click time and rechecked atomically with dispatch by the adapter.
/// Tokens are opaque local identities, never cookies, credentials or chat contents.
public struct TargetLease: Codable, Equatable, Hashable, Sendable {
    public let adapterID: String
    public let surface: TargetSurface
    public let applicationID: String
    public let sessionID: String
    public let windowID: String
    public let tabID: String?
    public let documentID: String
    public let composerID: String
    public let draftGeneration: String
    public let logicalDraftIdentity: LogicalDraftIdentity?
    /// Runtime page-issued click capability; absent on all historical leases.
    public let clickBindingID: UUID?

    public init(adapterID: String, surface: TargetSurface, applicationID: String,
                sessionID: String, windowID: String, tabID: String? = nil,
                documentID: String, composerID: String, draftGeneration: String,
                logicalDraftIdentity: LogicalDraftIdentity? = nil, clickBindingID: UUID? = nil) {
        self.adapterID = adapterID; self.surface = surface; self.applicationID = applicationID
        self.sessionID = sessionID; self.windowID = windowID; self.tabID = tabID
        self.documentID = documentID; self.composerID = composerID; self.draftGeneration = draftGeneration
        self.logicalDraftIdentity = logicalDraftIdentity
        self.clickBindingID = clickBindingID
    }

    public var stableKey: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // All fields are strings/enums; encoding cannot fail for a valid lease.
        return String(data: try! encoder.encode(self), encoding: .utf8)!
    }

    /// Scope comparison only, never an input or receipt capability. Two native
    /// clicks have different pins but may still belong to the same continuously
    /// observed draft. Every identity field other than the click pin must match;
    /// neither a logical ID alone nor a renewed document/input epoch qualifies.
    /// Full Equatable/stableKey identity intentionally remains unchanged.
    public func sharesContinuationDraft(with other: TargetLease) -> Bool {
        guard surface == .webChat, other.surface == surface,
              applicationID == "com.google.Chrome", other.applicationID == applicationID,
              !adapterID.isEmpty, adapterID == other.adapterID,
              !sessionID.isEmpty, sessionID == other.sessionID,
              !windowID.isEmpty, windowID == other.windowID,
              let tabID, !tabID.isEmpty, tabID == other.tabID,
              !documentID.isEmpty, documentID == other.documentID,
              !composerID.isEmpty, composerID == other.composerID,
              !draftGeneration.isEmpty, draftGeneration == other.draftGeneration,
              let draft = logicalDraftIdentity, draft.isRecognized,
              draft == other.logicalDraftIdentity else { return false }
        // Legacy pre-event capabilities may only keep their exact identity.
        // They cannot be promoted into a different, native-click capability.
        if clickBindingID == nil || other.clickBindingID == nil { return self == other }
        return true
    }

    /// Scheduling scope only, never input authority or Web continuation. An
    /// original append may keep observing START while a different, recognized
    /// business draft in a different document takes the input lane. A new pin,
    /// window move, local/persisted transition or reused document is insufficient.
    public func hasIndependentInputDocument(from other: TargetLease) -> Bool {
        guard surface == .webChat, other.surface == surface,
              applicationID == "com.google.Chrome", other.applicationID == applicationID,
              !adapterID.isEmpty, adapterID == other.adapterID,
              !sessionID.isEmpty, sessionID == other.sessionID,
              !windowID.isEmpty, !other.windowID.isEmpty,
              let tabID, !tabID.isEmpty, let otherTab = other.tabID, !otherTab.isEmpty, tabID != otherTab,
              !documentID.isEmpty, !other.documentID.isEmpty, documentID != other.documentID,
              !composerID.isEmpty, !other.composerID.isEmpty,
              !draftGeneration.isEmpty, !other.draftGeneration.isEmpty,
              let a = logicalDraftIdentity, let b = other.logicalDraftIdentity,
              a.isRecognized, b.isRecognized, a.profileID == b.profileID else { return false }
        return a.id.lowercased() != b.id.lowercased()
    }

    /// A focus lease is not a business draft identity. Until the Web adapter has
    /// independently proved that identity, an unresolved upload locks its whole
    /// Chrome tab, including rearming, navigation and moving between windows.
    /// Receipt equality still requires every field of the original lease.
    public var serializationKey: String {
        guard surface == .webChat, applicationID == "com.google.Chrome",
              let tabID, !tabID.isEmpty else { return stableKey }
        return String(data: try! JSONEncoder().encode([adapterID, applicationID, sessionID, tabID]), encoding: .utf8)!
    }

    /// A legacy or unrecognized identity is a wildcard for its entire tab.
    /// Only two recognized, distinct business drafts can narrow that conflict.
    /// Full receipt equality remains unchanged, including the input focus epoch.
    public func conflictsForDispatch(with other: TargetLease) -> Bool {
        guard serializationKey == other.serializationKey || mixedChromeSessionMayConflict(with: other) else { return false }
        guard surface == .webChat, other.surface == .webChat,
              applicationID == "com.google.Chrome", other.applicationID == applicationID,
              let tabID, !tabID.isEmpty, other.tabID == tabID,
              let a = logicalDraftIdentity, let b = other.logicalDraftIdentity,
              a.isRecognized, b.isRecognized, a.profileID == b.profileID else { return true }
        return a.id.lowercased() == b.id.lowercased()
    }

    /// A session spelling upgrade must not unlock an unresolved old operation.
    /// Same PID in mixed formats is only a conservative possible match: kernel
    /// birth never supplies or replaces the old LaunchServices date. Receipt and
    /// serialized identity equality deliberately remain exact and unchanged.
    private func mixedChromeSessionMayConflict(with other: TargetLease) -> Bool {
        guard surface == .webChat, other.surface == .webChat,
              applicationID == "com.google.Chrome", other.applicationID == applicationID,
              adapterID == other.adapterID, let tabID, !tabID.isEmpty, other.tabID == tabID,
              let a = Self.chromeSessionSpelling(sessionID),
              let b = Self.chromeSessionSpelling(other.sessionID) else { return false }
        return a.pid == b.pid && a.kernel != b.kernel
    }

    private static func chromeSessionSpelling(_ session: String) -> (pid: Int32, kernel: Bool)? {
        let fields = session.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        func pid(_ text: String) -> Int32? {
            guard let n = Int32(text), n > 0, String(n) == text else { return nil }; return n
        }
        if fields.count == 2, let process = pid(fields[0]), let date = Double(fields[1]),
           date.isFinite, date > 0, String(date) == fields[1] {
            return (process, false)
        }
        if fields.count == 4, fields[0] == "chrome-kernel-v1", let process = pid(fields[1]),
           let seconds = UInt64(fields[2]), seconds > 0, String(seconds) == fields[2],
           let micros = UInt64(fields[3]), micros < 1_000_000, String(micros) == fields[3] {
            return (process, true)
        }
        return nil
    }
}

public enum OperationPhase: String, Codable, Sendable {
    case prepared, dispatchIntent, inputTriggered, attachmentPresent, unknown, compensated, failed, succeeded
    public var isUnresolved: Bool { self != .failed && self != .succeeded }
}

public struct TransferOperation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let assetID: UUID
    public let attempt: Int
    public let target: TargetLease
    public let phase: OperationPhase
    public let createdAt: Date
    public let updatedAt: Date
}

public enum ReceiptOutcome: String, Codable, Sendable {
    case inputTriggered, attachedCandidate, uploadStarted, verifiedReady, definitiveFailure, unknown
}

public enum UploadStartSignal: String, Codable, Sendable {
    case correlatedProgress, correlatedByteRequest
    /// The current file produced a new, operation-correlated attachment in the
    /// original composer after change. A setter return alone is not acceptance.
    case attachmentAccepted
}

/// Identity is carried by the enclosing receipt. These fields are claims until
/// an independently reviewed, surface-specific start profile admits them.
public struct UploadStartEvidence: Codable, Equatable, Sendable {
    public let version: Int
    public let profileID: String
    public let signal: UploadStartSignal
    public let evidenceID: String
    public let inputCount: Int
    public init(version: Int = 1, profileID: String, signal: UploadStartSignal,
                evidenceID: String, inputCount: Int = 1) {
        self.version = version; self.profileID = profileID; self.signal = signal
        self.evidenceID = evidenceID; self.inputCount = inputCount
    }
}

/// Start, completion and retry have separate admission. Visual exit is not success.
public struct TransferReceipt: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let assetID: UUID
    public let attempt: Int
    public let assetSHA256: String
    public let target: TargetLease
    public let outcome: ReceiptOutcome
    public let profileID: String
    public let attachmentID: String?
    public let positiveReady: Bool
    public let belongsToOriginalDraft: Bool
    public let hasError: Bool
    public let isUploading: Bool
    /// True only if the adapter has proved no residual auto-retrying attachment remains.
    public let safeToRetry: Bool
    public let reason: String
    public let uploadStartEvidence: UploadStartEvidence?
    public let continuationEvidence: AttachmentContinuationEvidence?
    public let completionEvidence: AttachmentCompletionEvidence?
    public let terminationEvidence: AttachmentTerminationEvidence?

    public init(operationID: UUID, assetID: UUID, attempt: Int, assetSHA256: String,
                target: TargetLease, outcome: ReceiptOutcome, profileID: String,
                attachmentID: String? = nil, positiveReady: Bool = false,
                belongsToOriginalDraft: Bool = false, hasError: Bool = false,
                isUploading: Bool = false, safeToRetry: Bool = false, reason: String = "",
                uploadStartEvidence: UploadStartEvidence? = nil,
                continuationEvidence: AttachmentContinuationEvidence? = nil,
                completionEvidence: AttachmentCompletionEvidence? = nil,
                terminationEvidence: AttachmentTerminationEvidence? = nil) {
        self.operationID = operationID; self.assetID = assetID; self.attempt = attempt
        self.assetSHA256 = assetSHA256; self.target = target; self.outcome = outcome
        self.profileID = profileID; self.attachmentID = attachmentID
        self.positiveReady = positiveReady; self.belongsToOriginalDraft = belongsToOriginalDraft
        self.hasError = hasError; self.isUploading = isUploading; self.safeToRetry = safeToRetry
        self.reason = reason
        self.uploadStartEvidence = uploadStartEvidence
        self.continuationEvidence = continuationEvidence
        self.completionEvidence = completionEvidence
        self.terminationEvidence = terminationEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case operationID, assetID, attempt, assetSHA256, target, outcome, profileID, attachmentID
        case positiveReady, belongsToOriginalDraft, hasError, isUploading, safeToRetry, reason
        case uploadStartEvidence, continuationEvidence, completionEvidence, terminationEvidence
        case attachmentAcceptanceEvidence
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacyStart = try values.decodeIfPresent(UploadStartEvidence.self, forKey: .uploadStartEvidence)
        let acceptance = try values.decodeIfPresent(UploadStartEvidence.self, forKey: .attachmentAcceptanceEvidence)
        if let acceptance {
            guard legacyStart == nil, acceptance.signal == .attachmentAccepted else {
                throw DecodingError.dataCorruptedError(forKey: .attachmentAcceptanceEvidence, in: values,
                    debugDescription: "Attachment acceptance must be the sole start evidence and use its own signal")
            }
        }
        self.init(operationID: try values.decode(UUID.self, forKey: .operationID),
            assetID: try values.decode(UUID.self, forKey: .assetID),
            attempt: try values.decode(Int.self, forKey: .attempt),
            assetSHA256: try values.decode(String.self, forKey: .assetSHA256),
            target: try values.decode(TargetLease.self, forKey: .target),
            outcome: try values.decode(ReceiptOutcome.self, forKey: .outcome),
            profileID: try values.decode(String.self, forKey: .profileID),
            attachmentID: try values.decodeIfPresent(String.self, forKey: .attachmentID),
            positiveReady: try values.decode(Bool.self, forKey: .positiveReady),
            belongsToOriginalDraft: try values.decode(Bool.self, forKey: .belongsToOriginalDraft),
            hasError: try values.decode(Bool.self, forKey: .hasError),
            isUploading: try values.decode(Bool.self, forKey: .isUploading),
            safeToRetry: try values.decode(Bool.self, forKey: .safeToRetry),
            reason: try values.decode(String.self, forKey: .reason),
            uploadStartEvidence: acceptance ?? legacyStart,
            continuationEvidence: try values.decodeIfPresent(AttachmentContinuationEvidence.self, forKey: .continuationEvidence),
            completionEvidence: try values.decodeIfPresent(AttachmentCompletionEvidence.self, forKey: .completionEvidence),
            terminationEvidence: try values.decodeIfPresent(AttachmentTerminationEvidence.self, forKey: .terminationEvidence))
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationID, forKey: .operationID)
        try values.encode(assetID, forKey: .assetID)
        try values.encode(attempt, forKey: .attempt)
        try values.encode(assetSHA256, forKey: .assetSHA256)
        try values.encode(target, forKey: .target)
        try values.encode(outcome, forKey: .outcome)
        try values.encode(profileID, forKey: .profileID)
        try values.encodeIfPresent(attachmentID, forKey: .attachmentID)
        try values.encode(positiveReady, forKey: .positiveReady)
        try values.encode(belongsToOriginalDraft, forKey: .belongsToOriginalDraft)
        try values.encode(hasError, forKey: .hasError)
        try values.encode(isUploading, forKey: .isUploading)
        try values.encode(safeToRetry, forKey: .safeToRetry)
        try values.encode(reason, forKey: .reason)
        // PR40's strict enum knows only progress/request START. Store the new
        // signal in an additive key its decoder ignores, so the retained App
        // can still read the same database after rollback. Never mislabel this
        // receipt as a progress event or rewrite an older receipt to upgrade it.
        if let start = uploadStartEvidence, start.signal == .attachmentAccepted {
            try values.encode(start, forKey: .attachmentAcceptanceEvidence)
        } else {
            try values.encodeIfPresent(uploadStartEvidence, forKey: .uploadStartEvidence)
        }
        try values.encodeIfPresent(continuationEvidence, forKey: .continuationEvidence)
        try values.encodeIfPresent(completionEvidence, forKey: .completionEvidence)
        try values.encodeIfPresent(terminationEvidence, forKey: .terminationEvidence)
    }
}

public enum RiftletError: Error, Equatable {
    case database(String), invalidAsset(String), assetNotFound, operationNotFound
    case unresolvedOperation(UUID), targetBusy, invalidTransition, mismatchedReceipt
    case modeMismatch, adapterUnavailable(String)
}

/// The first admitted success and its identity-correlated revocation survive all
/// later observations. Revocation alone grants neither visibility nor new input.
public struct TransferCompensation: Codable, Equatable, Sendable {
    public let originalSuccess: TransferReceipt
    public let failure: TransferReceipt
    public let createdAt: Date
}
