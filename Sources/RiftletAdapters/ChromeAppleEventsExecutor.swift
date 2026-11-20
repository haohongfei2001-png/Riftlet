import AppKit
import Carbon
import Foundation
import RiftletCore

/// Native Apple Events address a fixed process/window/tab. Page discovery may
/// start on the first click; no earlier page acknowledgement authorizes input.
@MainActor
public final class ChromeAppleEventsExecutor: WebClickTargetPinning {
    private nonisolated static let scriptQueue = DispatchQueue(label: "com.riftlet.apple-events", qos: .userInitiated, attributes: .concurrent)
    private nonisolated static let observationQueue = DispatchQueue(label: "com.riftlet.apple-events-observation", qos: .utility)
    private let relays = MainWorldRelayStore()
    private let trace: ChromeBridgeTrace
    private struct ClickDestination {
        let process: ChromeProcessIdentity
        let route: ChromeClickRoute
    }
    private var routes = ChromeSessionCache<ClickDestination>()
    private var edgeWorlds = ChromeSessionCache<EdgeExecutionWorldWitness>()

    public init(traceEnabled: Bool = false, diagnosticTrace: BoundedDiagnosticTrace? = nil) {
        trace = ChromeBridgeTrace(sink: diagnosticTrace ?? BoundedDiagnosticTrace(enabled: traceEnabled))
    }

    /// Read the native destination and enqueue its one document witness during
    /// mouse-down. The browser must establish it within the same deadline;
    /// waiting for its reply and validating the result happen off the UI thread.
    public func targetForClick(program: WebPageProgram) throws -> Task<TargetLease, Error> {
        let frozen = try freezeChatClick()
        return try enqueueChatClick(frozen, program: program)
    }

    fileprivate struct FrozenChatClick {
        let deadline: ChromeClickDeadline
        let identity: ChromeProcessIdentity
        let requestID: String
        let route: ChromeClickRoute
        let originalURL: URL
    }

