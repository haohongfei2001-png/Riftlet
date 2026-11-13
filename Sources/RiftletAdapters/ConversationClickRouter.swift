import AppKit
import RiftletCore

/// Only routes admitted for ordinary clicks are registered here. Development
/// probes for other hosts cannot accidentally become screenshot destinations.
public protocol ConversationClickAdapter: Sendable {
    @MainActor var applicationID: String { get }
    @MainActor func targetForClick() throws -> Task<TargetLease, Error>
}

extension WebAttachmentAdapter: ConversationClickAdapter {
    public nonisolated var applicationID: String { "com.google.Chrome" }
}

@MainActor public struct ConversationClickRouter {
    private let adapters: [any ConversationClickAdapter]
    private let foreground: () -> String?

    public init(adapters: [any ConversationClickAdapter]) {
        self.init(adapters: adapters, foreground: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier })
    }

    init(adapters: [any ConversationClickAdapter], foreground: @escaping () -> String?) {
        self.adapters = adapters
        self.foreground = foreground
    }

    /// Invoke the chosen adapter synchronously, while the press still owns the
    /// event. It must capture the exact process/window/tab/document/editor now.
    public func targetForClick() throws -> Task<TargetLease, Error> {
        guard let host = foreground() else { throw WebAdapterError.browserNotFrontmost }
        let candidates = adapters.filter { $0.applicationID == host }
        guard candidates.count == 1 else { throw WebAdapterError.browserNotFrontmost }
        return try candidates[0].targetForClick()
    }
}
