import Foundation
import CryptoKit
import RiftletCore

/// Validates a complete capture reply against its original native context before
/// tracing native arrival. This is NOT click authorization or an ACK mailbox:
/// App publication/host epoch and final page validation remain separate gates.
enum NativeCaptureProof {
    static func digest(_ data: Data, session: String, window: String, tab: String,
                       applicationID: String = AttachmentBrowser.chrome.rawValue,
                       expectedProvider: ConversationProvider = .chatgpt) throws -> String {
        try digest(validatedTarget(data, session: session, window: window, tab: tab,
                                   applicationID: applicationID, expectedProvider: expectedProvider))
    }

    static func validatedTarget(_ data: Data, session: String, window: String, tab: String,
                                applicationID: String, expectedProvider: ConversationProvider) throws -> TargetLease {
        guard data.count <= ObservationDecoder.maximumPayloadBytes,
              let target = try? JSONDecoder().decode(TargetLease.self, from: data),
              matchesProvider(target, expectedProvider), target.surface == .webChat,
              let browser = AttachmentBrowser(rawValue: applicationID), browser.acceptsNativeTab(tab),
              target.applicationID == applicationID, target.sessionID == session, target.windowID == window, target.tabID == tab,
              !target.documentID.isEmpty, !target.composerID.isEmpty, !target.draftGeneration.isEmpty else {
            throw WebAdapterError.invalidTarget
        }
        return target
    }

    static func matchesProvider(_ target: TargetLease, _ expected: ConversationProvider) -> Bool {
        guard target.adapterID == expected.adapterID else { return false }
        if expected == .chatgpt { return true }
        guard let draft = target.logicalDraftIdentity else { return false }
        return target.historyConversationID == nil && draft.isRecognized &&
            draft.profileID == "conversation-composer-20261125-v1" && draft.id == expected.rawValue + ":" + target.draftGeneration
    }

    static func pinnedTarget(_ data: Data, expected: TargetLease, pinID: UUID) throws -> TargetLease {
        guard data.count <= ObservationDecoder.maximumPayloadBytes, expected.clickBindingID == nil,
              let returned = try? JSONDecoder().decode(TargetLease.self, from: data) else { throw WebAdapterError.invalidReply }
        let pinned = TargetLease(adapterID: expected.adapterID, surface: expected.surface,
            applicationID: expected.applicationID, sessionID: expected.sessionID, windowID: expected.windowID,
            tabID: expected.tabID, documentID: expected.documentID, composerID: expected.composerID,
            draftGeneration: expected.draftGeneration, logicalDraftIdentity: expected.logicalDraftIdentity,
            clickBindingID: pinID, historyConversationID: expected.historyConversationID)
        guard returned == pinned else { throw WebAdapterError.invalidTarget }
        return returned
    }

    static func digest(_ target: TargetLease) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(target)).map { String(format: "%02x", $0) }.joined()
    }
}