    fileprivate func freezeChatClick(includeCandidateSites: Bool = false) throws -> FrozenChatClick {
        let deadline = ChromeClickDeadline()
        let identity = try clickReceiver()
        let requestID = UUID().uuidString
        let bridge = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: requestID, clickDeadline: deadline)
        let raw = try bridge.rawClickRoute(deadline: deadline)
        guard let originalURL = URL(string: raw.url) else { throw WebAdapterError.invalidTarget }
        let route = includeCandidateSites
            ? try ChromeClickRoute(window: raw.window, tab: raw.tab, url: raw.url)
            : try ChromeClickRoute.chatGPT(window: raw.window, tab: raw.tab, url: raw.url)
        return FrozenChatClick(deadline: deadline, identity: identity, requestID: requestID, route: route, originalURL: originalURL)
    }

    fileprivate func enqueueChatClick(_ frozen: FrozenChatClick, program: WebPageProgram, witnessID: UUID = UUID()) throws -> Task<TargetLease, Error> {
        let clickDeadline = frozen.deadline, identity = frozen.identity, requestID = frozen.requestID, route = frozen.route
        let bridge = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: requestID, clickDeadline: clickDeadline)
        let witness = ChromeClickDocumentWitness(id: witnessID)
        let world = identity.applicationID == AttachmentBrowser.edge.rawValue ? EdgeExecutionWorldWitness() : nil
        let binding = try world?.prepareAndBind(witness, address: route.address, program: program)
            ?? witness.bindScript(address: route.address, program: program)
        let reply = try bridge.enqueueWitness(clickDeadline.guardExecution(of: binding), route: route, deadline: clickDeadline)
        let relays = self.relays, trace = self.trace
        let confirmation = clickDeadline.confirmation
        return Task { [weak self] in
            try Task.checkCancellation()
            try await Task.detached(priority: .userInitiated) {
                let received = ProcessInfo.processInfo.systemUptime
                guard try reply.boundWithinClick(before: confirmation) else {
                    trace.record(requestID: requestID, action: "pinTarget", phase: "lateBrowserExecution",
                                 enqueued: received, started: received, context: nil, succeeded: false,
                                 error: .nativeEventFailed(Int32(errAETimeout)))
                    throw WebAdapterError.nativeEventFailed(Int32(errAETimeout))
                }
                guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
                let reader = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: requestID, clickDeadline: confirmation)
                let selected = try reader.activeIdentity(check: "document_pin")
                guard selected.window == route.window, selected.tab == route.tab, Self.foregroundMatches(identity) else {
                    throw WebAdapterError.nativeSelectionChanged
                }
                try confirmation.checkReturn()
                try confirmation.checkClockAgreement()
            }.value
            try Task.checkCancellation()
            let bytes = try await Self.run(WebBridgeCommand(action: .captureTarget, clickWitnessID: witness.id), program: program,
                identity: identity, route: route, relays: relays, trace: trace, requestID: requestID, world: world)
            try Task.checkCancellation()
            guard let target = try? JSONDecoder().decode(TargetLease.self, from: bytes),
                  target.adapterID == "chatgpt-web", target.surface == .webChat,
                  target.applicationID == identity.applicationID, target.sessionID == identity.session,
                  target.clickBindingID == witness.id,
                  target.windowID == route.window, target.tabID == route.tab,
                  target.historyConversationID == nil || target.historyConversationID == route.historyConversationID,
                  !target.documentID.isEmpty, !target.composerID.isEmpty, !target.draftGeneration.isEmpty,
                  let self else { throw WebAdapterError.invalidTarget }
            if let world { self.edgeWorlds.store(world, for: target.stableKey) }
            self.routes.store(ClickDestination(process: identity, route: route), for: target.stableKey)
            return target
        }
    }

    /// Only a user-requested history action calls this path. Validate the stored
    /// document and composer against an existing relay before raising its tab.
    public func focusOriginal(_ operation: TransferOperation) async -> Bool {
        struct DraftValidation: Decodable { let target: TargetLease; let valid: Bool }
        let target = operation.target
        guard target.surface == .webChat, target.adapterID == "chatgpt-web",
              ChromeProcessIdentity.supports(target.applicationID), let tab = target.tabID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.applicationID)
                .first(where: { ChromeProcessIdentity.read(pid: $0.processIdentifier, applicationID: target.applicationID)?.matches(session: target.sessionID) == true }),
              let identity = ChromeProcessIdentity.read(pid: app.processIdentifier, applicationID: target.applicationID),
              identity.matches(session: target.sessionID) else { return false }
        let requestID = UUID().uuidString
        let start = ProcessInfo.processInfo.systemUptime
        var phase = "readOriginalTab"
        var succeeded = false
        var failure: WebAdapterError?
        defer {
            trace.record(requestID: requestID, action: "focusOriginal", phase: phase,
                enqueued: start, started: start, context: nil, succeeded: succeeded, error: failure)
        }
        do {
            let program = try ChatGPTWebPageProgram.load()
            let bridge = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: requestID)
            let route = try await Task.detached {
                try ChromeClickRoute.chatGPT(window: target.windowID, tab: tab, url: bridge.url(window: target.windowID, tab: tab))
            }.value
            func matches() async throws -> Bool {
                let data = try await Self.run(.init(action: .validate, target: target, requireLiveOriginal: true), program: program,
                    identity: identity, route: route, relays: relays, trace: trace,
                    requestID: UUID().uuidString, discoverForHistory: true)
                let result = try JSONDecoder().decode(DraftValidation.self, from: data)
                return result.valid && result.target == target && identity.isCurrent()
            }
            phase = "validateBeforeSelection"
            guard try await matches() else { return false }
            phase = "selectOriginalTab"
            try await Task.detached {
                guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
                try bridge.selectForHistory(window: route.window, tab: route.tab)
            }.value
            phase = "validateAfterSelection"
            guard try await matches() else { return false }
            phase = "activateOriginalProcess"
            succeeded = app.activate(options: [.activateIgnoringOtherApps])
            return succeeded
        } catch {
            failure = error as? WebAdapterError
            return false
        }
    }

    private func clickReceiver() throws -> ChromeProcessIdentity {
        guard let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier,
              let identity = ChromeProcessIdentity.read(pid: front.processIdentifier, applicationID: id),
              Self.foregroundMatches(identity) else { throw WebAdapterError.browserNotFrontmost }
        return identity
    }

    private nonisolated static func foregroundMatches(_ identity: ChromeProcessIdentity) -> Bool {
        let front = NSWorkspace.shared.frontmostApplication
        return identity.isCurrent() && identity.matchesForeground(pid: front?.processIdentifier, applicationID: front?.bundleIdentifier)
    }

    private nonisolated static func contextJSON(applicationID: String, session: String, window: String, tab: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try! encoder.encode(["applicationID":applicationID, "sessionID":session,
            "windowID":window, "tabID":tab]), as: UTF8.self)
    }

    public func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        guard command.action != .pinTarget else { throw WebAdapterError.invalidRequest }
        if command.action == .captureTarget {
            let task = try targetForClick(program: program)
            let target = try await task.value
            return try JSONEncoder().encode(target)
        }
        guard let target = command.target, ChromeProcessIdentity.supports(target.applicationID),
              let tab = target.tabID, let windowNumber = Int64(target.windowID), windowNumber > 0,
              let tabNumber = Int64(tab), tabNumber > 0 else { throw WebAdapterError.invalidTarget }
        let requestID = UUID().uuidString
        let started = ProcessInfo.processInfo.systemUptime
        func refuse(_ phase: String) -> WebAdapterError {
            trace.record(requestID: requestID, action: command.action.rawValue, phase: phase,
                         enqueued: started, started: started, context: nil, succeeded: false, error: .invalidTarget)
            return .invalidTarget
        }
        let destination = routes.value(for: target.stableKey)
        let identity: ChromeProcessIdentity
        if let process = destination?.process {
            guard process.applicationID == target.applicationID, process.matches(session: target.sessionID) else {
                throw refuse("originalSessionMismatch")
            }
            guard process.isCurrent() else { throw refuse("originalProcessChanged") }
            identity = process
        } else {
            // After restart only observation can locate an existing recipient.
            guard command.action == .observe else { throw refuse("originalRouteUnavailable") }
            let original = NSRunningApplication.runningApplications(withBundleIdentifier: target.applicationID)
                .compactMap { ChromeProcessIdentity.read(pid: $0.processIdentifier, applicationID: target.applicationID) }
                .first { $0.matches(session: target.sessionID, allowLegacyObservation: true) }
            guard let original else { throw refuse("originalProcessUnavailable") }
            identity = original
        }
        if command.action != .observe && relays.bound(to: target) == nil {
            throw refuse("originalRelayUnavailable")
        }
        let route = destination?.route
        return try await Self.run(command, program: program, identity: identity, route: route,
            relays: relays, trace: trace, requestID: requestID, world: edgeWorlds.value(for: target.stableKey))
    }

    private nonisolated static func run(_ command: WebBridgeCommand, program: WebPageProgram,
        identity: ChromeProcessIdentity, route: ChromeClickRoute?, relays: MainWorldRelayStore,
        trace: ChromeBridgeTrace, requestID: String, discoverForHistory: Bool = false, world: EdgeExecutionWorldWitness? = nil) async throws -> Data {
        let commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        let enqueued = ProcessInfo.processInfo.systemUptime
        // Old UNKNOWN observations must not occupy the input queue. Each
        // request still owns a separate receipt and never resubmits input.
        let queue = command.action == .observe ? observationQueue : scriptQueue
        let submission = NativeCommandSubmission()
        return try await submission.perform { continuation in
            queue.async {
                let started = ProcessInfo.processInfo.systemUptime
                var phase = "process"
                let result: Result<Data, Error> = Result {
                    try autoreleasepool {
                        guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
                        let bridge = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: requestID)
                        guard let window = route?.window ?? command.target?.windowID,
                              let tab = route?.tab ?? command.target?.tabID else { throw WebAdapterError.invalidTarget }
                        func checkSelection() throws {
                            guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
                            guard ChromeCommandRouting.requiresSelectionCheck(command.action) else { return }
                            if !discoverForHistory {
                                guard Self.foregroundMatches(identity) else { throw WebAdapterError.nativeSelectionChanged }
                                let selection = try bridge.activeIdentity(check: "before_command")
                                guard selection.window == window, selection.tab == tab else { throw WebAdapterError.nativeSelectionChanged }
                            }
                            guard let route else { throw WebAdapterError.invalidTarget }
                            let current = try ChromeClickRoute.chatGPT(window: route.window, tab: route.tab,
                                url: bridge.url(window: route.window, tab: route.tab))
                            guard current == route else { throw WebAdapterError.nativeSelectionChanged }
                        }
                        phase = "selection"
                        if command.action == .captureTarget { try checkSelection() }
                        if command.action == .observe || discoverForHistory {
                            // A relaunched App may have no cached route. Read the
                            // exact saved tab's service before any relay discovery.
                            let current = try ChromeClickRoute.chatGPT(window: window, tab: tab,
                                url: bridge.url(window: window, tab: tab))
                            guard current.matchesOriginal(route: route, savedConversation: command.target?.historyConversationID) else {
                                throw WebAdapterError.nativeSelectionChanged
                            }
                        }
                        if let world, command.action == .captureTarget {
                            try bridge.submitMainWorld(world.bootstrap, window: window, tab: tab)
                            guard try bridge.execute(world.confirm, window: window, tab: tab) == "verified" else {
                                throw WebAdapterError.pageRejected(.bridgeUnavailable)
                            }
                        }
                        let context = contextJSON(applicationID: identity.applicationID, session: command.target?.sessionID ?? identity.session, window: window, tab: tab)
                        let envelope = MainWorldCommandEnvelope(function: program.functionSource,
                            commandJSON: commandJSON, contextJSON: context)
                        let legacySession = (identity.applicationID == AttachmentBrowser.chrome.rawValue ? identity.legacyLaunchDate : nil).flatMap { date in
                            date.timeIntervalSince1970.isFinite ? "\(identity.pid):\(date.timeIntervalSince1970)" : nil
                        }
                        var relay = command.target.flatMap { relays.bound(to: $0) } ?? relays.relay(function: program.functionSource, contextJSON: context,
                            allowCreate: false, legacyObservationSession: legacySession)
                        if relay == nil, command.action == .observe || command.action == .captureTarget || (discoverForHistory && command.action == .validate) {
                            let expected = MainWorldCommandRelay(function: program.functionSource,
                                contextJSON: context, legacyObservationSession: legacySession)
                            let channel = try bridge.execute(expected.discovery, window: window, tab: tab,
                                receiptBudget: .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 1))
                            guard channel != "ambiguous" else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
                            relay = relays.adopt(function: program.functionSource, contextJSON: context,
                                channel: channel, legacyObservationSession: legacySession)
                        }
                        if command.action == .captureTarget, relay == nil {
                            relay = relays.relay(function: program.functionSource, contextJSON: context,
                                allowCreate: true, legacyObservationSession: legacySession)
                        }
                        guard let relay else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
                        phase = "submit"
                        var install = false
                        if command.action == .captureTarget {
                            install = try bridge.execute(relay.probe, window: window, tab: tab,
                                receiptBudget: .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 1)) != "ready"
                        }
                        if identity.applicationID == AttachmentBrowser.edge.rawValue, !discoverForHistory, command.action != .observe {
                            guard let world, try bridge.execute(world.validate, window: window, tab: tab) == "verified" else {
                                throw WebAdapterError.pageRejected(.clickPinRefused)
                            }
                        }
                        // The final foreground and tab checks follow all potentially
                        // blocking world checks and precede the single submission.
                        try checkSelection()
                        try submission.enter()
                        try ChromeMainWorldSubmission.submit(relay: relay, envelope: envelope, install: install,
                            bootstrap: { try bridge.submitMainWorld($0, window: window, tab: tab) },
                            dispatch: { try bridge.dispatchMainWorld($0, window: window, tab: tab) })
                        phase = "receipt"
                        // A first-use attachment entry can mount its picker
                        // asynchronously. Read the same once-submitted commit
                        // through that bounded discovery; never resend it.
                        let receipt = try MainWorldReceiptReader.read(envelope,
                            timeout: command.action == .commit ? 8 : 1) { budget in
                            try bridge.execute(envelope.reader, window: window, tab: tab, receiptBudget: budget)
                        }
                        guard identity.isCurrent(), receipt.text.utf8.count <= ObservationDecoder.maximumPayloadBytes else {
                            throw WebAdapterError.invalidReply
                        }
                        if command.action == .captureTarget {
                            try checkSelection()
                            if let target = try? JSONDecoder().decode(TargetLease.self, from: Data(receipt.text.utf8)) {
                                relays.bind(relay, to: target)
                            }
                        }
                        phase = "complete"
                        return Data(receipt.text.utf8)
                    }
                }
                let error: WebAdapterError?
                if case .failure(let failure) = result { error = failure as? WebAdapterError } else { error = nil }
                trace.record(requestID: requestID, action: command.action.rawValue, phase: phase,
                    enqueued: enqueued, started: started, context: command.captureInvocation,
                    succeeded: (try? result.get()) != nil, error: error)
                continuation.resume(with: result)
            }
        }
    }
}

