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

/// Source-qualified capabilities for the one ordinary product entry point.
/// Historical evidence-shaped configurations remain fail closed; candidate
/// review maps and arbitrary SHA strings cannot grant the product authority.
struct OrdinaryAttachmentAdmission {
    let input: OrdinaryAttachmentEvidence?
    let start: OrdinaryAttachmentEvidence?
    let completion: OrdinaryAttachmentEvidence?
    enum Purpose { case production, internalAcceptance }
    let purpose: Purpose
    private let internalStart: Bool
    private let internalCompletion: Bool
    private let internalCurrentDrafts: Bool
    let productOrigins: Set<AssetOrigin>
    var usesUnifiedProduct: Bool { !productOrigins.isEmpty }
    init(input: OrdinaryAttachmentEvidence?, start: OrdinaryAttachmentEvidence?, completion: OrdinaryAttachmentEvidence?) {
        self.input = input; self.start = start; self.completion = completion
        purpose = .production; internalStart = false; internalCompletion = false; internalCurrentDrafts = false
        productOrigins = []
    }
    private init(internalStart: Bool, internalCompletion: Bool, currentDrafts: Bool) {
        input = nil; start = nil; completion = nil
        purpose = .internalAcceptance
        self.internalStart = internalStart; self.internalCompletion = internalCompletion
        internalCurrentDrafts = currentDrafts
        productOrigins = []
    }
    /// The single product's source-qualified implementation. This does not
    /// claim release certification: the exact source/artefact still requires
    /// independent admission and real platform acceptance. No runtime option,
    /// page response or stored operation can select or expand these sources.
    private init(productOrigins: Set<AssetOrigin>) {
        input = nil; start = nil; completion = nil; purpose = .production
        internalStart = false; internalCompletion = false; internalCurrentDrafts = false
        self.productOrigins = productOrigins
    }
    static let unifiedProduct = Self(productOrigins: [.systemScreenshot, .applicationScreenshot])
    static let closed = Self(input: nil, start: nil, completion: nil)
    // Explicit test authorization, never synthesized from evidence hashes. This
    // constructor cannot be reached by arguments, settings or stored operations.
    static func internalAcceptance(start: Bool = true, completion: Bool = true, currentDrafts: Bool = false) -> Self {
        Self(internalStart: start, internalCompletion: completion, currentDrafts: currentDrafts)
    }
    // Empty until an independent reviewer admits exact final production evidence.
    // Well-formed arbitrary SHA strings are deliberately insufficient.
    private static let reviewedProductionEvidence: [OrdinaryAttachmentEvidence] = []
    private func approved(_ evidence: OrdinaryAttachmentEvidence?) -> Bool {
        guard let evidence, evidence.isWellFormed else { return false }
        return Self.reviewedProductionEvidence.contains(evidence)
    }
    var allowsInput: Bool { usesUnifiedProduct || purpose == .internalAcceptance || approved(input) }
    var allowsStart: Bool {
        if usesUnifiedProduct { return true }
        if purpose == .internalAcceptance { return internalStart }
        guard approved(input), approved(start), let input, let start else { return false }
        return start.matchesBuild(input)
    }
    var allowsCompletion: Bool {
        if usesUnifiedProduct { return true }
        if purpose == .internalAcceptance { return internalCompletion }
        guard approved(input), approved(completion), let input, let completion else { return false }
        return completion.matchesBuild(input)
    }
    var targetScope: SystemScreenshotAdmissionScope {
        usesUnifiedProduct ? .productSystem : (internalCurrentDrafts ? .ordinaryCurrentDraftInternal : .ordinary)
    }
    var observationProfile: ObservationProfile {
        usesUnifiedProduct ? OrdinaryProductScreenshotScope.systemProfile :
            (internalCurrentDrafts ? OrdinaryCurrentDraftInternalScope.profile : OrdinarySystemScreenshotScope.profile)
    }
    var receiptPolicy: ReceiptPolicy {
        // The same internal root retains prior ordinary registrations. Their
        // original, exact registered observations remain admissible on restart;
        // new dispatches use only targetScope and cannot manufacture old keys.
        var starts: [String: TargetSurface] = [:]
        var completions: [String: TargetSurface] = [:]
        if usesUnifiedProduct {
            var origins: [String: Set<AssetOrigin>] = [:]
            var continuations: [String: TargetSurface] = [:]
            for scope in [SystemScreenshotAdmissionScope.productSystem, .productApplication] where productOrigins.contains(scope.origin) {
                let profile = scope.admittedProfile
                if let start = profile.uploadStartProfileID {
                    starts[start] = .webChat; origins[start] = [scope.origin]
                }
                completions[profile.profileID] = .webChat; origins[profile.profileID] = [scope.origin]
                if let continuation = profile.continuationProfileID {
                    continuations[continuation] = .webChat; origins[continuation] = [scope.origin]
                }
            }
            // Old scopes may have registered input-only operations without
            // start/completion approval. Observe their original journal, but do
            // not promote them merely because a new product is now enabled.
            return ReceiptPolicy(admittedProfiles: completions, uploadStartProfiles: starts,
                continuationProfiles: continuations, profileOrigins: origins,
                requiredCompletionEvidenceProfiles: Set(completions.keys),
                requiredInputIsolationProfiles: Set(continuations.keys))
        }
        if allowsStart { starts[OrdinarySystemScreenshotScope.admittedUploadStartProfileID] = .webChat }
        if allowsCompletion { completions[OrdinarySystemScreenshotScope.admittedCompletionProfileID] = .webChat }
        if internalCurrentDrafts {
            if allowsStart { starts[OrdinaryCurrentDraftInternalScope.admittedUploadStartProfileID] = .webChat }
            if allowsCompletion { completions[OrdinaryCurrentDraftInternalScope.admittedCompletionProfileID] = .webChat }
        }
        return ReceiptPolicy(admittedProfiles: completions, retrySafeProfiles: [:], uploadStartProfiles: starts)
    }
    var supportText: String {
        guard allowsInput else {
            return "普通启动仅本地收录；真实附加尚待最终 App 端到端验收及独立审查。授权浏览器不会开启上传。"
        }
        if usesUnifiedProduct {
            return "Chrome 中文 ChatGPT 普通新聊天及已有聊天；支持原样系统截图和内置截图。PNG 须为单帧非交错 RGBA8，≤8 MiB、≤16,777,216 像素。真实开始后收起，独立核对最终完成；确认原文件已被独立请求接收时可继续追加。无法确认时保留记录并说明原因，不重复输入、不自动发送。上传后安全重试仍需独立失败证明。"
        }
        let scope = purpose == .internalAcceptance ? "内部普通入口验收（非生产准入）" : "普通附加范围"
        let chats = internalCurrentDrafts ? "已识别业务身份的普通新聊天及已有聊天（含本地身份）" : "普通已有聊天"
        return "\(scope)：Chrome 中文 ChatGPT \(chats)；仅原样系统截图、单帧非交错 RGBA8 PNG，≤8 MiB、≤16,777,216 像素。内置截图及其他来源不在附加范围。开始吞噬\(allowsStart ? (purpose == .internalAcceptance ? "仅测试授权" : "已单独准入") : "未开放")，最终完成\(allowsCompletion ? (purpose == .internalAcceptance ? "仅测试授权" : "已单独准入") : "未开放")；不自动发送消息，不自动重试，不开放未决多附件并行。"
    }
}

enum OrdinaryCaptureConfiguration {
    // One product implementation; the compiler-only acceptance harness retains
    // its isolated root and historical scope. Neither path asserts release or
    // real-page certification from build success or candidate F/H evidence.
    #if RIFTLET_ORDINARY_ACCEPTANCE
    static let isInternalAcceptance = true
    static let admission = OrdinaryAttachmentAdmission.internalAcceptance(currentDrafts: true)
    static let dataDirectoryName = "Riftlet-Ordinary-Acceptance"
    static let menuTitle = "Riftlet ORDINARY TEST"
    #else
    static let isInternalAcceptance = false
    static let admission = OrdinaryAttachmentAdmission.unifiedProduct
    static let dataDirectoryName = "Riftlet"
    static let menuTitle = "Riftlet"
    #endif
}
