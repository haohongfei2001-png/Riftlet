import Foundation

public enum ConversationSurfacePageProgram {
    public static func load() throws -> String {
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("Riftlet_RiftletAdapters.bundle"),
                  let bundle = Bundle(url: resourceURL) else { throw WebAdapterError.programUnavailable }
            resources = bundle
        } else {
            resources = Bundle.module
        }
        guard let url = resources.url(forResource: "ConversationSurfaceProbe", withExtension: "js") else {
            throw WebAdapterError.programUnavailable
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

extension ConversationSurfaceAdapter {
    /// Evaluate against a previously pinned top-level document. A page-world
    /// host can use results only as untrusted diagnostics. A binding ID belongs to one click. The return
    /// value is JSON containing only enums and a count, never draft data.
    public func script(for action: ConversationSurfaceAction, bindingID: UUID) throws -> String {
        try script(for: action, bindingID: bindingID, program: ConversationSurfacePageProgram.load())
    }
}