/// Development composition only. Read the nominated site's closed discovery
/// result in the originally addressed tab. No chooser, click, pin or input.
@MainActor public enum CandidateProviderInspector {
    public static func inspectForeground() async throws -> [String: String] {
        let catalog = try Issue120ProviderCatalog()
        let deadline = ChromeClickDeadline()
        guard let front = NSWorkspace.shared.frontmostApplication, let bundle = front.bundleIdentifier,
              let identity = ChromeProcessIdentity.read(pid: front.processIdentifier, applicationID: bundle) else {
            throw BindingError.unsupported
        }
        let bridge = ChromePIDEvents(pid: identity.pid, trace: ChromeBridgeTrace(sink: BoundedDiagnosticTrace(enabled: false)),
                                     requestID: UUID().uuidString, clickDeadline: deadline)
        let raw = try bridge.rawClickRoute(deadline: deadline)
        guard let url = URL(string: raw.url) else { throw BindingError.unsupported }
        let route = try resolveProvider(url, among: catalog.providers)
        let program = try catalog.program(for: route.profile)
        let literal = String(decoding: try JSONEncoder().encode(raw.url), as: UTF8.self)
        let code = "location.href === " + literal + " ? (" + program + ").inspect() : 'other_route'"
        let address = try ChromeClickRoute(window: raw.window, tab: raw.tab, url: raw.url)
        let reply = try bridge.enqueueWitness(deadline.guardExecution(of: code), route: address, deadline: deadline)
        let result = try await Task.detached {
            try reply.stringWithinClick(before: deadline.confirmation)
        }.value
        guard let current = NSWorkspace.shared.frontmostApplication,
              identity.matchesForeground(pid: current.processIdentifier, applicationID: current.bundleIdentifier),
              identity.isCurrent(),
              ["other_route","editor_unavailable","owner_unavailable","upload_control_unavailable",
               "editor_and_upload_action","owned_input"].contains(result) else { throw BindingError.targetChanged }
        return ["browser":bundle,"provider":route.profile.id,"programSHA256":route.profile.digest,"discovery":result]
    }
}

