import Foundation

/// Orders the publication of real permission inspections, not permission
/// authority itself. Every caller still performs its own native check. A result
/// from a previous foreground/host generation cannot revoke a newer target or
/// lend its grant to the caller after that caller's context has changed.
struct AutomationPermissionPublication {
    struct Request: Equatable {
        fileprivate let ordinal: UInt64
        let hostEpoch: UUID
        let foregroundSession: String?
        let receiverSession: String?
    }

    enum Resolution: String {
        case publish, supersededGrant, superseded, staleContext

        var mayUseResult: Bool { self == .publish || self == .supersededGrant }
    }

    enum TargetDisposition: Equatable {
        case publish, retainExisting, clear, staleEpoch
    }

    /// A superseded permission check or cooperatively interrupted read-only
    /// capture cannot prove that the previously acknowledged page became invalid. In contrast,
    /// an actual failed capture or a changed foreground must still revoke it.
    /// The caller supplies only the original scheduler completion and sessions;
    /// this function never creates an ACK or changes its event timestamp.
    static func targetDisposition(epochAccepted: Bool, captureAttempted: Bool,
                                  returnedSession: String?, existingSession: String?,
                                  existingEpochMatches: Bool, foregroundSession: String?,
                                  captureSuperseded: Bool = false) -> TargetDisposition {
        guard epochAccepted else { return .staleEpoch }
        if !captureSuperseded, captureAttempted, let returnedSession, returnedSession == foregroundSession { return .publish }
        guard (!captureAttempted || captureSuperseded), returnedSession == nil, existingEpochMatches,
              let foregroundSession, existingSession == foregroundSession else { return .clear }
        return .retainExisting
    }

    private var nextOrdinal: UInt64 = 0
    private var latest: (request: Request, state: AutomationPermissionState)?

    mutating func begin(hostEpoch: UUID, foregroundSession: String?, receiverSession: String?) -> Request {
        let request = Request(ordinal: nextOrdinal, hostEpoch: hostEpoch,
                              foregroundSession: foregroundSession, receiverSession: receiverSession)
        nextOrdinal += 1
        return request
    }

    mutating func resolve(_ request: Request, state: AutomationPermissionState,
                          hostEpoch: UUID, foregroundSession: String?, terminating: Bool) -> Resolution {
        guard !terminating, request.hostEpoch == hostEpoch,
              request.foregroundSession == foregroundSession,
              // A check explicitly addressing another Chrome process does not
              // describe the currently frontmost one. Background/settings-only
              // checks with no foreground Chrome retain their status use.
              foregroundSession == nil || request.receiverSession == foregroundSession else { return .staleContext }
        if let latest, latest.request.ordinal > request.ordinal {
            // Two independently completed grants in the same context need not
            // cancel a valid click merely because another status check finished
            // first. This does not reuse the newer grant: this request itself
            // must have returned granted from the native checker.
            if latest.request.hostEpoch == request.hostEpoch,
               latest.request.foregroundSession == request.foregroundSession,
               latest.request.receiverSession == request.receiverSession,
               latest.state == .granted, state == .granted { return .supersededGrant }
            return .superseded
        }
        latest = (request, state)
        return .publish
    }
}
