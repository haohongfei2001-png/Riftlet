import Foundation
import RiftletCore

/// Main-actor owned by the browser executor. Pending transport is never stored
/// here. Each entry already contains the browser's full document and editor ACK.
struct PreClickLeasePool<Destination> {
    struct Entry {
        let arm: ArmedTarget
        let destination: Destination
        var preparationStarted: TimeInterval
    }

    static var capacity: Int { 2 }
    private var entries: [Entry] = []
    private var lastPress: TimeInterval = -.infinity
    var count: Int { entries.count }
    var armedEntries: [Entry] { entries }
    var nextRenewalUptime: TimeInterval? { entries.map(\.preparationStarted).min().map { $0 + 240 } }

    /// The browser renewed this exact live object. Keep the original ACK that
    /// precedes the press. A later reply cannot reinsert a frozen or expired ticket.
    mutating func renew(_ target: TargetLease, epoch: UUID, requested: TimeInterval, received: TimeInterval) -> Bool {
        guard let index = entries.firstIndex(where: { $0.arm.target == target && $0.arm.hostSession == epoch }),
              requested.isFinite, received.isFinite, requested >= entries[index].preparationStarted,
              received >= requested, received < entries[index].preparationStarted + 540 else { return false }
        entries[index].preparationStarted = requested
        return true
    }

    mutating func remove(_ target: TargetLease) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.arm.target == target }) else { return nil }
        return entries.remove(at: index)
    }

    mutating func removeAll() -> [Entry] {
        defer { entries.removeAll() }
        return entries
    }

    /// Keep two independent capabilities on one draft so two natural presses
    /// need not serialize on another renderer round trip.
    mutating func acknowledge(_ entry: Entry) -> [Entry] {
        guard entry.arm.target.clickBindingID != nil, entry.preparationStarted.isFinite,
              entry.arm.acknowledgedUptime.isFinite, entry.arm.acknowledgedUptime >= entry.preparationStarted
        else { return [entry] }
        if entries.contains(where: { $0.arm.target.clickBindingID == entry.arm.target.clickBindingID }) { return [] }
        var retired: [Entry] = []
        if let prior = entries.last,
           prior.arm.hostSession != entry.arm.hostSession ||
            !Self.samePreparedDraft(prior.arm.target, entry.arm.target) {
            retired = removeAll()
        }
        if entries.count == Self.capacity { retired.append(entries.removeFirst()) }
        entries.append(entry)
        return retired
    }

    // Both ACKs came from actual receiver capture. The optional business ID
    // used by legacy continuation is absent on normal new chats.
    private static func samePreparedDraft(_ left: TargetLease, _ right: TargetLease) -> Bool {
        left.adapterID == right.adapterID && left.surface == right.surface &&
        left.applicationID == right.applicationID && left.sessionID == right.sessionID &&
        left.windowID == right.windowID && left.tabID == right.tabID &&
        left.documentID == right.documentID && left.composerID == right.composerID &&
        left.draftGeneration == right.draftGeneration && left.logicalDraftIdentity == right.logicalDraftIdentity &&
        left.historyConversationID == right.historyConversationID
    }

    mutating func freeze(press: TimeInterval, now: TimeInterval, epoch: UUID,
                         session: String, window: String, tab: String) -> Entry? {
        guard press.isFinite, now.isFinite, press <= now, press > lastPress else { return nil }
        // An old callback can never spend the other ticket for this same press.
        lastPress = press
        guard let index = entries.lastIndex(where: { entry in
            let arm = entry.arm
            // Browser lifetime starts later, at captureTarget, and lasts ten
            // minutes. Leave a full minute for an already frozen selection.
            return now < entry.preparationStarted + 540 &&
                arm.target.windowID == window && arm.target.tabID == tab &&
                arm.freeze(eventUptime: press, nowUptime: now, hostSession: epoch, foregroundSession: session) != nil
        }) else { return nil }
        return entries.remove(at: index)
    }
}

/// A frozen ticket may enroll one exact durable invocation. A lost transport
/// reply cannot grant a second begin or commit. Reads remain independent.
struct FrozenAttachmentInvocation {
    private var owner: ObservationIdentity?
    private var invocationID: UUID?
    private var enteredCommit = false
    var isUnspent: Bool { owner == nil }

    mutating func admits(_ command: WebBridgeCommand, for target: TargetLease) -> Bool {
        guard let identity = command.identity, identity.target == target, let invocation = command.invocationID else { return false }
        if command.action == .begin {
            guard owner == nil else { return false }
            owner = identity
            invocationID = invocation
            return true
        }
        guard owner == identity, invocationID == invocation else { return false }
        switch command.action {
        case .chunk, .discard: return !enteredCommit
        case .commit:
            guard !enteredCommit else { return false }
            enteredCommit = true
            return true
        default: return false
        }
    }
}