/// The two existing browser receivers use the original build-53 native pin and
/// execution-world checks. A second capture invalidates the first pending enqueue.
@MainActor final class ChatGPTChromiumHost: BrowserHost {
    let bundle: String
    let provider: ChatGPTConversationProvider
    private let executor: ChromeAppleEventsExecutor
    private let program: WebPageProgram
    private let inspectPermission: () -> OriginalReceiverAccess
    private var pending: (NativeClick, ChromeAppleEventsExecutor.FrozenChatClick)?

    init(browser: AttachmentBrowser, executor: ChromeAppleEventsExecutor, program: WebPageProgram,
         permission: @escaping () -> OriginalReceiverAccess) throws {
        self.bundle = browser.rawValue
        self.executor = executor
        self.program = program
        self.provider = try ChatGPTConversationProvider(program: program)
        self.inspectPermission = permission
    }

    var capabilities: HostCapabilities {
        .init(world: .page, reply: .originalAsynchronousReply, locator: .stableNativeID,
              epoch: .navigationEntry, fileSetterAndDataTransferVerified: true,
              maximumPinBytes: program.pinSource?.utf8.count ?? 0)
    }

    func permissionState() -> OriginalReceiverAccess { inspectPermission() }

    func freezeClick() throws -> NativeClick {
        pending = nil
        let frozen = try executor.freezeChatClick(includeCandidateSites: true)
        let pid = frozen.identity
        guard pid.applicationID == bundle else {
            throw BindingError.targetChanged
        }
        let click = NativeClick(bundle: bundle, pid: pid.pid, processBirth: pid.session,
            session: pid.session, window: frozen.route.window, tab: frozen.route.tab, url: frozen.originalURL,
            generation: UUID(), uptime: ProcessInfo.processInfo.systemUptime)
        pending = (click, frozen)
        return click
    }

