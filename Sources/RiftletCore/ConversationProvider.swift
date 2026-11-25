import Foundation

/// A matching web address nominates a provider. Only its original editor and
/// upload control can authorize a file input.
public enum ConversationProvider: String, CaseIterable, Sendable {
    case chatgpt, claude, gemini, copilot, perplexity, grok, poe, deepseek, kimi
    case qianwen, qwen, doubao, yuanbao, qingyan, spark, meta, mistral, wenxin, zai

    public var adapterID: String { rawValue + "-web" }

    public init?(adapterID: String) {
        guard adapterID.hasSuffix("-web") else { return nil }
        self.init(rawValue: String(adapterID.dropLast(4)))
    }

    public var origins: [String] {
        switch self {
        case .chatgpt: return ["https://chatgpt.com", "https://chat.openai.com"]
        case .claude: return ["https://claude.ai"]
        case .gemini: return ["https://gemini.google.com"]
        case .copilot: return ["https://copilot.microsoft.com", "https://copilot.com"]
        case .perplexity: return ["https://www.perplexity.ai", "https://perplexity.ai"]
        case .grok: return ["https://grok.com"]
        case .poe: return ["https://poe.com"]
        case .deepseek: return ["https://chat.deepseek.com"]
        case .kimi: return ["https://www.kimi.com", "https://kimi.com"]
        case .qianwen: return ["https://www.qianwen.com", "https://qianwen.com"]
        case .qwen: return ["https://chat.qwen.ai"]
        case .doubao: return ["https://www.doubao.com"]
        case .yuanbao: return ["https://yuanbao.tencent.com"]
        case .qingyan: return ["https://chatglm.cn"]
        case .spark: return ["https://xinghuo.xfyun.cn"]
        case .meta: return ["https://www.meta.ai", "https://meta.ai"]
        case .mistral: return ["https://chat.mistral.ai"]
        case .wenxin: return ["https://wenxin.baidu.com"]
        case .zai: return ["https://chat.z.ai"]
        }
    }

    /// Patterns apply only to the path. A provider still witnesses the complete
    /// draft route, including navigation within a single page.
    public var routes: [String] {
        let id = "[A-Za-z0-9_-]+"
        switch self {
        case .chatgpt: return ["^/.*$"] // The existing ChatGPT program checks the draft surface.
        case .claude: return ["^/(?:new|chat/\(id))?/?$"]
        case .gemini: return ["^/(?:u/[0-9]+/)?app(?:/\(id))?/?$", "^/$"]
        case .copilot: return ["^/(?:chats/\(id)|conversations/\(id))?/?$"]
        case .perplexity: return ["^/(?:search(?:/\(id))?)?/?$"]
        case .grok: return ["^/(?:c/\(id)|chat/\(id))?/?$"]
        case .poe: return ["^/(?:new|chat/\(id))?/?$", "^/[A-Z][A-Za-z0-9_.-]*/?$"]
        case .deepseek: return ["^/(?:a/chat(?:/s/\(id))?)?/?$"]
        case .kimi: return ["^/(?:chat(?:/\(id))?)?/?$"]
        case .qianwen: return ["^/(?:chat(?:/\(id))?)?/?$"]
        case .qwen: return ["^/(?:c/\(id))?/?$"]
        case .doubao: return ["^/chat(?:/\(id))?/?$"]
        case .yuanbao: return ["^/(?:chat(?:/\(id)){0,2})?/?$"]
        case .qingyan: return ["^/(?:main/(?:alltoolsdetail|detail)(?:/\(id))?)?/?$"]
        case .spark: return ["^/(?:desk(?:/\(id))?)?/?$"]
        case .meta: return ["^/(?:prompt(?:/\(id))?|chat(?:/\(id))?)?/?$"]
        case .mistral: return ["^/(?:work(?:/\(id))?|chat(?:/\(id))?)?/?$"]
        case .wenxin: return ["^/(?:chat(?:/\(id))?)?/?$"]
        case .zai: return ["^/(?:c/\(id))?/?$"]
        }
    }

    public static func matching(url: String) -> Self? {
        guard let parts = URLComponents(string: url), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
              let host = parts.percentEncodedHost?.lowercased(),
              let provider = allCases.first(where: { $0.origins.contains("https://" + host) }) else { return nil }
        let path = parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath
        return provider.routes.contains { path.range(of: $0, options: .regularExpression) != nil } ? provider : nil
    }
}
