import AppKit
import Foundation
import RiftletCore

/// Native transport only; it contains no ChatGPT selectors or completion rules.
/// A real reviewed page program is required. This executor never activates Chrome.
@MainActor
public final class ChromeAppleEventsExecutor: WebBridgeExecutor {
    // NSAppleScript may execute off the main thread, but execution must be
    // serialized across ALL executor instances in this process.
    private static let scriptQueue = DispatchQueue(label: "com.riftlet.apple-events", qos: .utility)

    public init() {}

    public func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        let browserID = "com.google.Chrome"
        let application: NSRunningApplication
        if command.action == .captureTarget {
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.bundleIdentifier == browserID else { throw WebAdapterError.browserNotFrontmost }
            application = frontmost
        } else {
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: browserID).first else {
                throw WebAdapterError.invalidTarget
            }
            application = running
        }
        guard let launched = application.launchDate else { throw WebAdapterError.invalidTarget }
        let session = "\(application.processIdentifier):\(launched.timeIntervalSince1970)"
        let requiresForeground = command.action != .observe && command.action != .discard
        if requiresForeground {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
                throw WebAdapterError.browserNotFrontmost
            }
        }
        let selection: String
        if command.action == .captureTarget {
            selection = """
            if frontmost is false then error "Browser no longer foreground"
            if (count of windows) is 0 then error "No browser window"
            set selectedWindow to front window
            set selectedTab to active tab of selectedWindow
            """
        } else {
            guard let target = command.target, target.applicationID == browserID,
                  target.sessionID == session,
                  let windowID = Int64(target.windowID), windowID > 0,
                  let tabText = target.tabID, let tabID = Int64(tabText), tabID > 0 else {
                throw WebAdapterError.invalidTarget
            }
            // Numeric identifiers only: no interpolation of caller-controlled AppleScript.
            selection = """
            set selectedWindow to first window whose id is \(windowID)
            set selectedTab to first tab of selectedWindow whose id is \(tabID)
            \(requiresForeground ? "if frontmost is false then error \"Browser no longer foreground\"\nif (id of front window) is not \(windowID) then error \"Original window no longer foreground\"\nif (id of active tab of selectedWindow) is not \(tabID) then error \"Original tab no longer active\"" : "")
            """
        }

        let commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        let sessionJSON = String(decoding: try JSONEncoder().encode(session), as: UTF8.self)
        // A supplied program receives native identities as context; it must observe
        // document/composer identity itself. Merely echoing context is not proof.
        let prefix = "JSON.stringify((\(program.functionSource))(\(commandJSON),{applicationID:\"\(browserID)\",sessionID:\(sessionJSON),windowID:String("
        let middle = "),tabID:String("
        let suffix = ")}))"
        let source = """
        with timeout of 5 seconds
            if application id "com.google.Chrome" is not running then error "Browser not running"
            tell application id "com.google.Chrome"
                \(selection)
                set nativeWindowID to (id of selectedWindow) as text
                set nativeTabID to (id of selectedTab) as text
                set jsSource to \(literal(prefix)) & nativeWindowID & \(literal(middle)) & nativeTabID & \(literal(suffix))
                return execute selectedTab javascript jsSource
            end tell
        end timeout
        """
        // Keep AppKit foreground/session snapshots on MainActor, but a blocked
        // Apple Event must not block the rift or menu for its timeout duration.
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            Self.scriptQueue.async {
                let result: Result<Data, WebAdapterError> = autoreleasepool {
                    guard let script = NSAppleScript(source: source) else { return .failure(.nativeExecutionFailed) }
                    var error: NSDictionary?
                    let reply = script.executeAndReturnError(&error)
                    guard error == nil, let text = reply.stringValue,
                          text.utf8.count <= ObservationDecoder.maximumPayloadBytes else {
                        return .failure(.nativeExecutionFailed)
                    }
                    return .success(Data(text.utf8))
                }
                continuation.resume(with: result)
            }
        }
        if command.action == .captureTarget {
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.processIdentifier == application.processIdentifier,
                  frontmost.launchDate == launched else {
                throw WebAdapterError.browserNotFrontmost
            }
        }
        return data
    }

    private func literal(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
}