    func enqueuePin(click: NativeClick, route: ProviderRoute, maximumBytes: Int) throws -> Task<PinReceipt, Error> {
        let saved = pending
        pending = nil
        guard route.profile == provider.profile else { throw BindingError.unsupported }
        guard let saved, saved.0 == click,
              provider.classify(click.url) == route.route, let pin = program.pinSource,
              !pin.isEmpty, pin.utf8.count <= maximumBytes else { throw BindingError.targetChanged }
        let original = try executor.enqueueChatClick(saved.1, program: program, witnessID: click.generation)
        return Task { try await PinReceipt(click: click, route: route, target: original.value) }
    }
}

struct ChatGPTConversationProvider: ConversationProvider {
    let profile: ProviderProfile
    let httpsHosts: Set<String> = ["chatgpt.com", "chat.openai.com"]

    init(program: WebPageProgram) throws {
        guard program.sourceID == ChatGPTWebPageProgram.sourceID else { throw BindingError.invalidProfile }
        profile = try ProviderProfile(id: "chatgpt", revision: 30, program: Data(program.functionSource.utf8))
    }

    func classify(_ url: URL) -> DraftRoute? {
        guard let host = url.host?.lowercased(), httpsHosts.contains(host),
              let route = try? ChromeClickRoute.chatGPT(window: "1", tab: "1", url: url.absoluteString)
        else { return nil }
        return DraftRoute(identity: route.address, surface: "webChat", mode: "chatgpt-web")
    }
}

/// Explicit setup check. The program evaluates a constant, with no DOM access,
/// file input, navigation or attachment relay. No tab identifier leaves this call.
public enum ChromeSetupConnectionProbe {
    public enum Result: Equatable, Sendable {
        case ready, javaScriptDisabled, permissionNotRequested, permissionDenied, noWindow, unavailable
    }

    public static func check(_ process: ChromeProcessIdentity) async -> Result {
        // A blocking Apple Event belongs off the main actor.
        await Task.detached(priority: .userInitiated) {
            guard process.isCurrent() else { return .unavailable }
            let bridge = ChromePIDEvents(pid: process.pid,
                trace: ChromeBridgeTrace(sink: BoundedDiagnosticTrace(enabled: false)), requestID: "setup")
            return evaluate(read: {
                let route = try bridge.activeIdentity(check: "setup")
                guard process.isCurrent() else { throw WebAdapterError.invalidTarget }
                return try bridge.execute("'Riftlet'", window: route.window, tab: route.tab,
                    receiptBudget: .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 3))
            }, stillCurrent: { process.isCurrent() })
        }.value
    }

    static func evaluate(read: () throws -> String, stillCurrent: () -> Bool) -> Result {
        let result: Result
        do { result = try read() == "Riftlet" ? .ready : .unavailable }
        catch WebAdapterError.nativeEventFailed(12) { result = .javaScriptDisabled }
        catch WebAdapterError.nativeEventFailed(-1744) { result = .permissionNotRequested }
        catch WebAdapterError.nativeEventFailed(-1743) { result = .permissionDenied }
        catch WebAdapterError.nativeEventFailed(-1728) { result = .noWindow }
        catch { result = .unavailable }
        return stillCurrent() ? result : .unavailable
    }
}

/// MAIN owns application-created pickers and their prototypes. Chrome's isolated
/// execute-JavaScript world can dispatch to an existing MAIN relay, but cannot
/// replace that relay's installer. A cold javascript: bootstrap can raise the
/// original Chrome window; it must keep that target and must never retry through
/// another world or restore focus after the user has moved elsewhere.
enum ChromeMainWorldSubmission {
    static func submit(relay: MainWorldCommandRelay, envelope: MainWorldCommandEnvelope, install: Bool,
                       bootstrap: (String) throws -> Void, dispatch: (String) throws -> Void) throws {
        if install {
            try bootstrap("(()=>{\(relay.installer);return \(relay.dispatch(envelope));})()")
        } else {
            try dispatch(relay.dispatch(envelope))
        }
    }
}

/// Local opt-in timing only; never raw source, URL, page content or payload.
private final class ChromeBridgeTrace: @unchecked Sendable {
    private let sink: BoundedDiagnosticTrace
    init(sink: BoundedDiagnosticTrace) { self.sink = sink }
    func record(requestID: String, action: String, phase: String, enqueued: TimeInterval, started: TimeInterval,
                context: CaptureInvocationContext?, succeeded: Bool, error: WebAdapterError? = nil) {
        let end = ProcessInfo.processInfo.systemUptime
        var fields: [String: Any] = ["event": "native_bridge", "requestID": requestID, "action": action, "phase": phase,
            "queuedUptime": enqueued, "startedUptime": started, "endedUptime": end,
            "queueMS": (started - enqueued) * 1000, "executionMS": (end - started) * 1000, "transportSucceeded": succeeded]
        addContext(context, to: &fields)
        if let error {
            fields["error"] = error.diagnosticLabel
            if case .pageRejected(let code) = error, code.isInputResourceRefusal {
                fields["resourceRefusalReason"] = code.rawValue
            }
        }
        sink.record(fields, critical: !succeeded && action != "captureTarget" && action != "observe")
    }

    func activeIdentity(requestID: String, check: String, route: String, started: TimeInterval, succeeded: Bool) {
        let fields: [String: Any] = ["event": "active_identity", "requestID": requestID,
            "check": check, "route": route, "elapsedMS": (ProcessInfo.processInfo.systemUptime - started) * 1000,
            "succeeded": succeeded, "authority": "DIAGNOSTIC_ONLY"]
        sink.record(fields)
    }

