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
    enum Purpose { case production, internalAcceptance }
    let purpose: Purpose
    private let internalStart: Bool
    private let internalCompletion: Bool
    init(input: OrdinaryAttachmentEvidence?, start: OrdinaryAttachmentEvidence?, completion: OrdinaryAttachmentEvidence?) {
        self.input = input; self.start = start; self.completion = completion
        purpose = .production; internalStart = false; internalCompletion = false
    }
    private init(internalStart: Bool, internalCompletion: Bool) {
        input = nil; start = nil; completion = nil
        purpose = .internalAcceptance
        self.internalStart = internalStart; self.internalCompletion = internalCompletion
    }
    static let closed = Self(input: nil, start: nil, completion: nil)
    // Explicit test authorization, never synthesized from evidence hashes. This
    // constructor cannot be reached by arguments, settings or stored operations.
    static func internalAcceptance(start: Bool = true, completion: Bool = true) -> Self {
        Self(internalStart: start, internalCompletion: completion)
    }
    // Empty until an independent reviewer admits exact final production evidence.
    // Well-formed arbitrary SHA strings are deliberately insufficient.
    private static let reviewedProductionEvidence: [OrdinaryAttachmentEvidence] = []
    private func approved(_ evidence: OrdinaryAttachmentEvidence?) -> Bool {
        guard let evidence, evidence.isWellFormed else { return false }
        return Self.reviewedProductionEvidence.contains(evidence)
    }
    var allowsInput: Bool { purpose == .internalAcceptance || approved(input) }
    var allowsStart: Bool {
        if purpose == .internalAcceptance { return internalStart }
        guard approved(input), approved(start), let input, let start else { return false }
        return start.matchesBuild(input)
    }
    var allowsCompletion: Bool {
        if purpose == .internalAcceptance { return internalCompletion }
        guard approved(input), approved(completion), let input, let completion else { return false }
        return completion.matchesBuild(input)
    }
    var receiptPolicy: ReceiptPolicy {
        ReceiptPolicy(admittedProfiles: allowsCompletion ? [OrdinarySystemScreenshotScope.admittedCompletionProfileID: .webChat] : [:],
            retrySafeProfiles: [:],
            uploadStartProfiles: allowsStart ? [OrdinarySystemScreenshotScope.admittedUploadStartProfileID: .webChat] : [:])
    }
    var supportText: String {
        guard allowsInput else {
            return "普通启动仅本地收录；真实附加尚待最终 App 端到端验收及独立审查。授权浏览器不会开启上传。"
        }
        let scope = purpose == .internalAcceptance ? "内部普通入口验收（非生产准入）" : "普通附加范围"
        return "\(scope)：Chrome 中文 ChatGPT 普通已有聊天；仅原样系统截图、单帧非交错 RGBA8 PNG，≤8 MiB、≤16,777,216 像素。内置截图及其他来源不在附加范围。开始吞噬\(allowsStart ? (purpose == .internalAcceptance ? "仅测试授权" : "已单独准入") : "未开放")，最终完成\(allowsCompletion ? (purpose == .internalAcceptance ? "仅测试授权" : "已单独准入") : "未开放")；不自动发送消息，不自动重试，不开放未决多附件并行。"
    }
}

enum OrdinaryCaptureConfiguration {
    // A future change needs independently reviewed evidence from the final
    // ordinary App. Neither the candidate's F/H records nor CI can fill this.
    #if RIFTLET_ORDINARY_ACCEPTANCE
    static let isInternalAcceptance = true
    static let admission = OrdinaryAttachmentAdmission.internalAcceptance()
    static let dataDirectoryName = "Riftlet-Ordinary-Acceptance"
    static let menuTitle = "Riftlet ORDINARY TEST"
    #else
    static let isInternalAcceptance = false
    static let admission = OrdinaryAttachmentAdmission.closed
    static let dataDirectoryName = "Riftlet"
    static let menuTitle = "Riftlet"
    #endif
}
