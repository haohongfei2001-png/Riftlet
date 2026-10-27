import Foundation

public enum StoreMode: String, Codable, Sendable { case production, simulation }
public enum AssetOrigin: String, Codable, Sendable { case systemScreenshot, synthetic }
public enum QueueStatus: String, Codable, Sendable {
    case pending, transferring, unknown, failed, used, missing
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

    public init(image: ImportedAsset, sequence: Int64, status: QueueStatus = .pending,
                activeOperationID: UUID? = nil) {
        self.image = image; self.sequence = sequence; self.status = status
        self.activeOperationID = activeOperationID
    }
}

public enum TargetSurface: String, Codable, Sendable {
    case webChat, webWork, macChat, macWork, macClassic, simulation
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

    public init(adapterID: String, surface: TargetSurface, applicationID: String,
                sessionID: String, windowID: String, tabID: String? = nil,
                documentID: String, composerID: String, draftGeneration: String) {
        self.adapterID = adapterID; self.surface = surface; self.applicationID = applicationID
        self.sessionID = sessionID; self.windowID = windowID; self.tabID = tabID
        self.documentID = documentID; self.composerID = composerID; self.draftGeneration = draftGeneration
    }

    public var stableKey: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // All fields are strings/enums; encoding cannot fail for a valid lease.
        return String(data: try! encoder.encode(self), encoding: .utf8)!
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
    case inputTriggered, attachedCandidate, verifiedReady, definitiveFailure, unknown
}

/// Evidence is data; only the reviewed ReceiptPolicy may turn it into consumption.
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

    public init(operationID: UUID, assetID: UUID, attempt: Int, assetSHA256: String,
                target: TargetLease, outcome: ReceiptOutcome, profileID: String,
                attachmentID: String? = nil, positiveReady: Bool = false,
                belongsToOriginalDraft: Bool = false, hasError: Bool = false,
                isUploading: Bool = false, safeToRetry: Bool = false, reason: String = "") {
        self.operationID = operationID; self.assetID = assetID; self.attempt = attempt
        self.assetSHA256 = assetSHA256; self.target = target; self.outcome = outcome
        self.profileID = profileID; self.attachmentID = attachmentID
        self.positiveReady = positiveReady; self.belongsToOriginalDraft = belongsToOriginalDraft
        self.hasError = hasError; self.isUploading = isUploading; self.safeToRetry = safeToRetry
        self.reason = reason
    }
}

public enum RiftletError: Error, Equatable {
    case database(String), invalidAsset(String), assetNotFound, operationNotFound
    case unresolvedOperation(UUID), targetBusy, invalidTransition, mismatchedReceipt
    case modeMismatch, adapterUnavailable(String)
}

/// The first admitted success and its identity-correlated revocation survive all
/// later observations. Revocation restores visibility but grants no new input.
public struct TransferCompensation: Codable, Equatable, Sendable {
    public let originalSuccess: TransferReceipt
    public let failure: TransferReceipt
    public let createdAt: Date
}