    private func addContext(_ context: CaptureInvocationContext?, to fields: inout [String: Any]) {
        guard let context else { return }
        fields["captureRequestID"] = context.requestID.uuidString
        fields["armAttemptID"] = context.armAttemptID.uuidString
        fields["hostEpoch"] = context.hostEpoch.uuidString
    }
}

/// Pure parser for the observed Chrome get-acTa result. Only a complete,
/// absolute tab-ID -> window-ID -> null object chain is a one-read identity.
/// Unsupported descriptor shapes return nil for the existing compatibility path.
enum ChromeActiveTabDescriptor {
    private static func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    static func identity(in descriptor: NSAppleEventDescriptor) -> (window: String, tab: String)? {
        guard let tab = fixedObject(descriptor, kind: "CrTb"),
              let window = fixedObject(tab.container, kind: "cwin"),
              window.container.descriptorType == code("null"), window.container.data.isEmpty else { return nil }
        return (window.id, tab.id)
    }

    static func matchedURL(properties: NSAppleEventDescriptor?, tab: String) throws -> String? {
        guard let properties, properties.descriptorType == code("reco"),
              let kind = properties.forKeyword(code("pcls")), kind.descriptorType == code("type"),
              kind.typeCodeValue == code("CrTb"),
              let id = properties.forKeyword(code("ID  ")), id.descriptorType == code("utxt") else { return nil }
        // Two independent reads can straddle a real tab switch. Refuse this click.
        guard id.stringValue == tab else { throw WebAdapterError.invalidTarget }
        guard let url = properties.forKeyword(code("URL ")), url.descriptorType == code("utxt") else { return nil }
        return url.stringValue
    }

    private static func fixedObject(_ descriptor: NSAppleEventDescriptor, kind: String)
        -> (id: String, container: NSAppleEventDescriptor)? {
        let keys = Set([code("want"), code("form"), code("seld"), code("from")])
        guard descriptor.descriptorType == code("obj "), descriptor.numberOfItems == 4,
              Set((1...4).map { descriptor.keywordForDescriptor(at: $0) }) == keys,
              let want = descriptor.forKeyword(code("want")), want.descriptorType == code("type"),
              want.data.count == 4, want.typeCodeValue == code(kind),
              let form = descriptor.forKeyword(code("form")), form.descriptorType == code("enum"),
              form.data.count == 4, form.enumCodeValue == code("ID  "),
              let selector = descriptor.forKeyword(code("seld")), selector.descriptorType == code("utxt"),
              let text = selector.stringValue, !text.isEmpty, text.utf8.count <= 19,
              text.utf8.allSatisfy({ (48...57).contains($0) }), text.first != "0",
              let number = Int64(text), number > 0, String(number) == text,
              let container = descriptor.forKeyword(code("from")) else { return nil }
        return (text, container)
    }
}

/// Mouse-down fixes the URL as well as the window and tab, since Chrome can
/// navigate to another draft in the same tab. All of these read-only Apple
/// Events, including the compatibility path, share one short deadline.
struct ChromeClickDeadline {
    private static let captureSeconds = 0.15
    private let start: TimeInterval
    private let end: TimeInterval
    private let wallStartMS: Int64

    init(start: TimeInterval = ProcessInfo.processInfo.systemUptime,
         wallTime: TimeInterval = Date().timeIntervalSince1970) {
        self.start = start
        end = start + Self.captureSeconds
        wallStartMS = Int64((wallTime * 1000).rounded(.down))
    }

    private init(capture: Self, end: TimeInterval) {
        start = capture.start
        wallStartMS = capture.wallStartMS
        self.end = end
    }

    /// Only the receipt of the original event and read-only target checks get
    /// this budget. It never grants additional time to establish a binding.
    var confirmation: Self { Self(capture: self, end: start + 1) }

    // Native uptime governs the reply. If the wall clock changed during the
    // request, its browser-side execution timestamp no longer proves the click.
    private static let clockToleranceMS: Int64 = 5
    func checkClockAgreement(at now: TimeInterval = ProcessInfo.processInfo.systemUptime,
                             wallTime: TimeInterval = Date().timeIntervalSince1970) throws {
        let wallElapsed = wallTime * 1000 - Double(wallStartMS)
        guard abs(wallElapsed - (now - start) * 1000) <= Double(Self.clockToleranceMS) else {
            throw WebAdapterError.nativeEventFailed(Int32(errAETimeout))
        }
    }

    func guardExecution(of binding: String) -> String {
        let lastMS = wallStartMS + Int64(Self.captureSeconds * 1000) - Self.clockToleranceMS
        return """
        (()=>{const wall=Date.now(),age=performance.now();
        if(!Number.isFinite(age)||age<0||wall<\(wallStartMS)||wall>\(lastMS)
          ||wall-age>\(wallStartMS))return 'expired';
        if(document.visibilityState!=='visible'||!document.hasFocus())return 'refused';
        const result=(\(binding)),end=Date.now(),spent=performance.now()-age;
        return end>=wall&&end<=\(lastMS)&&spent>=0&&wall+spent<=\(lastMS)?result:'expired';})()
        """
    }

