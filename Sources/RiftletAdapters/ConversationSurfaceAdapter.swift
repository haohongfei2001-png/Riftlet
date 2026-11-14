import Foundation

public enum ConversationSurfaceService: String, CaseIterable, Sendable {
    case chatGPT, claude, gemini, perplexity, poe

    // Candidate web surface signatures for read-only inspection. A UI signature
    // is deliberately separate from a transport, receipt profile or release claim.
    fileprivate var profile: ConversationSurfaceProfile {
        switch self {
        case .chatGPT:
            return .init(hosts: ["chatgpt.com", "chat.openai.com"],
                         route: #"^/(?:c/[a-zA-Z0-9-]+/?)?$"#,
                         editor: "#prompt-textarea",
                         container: "[data-composer-placement],[data-chatgpt-composer],[data-testid='composer'],form",
                         entry: "button[data-testid='composer-plus-btn'],button[data-testid='composer-plus-button']",
                         attachment: "[data-testid='attachment-preview'],[data-testid='file-thumbnail']")
        case .claude:
            return .init(hosts: ["claude.ai"], route: #"^/(?:new|chat/[a-zA-Z0-9-]+)/?$"#,
                         editor: "[data-testid='chat-input'][contenteditable],.ProseMirror[contenteditable]",
                         container: "[data-testid='chat-input-container'],fieldset,form",
                         entry: "button[data-testid='add-attachment'],button[aria-label='Add files or photos']",
                         attachment: "[data-testid='file-thumbnail'],[data-testid='attachment-preview']")
        case .gemini:
            return .init(hosts: ["gemini.google.com"], route: #"^/(?:u/[0-9]+/)?app(?:/[a-zA-Z0-9_-]+)?/?$"#,
                         editor: "rich-textarea [contenteditable]",
                         container: "input-area-v2,input-area",
                         entry: "button.upload-card-button,button[aria-label='Upload files']",
                         attachment: "uploader-file-preview,file-preview")
        case .perplexity:
            return .init(hosts: ["perplexity.ai", "www.perplexity.ai"],
                         route: #"^/(?:search/[a-zA-Z0-9_.-]+/?)?$"#,
                         editor: "#ask-input,[data-testid='ask-input']",
                         container: "[data-testid='query-box'],form",
                         entry: "button[data-testid='attach-file'],button[aria-label='Attach files']",
                         attachment: "[data-testid='attached-file'],[data-testid='file-pill']")
        case .poe:
            return .init(hosts: ["poe.com"], route: #"^/(?:chat/[a-zA-Z0-9_-]+/?)?$"#,
                         editor: "textarea[class*='GrowingTextArea_textArea'],textarea[data-testid='chat-input']",
                         container: "[class*='ChatMessageInputContainer_inputContainer'],[data-testid='chat-input-container']",
                         entry: "button[class*='ChatMessageInputView_attachButton'],button[aria-label='Add attachment']",
                         attachment: "[class*='AttachmentPill_'],[data-testid='attachment-preview']")
        }
    }
}

private struct ConversationSurfaceProfile: Encodable {
    let hosts: [String]
    let route: String
    let editor: String
    let container: String
    let entry: String
    let attachment: String
}

public enum ConversationSurfaceAction: String, Sendable { case bind, revalidate, release }
public enum ConversationSurfaceStatus: String, Codable, Sendable {
    case bound, unchanged, released, unsupportedRoute, unavailable, ambiguous, changed, expired, capacity
}

/// Only a candidate attachment button associated with the original composer.
/// A missing button can also be an unrecognized or dynamically mounted entry.
public enum ConversationSurfaceEntry: String, Codable, Sendable { case missing, button, ambiguous }

public struct ConversationSurfaceInspection: Decodable, Sendable {
    public let status: ConversationSurfaceStatus
    public let entry: ConversationSurfaceEntry?
    /// Number of recognized attachment nodes; the service may have other attachment presentations.
    public let attachmentCount: Int?
}

public struct ConversationSurfaceAdapter: Sendable {
    public let service: ConversationSurfaceService
    private let address: String

    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443, let host = parts.host?.lowercased(),
              let site = ConversationSurfaceService.allCases.first(where: {
                  $0.profile.hosts.contains(host)
                  && (parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath)
                      .range(of: $0.profile.route, options: .regularExpression) != nil
              }) else { return nil }
        service = site
        address = url.absoluteURL.absoluteString
    }

    // The standalone WebKit regression uses the same bundled program's source
    // file with identical command construction, without a SwiftPM application.
    func script(for action: ConversationSurfaceAction, bindingID: UUID, program: String) throws -> String {
        let profileJSON = String(decoding: try JSONEncoder().encode(service.profile), as: UTF8.self)
        let addressJSON = String(decoding: try JSONEncoder().encode(address), as: UTF8.self)
        return "(\(program))(\(profileJSON), \(addressJSON), '\(service.rawValue)', '\(action.rawValue)', '\(bindingID.uuidString)')"
    }
}
