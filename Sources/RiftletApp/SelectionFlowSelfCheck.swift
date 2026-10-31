import Foundation
import RiftletCore

/// Pure host state checks for the packaged first-use command. No OS permission
/// query, browser transport, UI, or real asset is used.
@MainActor
enum SelectionFlowSelfCheck {
    static func run() async throws {
        let first = PermissionBrowserIdentity(pid: 11, launched: Date(timeIntervalSince1970: 1))
        let second = PermissionBrowserIdentity(pid: 22, launched: Date(timeIntervalSince1970: 2))
        guard PermissionBrowserIdentity.select([first, second], foregroundPID: 22, expectedSession: nil) == second,
              PermissionBrowserIdentity.select([first, second], foregroundPID: 11, expectedSession: second.session) == second,
              PermissionBrowserIdentity.select([first, second], foregroundPID: nil, expectedSession: nil) == nil,
              PermissionBrowserIdentity.select([first, second], foregroundPID: 22, expectedSession: "22:1.0") == nil else {
            throw RiftletError.invalidTransition
        }
        let epoch = UUID(), now = ProcessInfo.processInfo.systemUptime
        let target = TargetLease(adapterID: "fixture", surface: .webChat, applicationID: "fixture",
            sessionID: "original", windowID: "1", tabID: "1", documentID: "doc", composerID: "editor", draftGeneration: "draft")
        let token = AcceptedSelection(assetID: UUID(), target: target, hostEpoch: epoch,
            acknowledgedUptime: now - 2, eventUptime: now - 1, acceptedUptime: now,
            visibilityRevision: 0, deadlineUptime: now + 30)
        let authority = SelectionAuthority()
        guard authority.insert(token, now: now), authority.permits(token, epoch: epoch, foregroundSession: "original",
            hidden: false, terminating: false, now: now) else { throw RiftletError.invalidTransition }
        authority.cancel()
        guard !token.isValid(at: now) else { throw RiftletError.invalidTransition }

        let queue = SelectionSubmissionQueue()
        var order: [Int] = []
        var release: CheckedContinuation<Void, Never>?
        queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in
            order.append(1)
            await withCheckedContinuation { release = $0 }
            order.append(2)
        }
        let removed = UUID()
        queue.enqueue(selectionID: removed, deadline: nil, cancelled: {}) { _ in order.append(99) }
        queue.enqueue(selectionID: UUID(), deadline: nil, cancelled: {}) { _ in order.append(3) }
        queue.cancel(selectionIDs: [removed])
        for _ in 0..<1000 where release == nil { await Task.yield() }
        guard order == [1], let continuation = release else { queue.stop(); throw RiftletError.invalidTransition }
        continuation.resume()
        for _ in 0..<1000 where order.count < 3 { await Task.yield() }
        guard order == [1, 2, 3] else { throw RiftletError.invalidTransition }
    }
}
