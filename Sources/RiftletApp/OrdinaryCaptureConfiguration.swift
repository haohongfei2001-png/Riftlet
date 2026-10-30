import Foundation
import RiftletCore
import RiftletAdapters

/// Source-owned review references, never decoded from settings, arguments,
/// page JSON or an old operation. Valid syntax alone is not review approval.
struct OrdinaryAttachmentEvidence: Equatable {
    let sourceRevision: String
    let appSHA256: String
    let evidenceSHA256: String
    let reviewSHA256: String

    var isWellFormed: Bool {
        func hex(_ value: String, count: Int) -> Bool {
            value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        return hex(sourceRevision, count: 40) && [appSHA256, evidenceSHA256, reviewSHA256].allSatisfy { hex($0, count: 64) }
    }
    func matchesBuild(_ other: Self) -> Bool {
        isWellFormed && other.isWellFormed && sourceRevision == other.sourceRevision && appSHA256 == other.appSHA256
    }
}

/// Three independent decisions for the ordinary entry point. Candidate review
/// maps are deliberately not used. No input decision has been granted yet.
struct OrdinaryAttachmentAdmission {
    let input: OrdinaryAttachmentEvidence?
    let start: OrdinaryAttachmentEvidence?
    let completion: OrdinaryAttachmentEvidence?
    static let closed = Self(input: nil, start: nil, completion: nil)

    var allowsInput: Bool { input?.isWellFormed == true }
    var allowsStart: Bool { guard let input, let start else { return false }; return start.matchesBuild(input) }
    var allowsCompletion: Bool { guard let input, let completion else { return false }; return completion.matchesBuild(input) }
    var receiptPolicy: ReceiptPolicy {
        ReceiptPolicy(admittedProfiles: allowsCompletion ? [OrdinarySystemScreenshotScope.admittedCompletionProfileID: .webChat] : [:],
            retrySafeProfiles: [:],
            uploadStartProfiles: allowsStart ? [OrdinarySystemScreenshotScope.admittedUploadStartProfileID: .webChat] : [:])
    }
    var supportText: String {
        guard allowsInput else {
            return "普通启动仅本地收录；真实附加尚待最终 App 端到端验收及独立审查。授权浏览器不会开启上传。"
        }
        return "普通附加范围：Chrome 中文 ChatGPT 普通已有聊天；仅原样系统截图、单帧非交错 RGBA8 PNG，≤8 MiB、≤16,777,216 像素。内置截图及其他来源不在附加范围。开始吞噬\(allowsStart ? "已单独准入" : "未开放")，最终完成\(allowsCompletion ? "已单独准入" : "未开放")；不自动发送消息，不自动重试，不开放未决多附件并行。"
    }
}

enum OrdinaryCaptureConfiguration {
    // A future change needs independently reviewed evidence from the final
    // ordinary App. Neither the candidate's F/H records nor CI can fill this.
    static let admission = OrdinaryAttachmentAdmission.closed
}