    func timeout(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> TimeInterval {
        let remaining = end - now
        // Never pass a zero or sub-tick timeout to the Apple Event Manager.
        guard remaining >= 1.0 / 60.0 else { throw WebAdapterError.nativeEventFailed(-1712) }
        return remaining
    }

    func receiveMilliseconds(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> UInt32 {
        let remaining = (end - now) * 1000
        guard remaining >= 1 else { throw WebAdapterError.nativeEventFailed(-1712) }
        return UInt32(remaining)
    }

    func checkReturn(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        guard now < end else { throw WebAdapterError.nativeEventFailed(-1712) }
    }
}

enum ChromeHistoryTabSelection {
    /// An absolute-position object specifier carries an absolute ordinal (abso),
    /// even though its key form is an enumeration (indx).
    static func allTabsOrdinal() throws -> NSAppleEventDescriptor {
        let value = NSAppleEventDescriptor(enumCode: OSType(kAEAll)).data
        guard let descriptor = NSAppleEventDescriptor(descriptorType: typeAbsoluteOrdinal, data: value) else {
            throw WebAdapterError.nativeExecutionFailed
        }
        return descriptor
    }
}

/// Codes come from Chrome's installed scripting.sdef (Standard/Chromium suites),
/// not undocumented browser internals. Mouse-down reads use the common click
/// deadline. Background submissions use five seconds; receipts use their command
/// budget (eight seconds for attachment discovery, one for other commands).
/// This never activates or sends a ChatGPT message. The URL setter
/// receives only a void JavaScript expression, not a navigation URL.
private struct ChromePIDEvents {
    let pid: pid_t
    let trace: ChromeBridgeTrace
    let requestID: String
    var clickDeadline: ChromeClickDeadline? = nil
    private func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    private func object(_ kind: String, form: String, key: NSAppleEventDescriptor,
                        container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: code(kind)), forKeyword: code("want"))
        record.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(key, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        guard let specifier = record.coerce(toDescriptorType: code("obj ")) else { throw WebAdapterError.nativeExecutionFailed }
        return specifier
    }

    private func property(_ name: String, of container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        try object("prop", form: "prop", key: .init(typeCode: code(name)), container: container)
    }

    private func send(_ suite: String, _ event: String, direct: NSAppleEventDescriptor,
                      javascript: String? = nil, value: String? = nil, integer: Int32? = nil,
                      receiptBudget: MainWorldReceiptReadBudget? = nil) throws -> NSAppleEventDescriptor {
        let request = NSAppleEventDescriptor(eventClass: code(suite), eventID: code(event),
            targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
        request.setParam(direct, forKeyword: code("----"))
        if let javascript { request.setParam(.init(string: javascript), forKeyword: code("JvSc")) }
        if let integer { request.setParam(.init(int32: integer), forKeyword: code("data")) }
        if let value { request.setParam(.init(string: value), forKeyword: code("data")) }
        let timeout: TimeInterval
        if let receiptBudget {
            timeout = try receiptBudget.timeout(at: ProcessInfo.processInfo.systemUptime)
        } else if let clickDeadline {
            timeout = try clickDeadline.timeout()
        } else { timeout = 5 }
        let reply: NSAppleEventDescriptor
        do { reply = try request.sendEvent(options: ChromeClickSnapshot.waitOptions, timeout: timeout) }
        catch {
            // Never surface the native localized description: it can contain
            // script source, user paths or page payload. A numeric OSStatus is
            // sufficient to distinguish denied Automation from timeout/transport.
            let native = error as NSError
            guard native.domain == NSOSStatusErrorDomain,
                  let status = Int32(exactly: native.code) else { throw WebAdapterError.nativeExecutionFailed }
            throw WebAdapterError.nativeEventFailed(status)
        }
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
            throw WebAdapterError.nativeEventFailed(error.int32Value)
        }
        guard let result = reply.paramDescriptor(forKeyword: code("----")) else {
            if value != nil || integer != nil { return .null() }
            throw WebAdapterError.nativeExecutionFailed
        }
        return result
    }

    private func get(_ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try send("core", "getd", direct: object)
    }

    private func identifier(_ object: NSAppleEventDescriptor) throws -> String {
        guard let value = try get(property("ID  ", of: object)).stringValue,
              let number = Int64(value), number > 0 else { throw WebAdapterError.invalidTarget }
        return String(number)
    }

    func rawClickRoute(deadline: ChromeClickDeadline) throws -> (window: String, tab: String, url: String) {
        let started = ProcessInfo.processInfo.systemUptime
        var succeeded = false
        var stage = "create_specifiers"
        defer { trace.activeIdentity(requestID: requestID, check: "click_selection", route: succeeded ? "queued_click_route" : stage,
                                     started: started, succeeded: succeeded) }
        let front = try object("cwin", form: "indx", key: .init(int32: 1))
        let active = try property("acTa", of: front)
        let reads = try ChromeClickSnapshot.read(pid: pid, active: active, properties: property("pALL", of: active),
                                                 deadline: deadline, stage: &stage)
        // A later front-window lookup could select a different draft. The
        // absolute click-time pair remains mandatory even when pALL is absent.
        stage = "absolute_identity"
        guard let identity = ChromeActiveTabDescriptor.identity(in: reads.activeTab) else {
            throw WebAdapterError.invalidTarget
        }
        stage = "original_tab_url"
        let address = try ChromeActiveTabDescriptor.matchedURL(properties: reads.properties, tab: identity.tab)
            ?? url(window: identity.window, tab: identity.tab)
        succeeded = true
        return (identity.window, identity.tab, address)
    }

    func url(window: String, tab: String) throws -> String {
        let windowObject = try object("cwin", form: "ID  ", key: .init(string: window))
        let tabObject = try object("CrTb", form: "ID  ", key: .init(string: tab), container: windowObject)
        guard let value = try get(property("URL ", of: tabObject)).stringValue else {
            throw WebAdapterError.invalidTarget
        }
        return value
    }

    func selectForHistory(window: String, tab: String) throws {
        let owner = try object("cwin", form: "ID  ", key: .init(string: window))
        let active = try property("acTa", of: owner)
        if try identifier(get(active)) != tab {
            // Chrome exposes selection by index only. Resolve IDs within the
            // saved window and check both sides of the indexed selection.
            let tabs = try object("CrTb", form: "indx", key: ChromeHistoryTabSelection.allTabsOrdinal(), container: owner)
            let ids = try get(property("ID  ", of: tabs))
            guard ids.numberOfItems > 0,
                  let index = (1...ids.numberOfItems).first(where: { ids.atIndex($0)?.stringValue == tab }),
                  let position = Int32(exactly: index) else { throw WebAdapterError.invalidTarget }
            let candidate = try object("CrTb", form: "indx", key: .init(int32: position), container: owner)
            guard try identifier(candidate) == tab else { throw WebAdapterError.invalidTarget }
            _ = try send("core", "setd", direct: property("acTI", of: owner), integer: position)
        }
        guard try identifier(get(active)) == tab else { throw WebAdapterError.invalidTarget }
        _ = try send("core", "setd", direct: property("pidx", of: owner), integer: 1)
        let selected = try activeIdentity(check: "history_focus")
        guard selected.window == window, selected.tab == tab else { throw WebAdapterError.invalidTarget }
    }

    func activeIdentity(check: String) throws -> (window: String, tab: String) {
        let started = ProcessInfo.processInfo.systemUptime
        var route = "descriptor_read_failed", succeeded = false
        defer { trace.activeIdentity(requestID: requestID, check: check, route: route, started: started, succeeded: succeeded) }
        let front = try object("cwin", form: "indx", key: .init(int32: 1))
        // One get resolves the front window's active tab to an absolute object
        // chain. Parse fields, never the descriptor's printable description.
        let snapshot = try get(property("acTa", of: front))
        if let identity = ChromeActiveTabDescriptor.identity(in: snapshot) {
            route = "descriptor_fast"; succeeded = true; return identity
        }
        route = "legacy_fallback"
        // Older/unsupported Chrome shapes retain the previous three-read path.
        // A transport error above propagates; it is not an automatic resend.
        let identity = try legacyIdentity(front: front)
        succeeded = true
        return identity
    }

    private func legacyIdentity(front: NSAppleEventDescriptor) throws -> (window: String, tab: String) {
        let windowID = try identifier(front)
        // Resolve the tab from the captured window, not a second front-window read.
        let window = try object("cwin", form: "ID  ", key: .init(string: windowID))
        let active = try get(property("acTa", of: window))
        let tabID = try identifier(active)
        return (windowID, tabID)
    }

    func enqueueWitness(_ source: String, route: ChromeClickRoute, deadline: ChromeClickDeadline) throws -> ChromeClickSnapshot.WitnessReply {
        let window = try object("cwin", form: "ID  ", key: .init(string: route.window))
        let tab = try object("CrTb", form: "ID  ", key: .init(string: route.tab), container: window)
        let event = NSAppleEventDescriptor(eventClass: code("CrSu"), eventID: code("ExJa"),
            targetDescriptor: .init(processIdentifier: pid), returnID: 3, transactionID: 0)
        event.setParam(tab, forKeyword: keyDirectObject)
        event.setParam(.init(string: source), forKeyword: code("JvSc"))
        return try ChromeClickSnapshot.enqueueWitness(event, before: deadline)
    }

    func execute(_ source: String, window: String, tab: String,
                 receiptBudget: MainWorldReceiptReadBudget? = nil) throws -> String {
        let windowObject = try object("cwin", form: "ID  ", key: .init(string: window))
        let tabObject = try object("CrTb", form: "ID  ", key: .init(string: tab), container: windowObject)
        guard let result = try send("CrSu", "ExJa", direct: tabObject, javascript: source,
                                    receiptBudget: receiptBudget).stringValue else {
            throw WebAdapterError.nativeExecutionFailed
        }
        return result
    }

    func dispatchMainWorld(_ source: String, window: String, tab: String) throws {
        let windowObject = try object("cwin", form: "ID  ", key: .init(string: window))
        let tabObject = try object("CrTb", form: "ID  ", key: .init(string: tab), container: windowObject)
        guard try send("CrSu", "ExJa", direct: tabObject, javascript: source).stringValue == "submitted" else {
            throw WebAdapterError.nativeExecutionFailed
        }
    }

    func submitMainWorld(_ source: String, window: String, tab: String) throws {
        let windowObject = try object("cwin", form: "ID  ", key: .init(string: window))
        let tabObject = try object("CrTb", form: "ID  ", key: .init(string: tab), container: windowObject)
        // URL parsing strips literal line breaks (which would turn // comments
        // into the remainder of the program). Encode source before that parser.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = ("void(" + source + ")").addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw WebAdapterError.invalidRequest
        }
        _ = try send("core", "setd", direct: property("URL ", of: tabObject), value: "javascript:" + encoded)
    }
}
