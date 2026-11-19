import Foundation

/// Research-only observation. The Edge scripting dictionary specifies no content-world
/// isolation. Page observations can never authorize input or act as service receipts.
struct EdgeConversationBinding {
    fileprivate let host: EdgeWindowTab
    fileprivate let surface: ConversationSurfaceAdapter
    fileprivate let id: UUID
    let firstInspection: ConversationSurfaceInspection
}

enum EdgeInspectionError: Error { case unsupportedService, malformedReply, unavailable }

struct EdgeConversationInspection {
    private let host: EdgeApplicationHost
    private let read: (ConversationSurfaceAdapter, ConversationSurfaceAction, UUID, EdgeWindowTab) throws -> ConversationSurfaceInspection

    init() {
        let host = EdgeApplicationHost()
        self.init(host: host) { surface, action, id, target in
            let script = try surface.script(for: action, bindingID: id)
            let quoted = String(decoding: try JSONEncoder().encode(target.address), as: UTF8.self)
            // Pin the native address again inside the exact addressed top-level document
            // before executing even the read-only inspector, including after a redirect.
            let guarded = "location.href === \(quoted) ? (\(script)) : JSON.stringify({status:'changed'})"
            let raw = try EdgeJavaScriptEvent.send(guarded, to: target, using: host)
            guard raw.utf8.count <= 1024,
                  let reply = try? JSONDecoder().decode(ConversationSurfaceInspection.self, from: Data(raw.utf8)) else {
                throw EdgeInspectionError.malformedReply
            }
            return reply
        }
    }

    init(host: EdgeApplicationHost,
         read: @escaping (ConversationSurfaceAdapter, ConversationSurfaceAction, UUID, EdgeWindowTab) throws -> ConversationSurfaceInspection) {
        self.host = host
        self.read = read
    }

    func bind(_ target: EdgeWindowTab) throws -> EdgeConversationBinding {
        try host.revalidate(target)
        guard let url = URL(string: target.address), let service = ConversationSurfaceAdapter(url: url) else {
            throw EdgeInspectionError.unsupportedService
        }
        let id = UUID()
        let result = try read(service, .bind, id, target)
        try host.revalidate(target)
        guard result.status == .bound, result.entry != nil, let count = result.attachmentCount,
              (0...128).contains(count) else { throw EdgeInspectionError.unavailable }
        return EdgeConversationBinding(host: target, surface: service, id: id, firstInspection: result)
    }

    func revalidate(_ binding: EdgeConversationBinding) throws -> ConversationSurfaceInspection {
        try host.revalidate(binding.host)
        let result = try read(binding.surface, .revalidate, binding.id, binding.host)
        try host.revalidate(binding.host)
        guard result.status == .unchanged, result.entry == binding.firstInspection.entry,
              result.attachmentCount == binding.firstInspection.attachmentCount else { throw EdgeInspectionError.unavailable }
        return result
    }

    func release(_ binding: EdgeConversationBinding) throws {
        // If the user moved, the document expires its short-lived binding locally.
        try host.revalidate(binding.host)
        _ = try read(binding.surface, .release, binding.id, binding.host)
    }
}
