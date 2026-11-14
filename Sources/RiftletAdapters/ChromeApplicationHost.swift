import AppKit

/// The existing ChatGPT route retains its native process session spelling.
struct ChromeHostTarget: Equatable {
    let process: ChromeProcessIdentity
    let route: ChromeClickRoute
}

/// Only the selected tab of the actual foreground Chrome can be bound. Both
/// reads of selection address the same PID. Neither operation activates a tab.
struct ChromeApplicationHost: ApplicationHostAdapter {
    let foreground: () -> ChromeProcessIdentity?
    let selected: (pid_t) throws -> (window: String, tab: String)
    let address: (pid_t, String, String) throws -> String

    static func currentForeground() -> ChromeProcessIdentity? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.google.Chrome",
              let process = ChromeProcessIdentity.read(pid: app.processIdentifier),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == process.pid else { return nil }
        return process
    }

    func freeze() throws -> ChromeHostTarget {
        guard let process = foreground() else { throw WebAdapterError.browserNotFrontmost }
        return try freeze(process)
    }

    private func freeze(_ process: ChromeProcessIdentity) throws -> ChromeHostTarget {
        guard foreground() == process else { throw WebAdapterError.nativeSelectionChanged }
        let tab = try selected(process.pid)
        let route = try route(pid: process.pid, window: tab.window, tab: tab.tab)
        guard try selected(process.pid) == tab, foreground() == process else {
            throw WebAdapterError.nativeSelectionChanged
        }
        return ChromeHostTarget(process: process, route: route)
    }

    func revalidate(_ original: ChromeHostTarget) throws {
        guard try freeze(original.process) == original else { throw WebAdapterError.nativeSelectionChanged }
    }

    private func route(pid: pid_t, window: String, tab: String) throws -> ChromeClickRoute {
        let url = try address(pid, window, tab)
        guard let parts = URLComponents(string: url),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              ["chatgpt.com", "chat.openai.com"].contains(parts.host?.lowercased()) else {
            throw WebAdapterError.pageRejected(.pageRouteUnsupported)
        }
        return try ChromeClickRoute(window: window, tab: tab, url: url)
    }
}
