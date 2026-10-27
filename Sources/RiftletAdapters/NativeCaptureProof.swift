import Foundation
import CryptoKit
import RiftletCore

/// Validates a complete capture reply against its original native context before
/// tracing native arrival. This is NOT click authorization or an ACK mailbox:
/// App publication/host epoch and final page validation remain separate gates.
enum NativeCaptureProof {
    static func digest(_ data: Data, session: String, window: String, tab: String) throws -> String {
        guard data.count <= ObservationDecoder.maximumPayloadBytes,
              let target = try? JSONDecoder().decode(TargetLease.self, from: data),
              target.adapterID == "chatgpt-web", target.surface == .webChat,
              target.applicationID == "com.google.Chrome", target.sessionID == session,
              target.windowID == window, target.tabID == tab,
              !target.documentID.isEmpty, !target.composerID.isEmpty, !target.draftGeneration.isEmpty else {
            throw WebAdapterError.invalidTarget
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(target)).map { String(format: "%02x", $0) }.joined()
    }
}
