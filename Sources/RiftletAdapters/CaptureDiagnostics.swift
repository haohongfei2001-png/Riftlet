import Foundation
import RiftletCore

/// Host-only correlation for one prebinding invocation. These IDs never enter
/// the page command and cannot authorize input, replace a lease or backdate ACK.
public struct CaptureInvocationContext: Equatable, Sendable {
    public let requestID: UUID
    public let armAttemptID: UUID
    public let hostEpoch: UUID

    public init(requestID: UUID = UUID(), armAttemptID: UUID, hostEpoch: UUID) {
        self.requestID = requestID; self.armAttemptID = armAttemptID; self.hostEpoch = hostEpoch
    }
}

/// Native receipt/validation/return events use context.requestID in the opt-in
/// transport log. This later boundary is adapter validation, NOT App publication.
/// Matching target digests alone must never join two separate invocations.
public struct CapturedTargetDiagnostics: Sendable {
    public let context: CaptureInvocationContext
    public let target: TargetLease
    public let targetDigest: String
    public let adapterValidatedUptime: TimeInterval

    init(context: CaptureInvocationContext, target: TargetLease) throws {
        self.context = context; self.target = target
        targetDigest = try NativeCaptureProof.digest(target)
        adapterValidatedUptime = ProcessInfo.processInfo.systemUptime
    }
}
