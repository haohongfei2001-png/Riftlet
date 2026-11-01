import Foundation

/// One ordering domain for every native permission inspection, including future
/// foreground prebinding and original click validation. This stores results,
/// never substitutes a cached grant for an actual OS check.
@MainActor
final class OriginalReceiverPermission {
    struct Request { let session: String; let ordinal: UInt64 }
    struct Resolution { let usable: AutomationPermissionState; let published: Bool }
    private var ordinal: UInt64 = 0
    private var latest: [String: (UInt64, AutomationPermissionState)] = [:]

    func begin(session: String) -> Request {
        ordinal += 1
        return Request(session: session, ordinal: ordinal)
    }
    func resolve(_ request: Request, result: AutomationPermissionState) -> Resolution {
        if let newer = latest[request.session], newer.0 > request.ordinal {
            return Resolution(usable: result == .granted && newer.1 == .granted ? .granted : .unavailable, published: false)
        }
        latest[request.session] = (request.ordinal, result)
        return Resolution(usable: result, published: true)
    }
    func inspect(session: String, gate: AutomationPermissionGate) async -> AutomationPermissionState {
        await inspectResolution(session: session, gate: gate).usable
    }
    func inspectResolution(session: String, gate: AutomationPermissionGate) async -> Resolution {
        let request = begin(session: session)
        return resolve(request, result: await gate.inspect(expectedSession: session))
    }
}
