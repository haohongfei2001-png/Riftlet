import AppKit
import Foundation
import RiftletCore

/// Native Apple Events transport; selectors and completion rules stay in the
/// reviewed page program. Events address the exact PID, never an ambiguous
/// bundle-ID lookup when several Chrome profile processes are running.
@MainActor
public final class ChromeAppleEventsExecutor: WebClickTargetPinning {
    private static let scriptQueue = DispatchQueue(label: "com.riftlet.apple-events", qos: .utility)
    private static let clickResolutionQueue = DispatchQueue(label: "com.riftlet.pending-click", qos: .userInitiated)
    private static let capturePriority = CaptureReadPriority()
    private let observedRoutes = ObservedClickRoutes()
    private let relays = MainWorldRelayStore()
    private let trace: ChromeBridgeTrace

    public init(traceEnabled: Bool = false) { trace = ChromeBridgeTrace(enabled: traceEnabled) }

    /// Runs directly at the native press callback, before an asynchronous queue
    /// can substitute a newly frontmost tab. Reads Chrome's absolute object
    /// specifier, then submits only to that object. No activation or tab setter.
    /// The page must already have a continuous identity observer, but its full
    /// target ACK need not have returned to the App.
    public func pinTargetAtPress(program: WebPageProgram, eventUptime: TimeInterval) throws -> TargetLease {
        Self.capturePriority.supersede()
        let started = ProcessInfo.processInfo.systemUptime
        let routeSnapshot = observedRoutes.snapshot()
        let deadline = started + 0.75
        guard eventUptime.isFinite, eventUptime >= 0, eventUptime <= started,
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.google.Chrome",
              let identity = ChromeProcessIdentity.read(pid: app.processIdentifier) else { throw WebAdapterError.invalidTarget }
        let requestID = UUID(), pinID = UUID()
        let bridge = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: requestID.uuidString, deadline: deadline)
        guard identity.isCurrent(), try bridge.frontmost() else { throw WebAdapterError.browserNotFrontmost }
        let selected = try bridge.activeIdentity(check: "press_route")
        guard let expected = routeSnapshot.target(session: identity.session, window: selected.window, tab: selected.tab, eventUptime: eventUptime) else {
            throw WebAdapterError.pageRejected(.clickRouteUnobserved)
        }
        let command = WebBridgeCommand(action: .pinTarget, target: expected, clickBindingID: pinID)
        let envelope = MainWorldCommandEnvelope(function: program.functionSource,
            commandJSON: String(decoding: try JSONEncoder().encode(command), as: UTF8.self),
            contextJSON: Self.contextJSON(session: identity.session, window: selected.window, tab: selected.tab))
        guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
        guard let relay = relays.relay(function: program.functionSource,
            contextJSON: Self.contextJSON(session: identity.session, window: selected.window, tab: selected.tab), allowCreate: false) else {
            throw WebAdapterError.pageRejected(.bridgeUnavailable)
        }
        try bridge.dispatchMainWorld(relay.dispatch(envelope), window: selected.window, tab: selected.tab)
        let receipt = try MainWorldReceiptReader.read(envelope) { budget in
            try bridge.execute(envelope.reader, window: selected.window, tab: selected.tab, receiptBudget: budget)
        }
        let data = Data(receipt.text.utf8)
        _ = try NativeCaptureProof.digest(data, session: identity.session, window: selected.window, tab: selected.tab)
        let target = try NativeCaptureProof.pinnedTarget(data, expected: expected, pinID: pinID)
        guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
        // Page pin creation required A to be focused; once created, switching to
        // B is allowed. Do not reread activeIdentity here and replace/cancel A.
        trace.record(requestID: requestID.uuidString, action: "pinTarget", phase: "pinned",
            enqueued: eventUptime, started: started, context: nil, succeeded: true)
        return target
    }

    /// Synthetic-only pending candidate. Routing, the small document witness and
    /// MAIN preparation submission run at press with a short deadline. This is
    /// NOT zero main-thread work. All receipt waits/target decoding run off-main.
    /// Real/admitted sources retain the original pinTargetAtPress path above.
    public func prepareClickAtPress(assetID: UUID, program: WebPageProgram, eventUptime: TimeInterval) throws -> PendingWebClick {
        Self.capturePriority.supersede()
        let started = ProcessInfo.processInfo.systemUptime
        guard eventUptime.isFinite, eventUptime >= 0, eventUptime <= started,
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.google.Chrome",
              let identity = ChromeProcessIdentity.read(pid: app.processIdentifier) else { throw WebAdapterError.invalidTarget }
        let id = UUID(), witness = UUID()
        let bridge = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: id.uuidString, deadline: started + 0.15)
        guard identity.isCurrent(), try bridge.frontmost() else { throw WebAdapterError.browserNotFrontmost }
        let selected = try bridge.activeIdentity(check: "press_route")
        guard try bridge.execute(ClickDocumentWitness.install(witness), window: selected.window, tab: selected.tab,
            receiptBudget: .init(deadlineUptime: started + 0.15)) == "ready" else { throw WebAdapterError.pageRejected(.clickRouteUnobserved) }
        guard identity.isCurrent(), try bridge.frontmost(),
              try bridge.activeIdentity(check: "press_route_frozen") == selected else { throw WebAdapterError.nativeSelectionChanged }
        let routeFrozen = ProcessInfo.processInfo.systemUptime
        trace.record(requestID: id.uuidString, action: "pendingClick", phase: "routeFrozen",
            enqueued: eventUptime, started: started, context: nil, succeeded: true)
        let context = Self.contextJSON(session: identity.session, window: selected.window, tab: selected.tab)
        let legacy = identity.legacyLaunchDate.map { "\(identity.pid):\($0.timeIntervalSince1970)" }
        let relay = relays.relay(function: program.functionSource, contextJSON: context, allowCreate: true,
            legacyObservationSession: legacy)!
        let prepare = WebBridgeCommand(action: .prepareClick, clickBindingID: id, documentWitnessID: witness)
        let envelope = MainWorldCommandEnvelope(function: program.functionSource,
            commandJSON: String(decoding: try JSONEncoder().encode(prepare), as: UTF8.self), contextJSON: context)
        if try bridge.execute(relay.probe, window: selected.window, tab: selected.tab,
            receiptBudget: .init(deadlineUptime: started + 0.15)) != "ready" {
            guard try bridge.frontmost(), try bridge.activeIdentity(check: "press_first_install") == selected else {
                throw WebAdapterError.nativeSelectionChanged
            }
            try bridge.submitMainWorld("(()=>{\(relay.installer);return \(relay.dispatch(envelope));})()",
                window: selected.window, tab: selected.tab)
        } else {
            try bridge.dispatchMainWorld(relay.dispatch(envelope), window: selected.window, tab: selected.tab)
        }
        // The preparation command is addressed to original A. Receipt waiting
        // and full target decoding happen asynchronously. A first-install script
        // that loses foreground before snapshot must refuse, never bind B.
        trace.record(requestID: id.uuidString, action: "pendingClick", phase: "mainSubmitted",
            enqueued: eventUptime, started: started, context: nil, succeeded: true)
        return PendingWebClick(id: id, assetID: assetID, session: identity.session,
            window: selected.window, tab: selected.tab, documentWitness: witness, preparation: envelope,
            eventUptime: eventUptime, routeFrozenUptime: routeFrozen)
    }

    public func resolveClick(_ click: PendingWebClick, program: WebPageProgram) async throws -> TargetLease {
        guard click.beginResolution(at: ProcessInfo.processInfo.systemUptime),
              let identity = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
                .compactMap({ ChromeProcessIdentity.read(pid: $0.processIdentifier) })
                .first(where: { $0.session == click.session }) else { throw WebAdapterError.invalidTarget }
        let trace = self.trace, relays = self.relays
        return try await withCheckedThrowingContinuation { continuation in
            Self.clickResolutionQueue.async {
                let started = ProcessInfo.processInfo.systemUptime
                var phase = "originalProcess"
                let result: Result<TargetLease, Error> = Result {
                    try autoreleasepool {
                        guard identity.isCurrent(), click.isValid(at: started) else { throw WebAdapterError.invalidTarget }
                        let bridge = ChromePIDEvents(pid: identity.pid, trace: trace, requestID: click.id.uuidString,
                            deadline: click.deadlineUptime)
                        guard let preparation = click.preparation else { throw WebAdapterError.invalidRequest }
                        phase = "mainPrepared"
                        let prepared = try MainWorldReceiptReader.read(preparation) { budget in
                            try bridge.execute(preparation.reader, window: click.window, tab: click.tab, receiptBudget: budget)
                        }
                        guard let value = try? JSONDecoder().decode(PendingPreparationReceipt.self, from: Data(prepared.text.utf8)),
                              value.prepared == click.id, value.pagePreparedAtMS.isFinite, value.pagePreparedAtMS >= 0,
                              click.isValid(at: ProcessInfo.processInfo.systemUptime) else {
                            throw WebAdapterError.invalidTarget
                        }
                        trace.record(requestID: click.id.uuidString, action: "pendingClick", phase: "mainPrepared",
                            enqueued: click.eventUptime, started: started, context: nil, succeeded: true,
                            pagePreparedAtMS: value.pagePreparedAtMS)
                        let context = Self.contextJSON(session: click.session, window: click.window, tab: click.tab)
                        let legacy = identity.legacyLaunchDate.map { "\(identity.pid):\($0.timeIntervalSince1970)" }
                        let relay = relays.relay(function: program.functionSource, contextJSON: context,
                            allowCreate: true, legacyObservationSession: legacy)!
                        let command = WebBridgeCommand(action: .resolveClick, clickBindingID: click.id,
                            documentWitnessID: click.documentWitness)
                        let envelope = MainWorldCommandEnvelope(function: program.functionSource,
                            commandJSON: String(decoding: try JSONEncoder().encode(command), as: UTF8.self), contextJSON: context)
                        let budget = MainWorldReceiptReadBudget(deadlineUptime: min(click.deadlineUptime, ProcessInfo.processInfo.systemUptime + 1))
                        phase = "mainChannel"
                        guard try bridge.execute(relay.probe, window: click.window, tab: click.tab, receiptBudget: budget) == "ready",
                              click.isValid(at: ProcessInfo.processInfo.systemUptime) else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
                        // Resolution is observation of this already prepared click,
                        // never an installer, active-tab lookup, or registry recapture.
                        try bridge.dispatchMainWorld(relay.dispatch(envelope), window: click.window, tab: click.tab)
                        phase = "pageReceipt"
                        let receipt = try MainWorldReceiptReader.read(envelope) { budget in
                            try bridge.execute(envelope.reader, window: click.window, tab: click.tab, receiptBudget: budget)
                        }
                        let data = Data(receipt.text.utf8)
                        _ = try NativeCaptureProof.digest(data, session: click.session, window: click.window, tab: click.tab)
                        let target = try JSONDecoder().decode(TargetLease.self, from: data)
                        guard target.clickBindingID == click.id, identity.isCurrent(),
                              click.isValid(at: ProcessInfo.processInfo.systemUptime) else { throw WebAdapterError.invalidTarget }
                        phase = "resolved"
                        return target
                    }
                }
                if (try? result.get()) == nil { click.cancel() }
                trace.record(requestID: click.id.uuidString, action: "pendingClick", phase: phase,
                    enqueued: click.eventUptime, started: started, context: nil, succeeded: (try? result.get()) != nil)
                continuation.resume(with: result)
            }
        }
    }

    private nonisolated static func contextJSON(session: String, window: String, tab: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try! encoder.encode(["applicationID":"com.google.Chrome", "sessionID":session,
            "windowID":window, "tabID":tab]), as: UTF8.self)
    }

    public func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        guard command.action != .pinTarget, command.action != .prepareClick, command.action != .resolveClick else { throw WebAdapterError.invalidRequest }
        let browserID = "com.google.Chrome"
        let application: NSRunningApplication
        if command.action == .captureTarget {
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.bundleIdentifier == browserID else { throw WebAdapterError.browserNotFrontmost }
            application = frontmost
        } else {
            guard let target = command.target, target.applicationID == browserID,
                  let running = NSRunningApplication.runningApplications(withBundleIdentifier: browserID).first(where: {
                      ChromeProcessIdentity.read(pid: $0.processIdentifier)?.matches(
                          session: target.sessionID, allowLegacyObservation: command.action == .observe) == true
                  }) else { throw WebAdapterError.invalidTarget }
            application = running
        }
        guard let identity = ChromeProcessIdentity.read(pid: application.processIdentifier) else {
            throw WebAdapterError.invalidTarget
        }
        let pid = identity.pid
        // Original operation identity remains unchanged for legacy read-only observation.
        let session = command.action == .captureTarget ? identity.session : (command.target?.sessionID ?? "")
        let requiresForeground = ChromeCommandRouting.requiresForeground(command.action, target: command.target)
        if requiresForeground {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                throw WebAdapterError.browserNotFrontmost
            }
        }
        if command.action != .captureTarget {
            guard let target = command.target,
                  identity.matches(session: target.sessionID, allowLegacyObservation: command.action == .observe),
                  let windowID = Int64(target.windowID), windowID > 0,
                  let tab = target.tabID, let tabID = Int64(tab), tabID > 0 else {
                throw WebAdapterError.invalidTarget
            }
        }
        let commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        let captureContext = command.action == .captureTarget ? command.captureInvocation : nil
        let requestID = captureContext?.requestID.uuidString ?? UUID().uuidString
        let enqueued = ProcessInfo.processInfo.systemUptime
        // Mark queued discoveries obsolete before waiting behind them. No input,
        // discard or UNKNOWN observation receives a cancellation ticket.
        if command.target?.clickBindingID != nil,
           [.validate, .begin, .chunk, .commit].contains(command.action) {
            Self.capturePriority.supersede()
        }
        let captureTicket = command.action == .captureTarget ? Self.capturePriority.ticket() : nil
        let trace = self.trace
        let observedRoutes = self.observedRoutes
        let relays = self.relays
        let delivery: ChromeDelivery = try await withCheckedThrowingContinuation { continuation in
            Self.scriptQueue.async {
                let started = ProcessInfo.processInfo.systemUptime
                var phase = "process"
                let result: Result<ChromeDelivery, Error> = Result {
                    try autoreleasepool {
                        try captureTicket?.check()
                        // Recheck process lifetime after waiting for the shared serial
                        // queue. An old lease cannot target a newly reused PID.
                        guard identity.isCurrent() else {
                            throw WebAdapterError.invalidTarget
                        }
                        let bridge = ChromePIDEvents(pid: pid, trace: trace, requestID: requestID,
                            captureTicket: captureTicket)
                        phase = "foreground"
                        if requiresForeground, try !bridge.frontmost() { throw WebAdapterError.browserNotFrontmost }
                        phase = "selection"
                        let selected: (window: String, tab: String)
                        if command.action == .captureTarget {
                            selected = try bridge.activeIdentity(check: "capture_selection")
                            try captureTicket?.whileCurrent {
                                observedRoutes.recordRoute(session: session, window: selected.window, tab: selected.tab,
                                    uptime: ProcessInfo.processInfo.systemUptime)
                            }
                        } else {
                            guard let target = command.target, let tab = target.tabID else { throw WebAdapterError.invalidTarget }
                            selected = (target.windowID, tab)
                            if requiresForeground {
                                let active = try bridge.activeIdentity(check: "input_selection")
                                guard active.window == selected.window, active.tab == selected.tab else {
                                    throw WebAdapterError.nativeSelectionChanged
                                }
                            }
                        }
                        let context = Self.contextJSON(session: identity.session, window: selected.window, tab: selected.tab)
                        // Chrome's execute-JavaScript event is isolated-world. The
                        // observed composer business identity lives in MAIN. Submit
                        // exactly once, then only read its nonce-bound DOM receipt.
                        let envelope = MainWorldCommandEnvelope(function: program.functionSource,
                            commandJSON: commandJSON, contextJSON: context)
                        phase = "submit"
                        guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
                        let legacySession = identity.legacyLaunchDate.flatMap { date in
                            date.timeIntervalSince1970.isFinite ? "\(pid):\(date.timeIntervalSince1970)" : nil
                        }
                        var foundRelay = relays.relay(function: program.functionSource, contextJSON: context,
                            allowCreate: false, legacyObservationSession: legacySession)
                        if foundRelay == nil, command.action == .observe || command.action == .captureTarget {
                            let expectedRelay = MainWorldCommandRelay(function: program.functionSource,
                                contextJSON: context, legacyObservationSession: legacySession)
                            let channel = try bridge.execute(expectedRelay.discovery, window: selected.window, tab: selected.tab,
                                receiptBudget: .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 1))
                            guard channel != "ambiguous" else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
                            foundRelay = relays.adopt(function: program.functionSource, contextJSON: context,
                                channel: channel, legacyObservationSession: legacySession)
                        }
                        if command.action == .captureTarget, foundRelay == nil || (legacySession != nil && foundRelay?.legacyObservationSession != legacySession) {
                            foundRelay = relays.relay(function: program.functionSource, contextJSON: context,
                                allowCreate: true, legacyObservationSession: legacySession)
                        }
                        guard let relay = foundRelay else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
                        if command.action == .captureTarget,
                           try bridge.execute(relay.probe, window: selected.window, tab: selected.tab,
                               receiptBudget: .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 1)) != "ready" {
                            // Installation is foreground-only. Never repair a missing
                            // background endpoint by a URL setter that raises Chrome.
                            guard try bridge.frontmost(), try bridge.activeIdentity(check: "relay_install") == selected else {
                                throw WebAdapterError.nativeSelectionChanged
                            }
                            let installAndCapture = "(()=>{\(relay.installer);return \(relay.dispatch(envelope));})()"
                            try bridge.submitMainWorld(installAndCapture, window: selected.window, tab: selected.tab)
                        } else {
                            try bridge.dispatchMainWorld(relay.dispatch(envelope), window: selected.window, tab: selected.tab)
                        }
                        phase = "receipt"
                        let receipt = try MainWorldReceiptReader.read(envelope,
                            checkContinuation: { try captureTicket?.check() }) { budget in
                            try bridge.execute(envelope.reader, window: selected.window, tab: selected.tab,
                                               receiptBudget: budget)
                        }
                        guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
                        let received = receipt.receivedUptime
                        // Missing/late reply never resubmits an input command.
                        let text = receipt.text
                        guard text.utf8.count <= ObservationDecoder.maximumPayloadBytes else { throw WebAdapterError.invalidReply }
                        let bytes = Data(text.utf8)
                        var targetDigest: String?
                        if command.action == .captureTarget {
                            targetDigest = try NativeCaptureProof.digest(bytes, session: session, window: selected.window, tab: selected.tab)
                            // Publish only decoded, native-context-matched identity,
                            // independently of the later active-tab check/App ACK.
                            // It grants nothing until a press pins this exact page.
                            let capturedTarget = try JSONDecoder().decode(TargetLease.self, from: bytes)
                            try captureTicket?.whileCurrent { observedRoutes.record(capturedTarget, uptime: received) }
                            // Do not publish an ACK already known to be stale:
                            // selecting another tab while the receipt was pending
                            // is a different target even in the same Chrome PID.
                            phase = "capture_return_selection"
                            let active = try bridge.activeIdentity(check: "capture_return_selection")
                            guard active == selected else { throw WebAdapterError.nativeSelectionChanged }
                        }
                        phase = "complete"
                        let validated = ProcessInfo.processInfo.systemUptime
                        try captureTicket?.check()
                        if let targetDigest {
                            trace.capture(requestID: requestID, phase: "native_validated", digest: targetDigest,
                                          received: received, validated: validated, context: captureContext, accepted: true)
                        }
                        return ChromeDelivery(data: bytes, targetDigest: targetDigest, received: received, validated: validated)
                    }
                }
                trace.record(requestID: requestID, action: command.action.rawValue, phase: phase, enqueued: enqueued, started: started,
                             context: captureContext, succeeded: (try? result.get()) != nil)
                continuation.resume(with: result)
            }
        }
        try captureTicket?.check()
        if command.action == .captureTarget {
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.processIdentifier == pid, identity.isCurrent() else {
                if let digest = delivery.targetDigest {
                    trace.capture(requestID: requestID, phase: "main_actor_return", digest: digest, received: delivery.received,
                                  validated: delivery.validated, context: captureContext, accepted: false)
                }
                throw WebAdapterError.browserNotFrontmost
            }
            let returned = ProcessInfo.processInfo.systemUptime
            if let digest = delivery.targetDigest {
                trace.capture(requestID: requestID, phase: "main_actor_return", digest: digest, received: delivery.received,
                              validated: delivery.validated, context: captureContext, accepted: true, mainReturned: returned)
            }
        }
        guard identity.isCurrent() else { throw WebAdapterError.invalidTarget }
        return delivery.data
    }
}

private struct PendingPreparationReceipt: Decodable {
    let prepared: UUID
    let pagePreparedAtMS: Double
}

private struct ChromeDelivery: Sendable {
    let data: Data
    let targetDigest: String?
    let received: TimeInterval
    let validated: TimeInterval
}

/// Local opt-in timing only; opaque digest, never raw source/URL/identity/payload.
private final class ChromeBridgeTrace: @unchecked Sendable {
    private let enabled: Bool
    private let lock = NSLock()
    private var count = 0
    init(enabled: Bool) { self.enabled = enabled }
    func capture(requestID: String, phase: String, digest: String, received: TimeInterval,
                 validated: TimeInterval, context: CaptureInvocationContext?, accepted: Bool,
                 mainReturned: TimeInterval? = nil) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        guard count < 2048 else { return }; count += 1
        let now = ProcessInfo.processInfo.systemUptime
        var fields: [String: Any] = ["event": "capture_ack", "requestID": requestID, "phase": phase,
            "targetDigest": digest, "receivedUptime": received, "nativeReceivedUptime": received,
            "nativeValidatedUptime": validated, "recordedUptime": now, "accepted": accepted,
            "authority": "DIAGNOSTIC_ONLY_NOT_APP_PUBLICATION"]
        if let mainReturned, accepted { fields["executorMainReturnedUptime"] = mainReturned }
        addContext(context, to: &fields)
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
            try? FileHandle.standardError.write(contentsOf: data + Data([10]))
        }
    }
    func record(requestID: String, action: String, phase: String, enqueued: TimeInterval, started: TimeInterval,
                context: CaptureInvocationContext?, succeeded: Bool, pagePreparedAtMS: Double? = nil) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        guard count < 2048 else { return }; count += 1
        let end = ProcessInfo.processInfo.systemUptime
        var fields: [String: Any] = ["event": "native_bridge", "requestID": requestID, "action": action, "phase": phase,
            "queuedUptime": enqueued, "startedUptime": started, "endedUptime": end,
            "queueMS": (started - enqueued) * 1000, "executionMS": (end - started) * 1000, "transportSucceeded": succeeded]
        if let pagePreparedAtMS { fields["pagePreparedAtMS"] = pagePreparedAtMS; fields["pageClockDomain"] = "document-performance-now" }
        addContext(context, to: &fields)
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
            try? FileHandle.standardError.write(contentsOf: data + Data([10]))
        }
    }

    func activeIdentity(requestID: String, check: String, route: String, started: TimeInterval, succeeded: Bool) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        guard count < 2048 else { return }; count += 1
        let fields: [String: Any] = ["event": "active_identity", "requestID": requestID,
            "check": check, "route": route, "elapsedMS": (ProcessInfo.processInfo.systemUptime - started) * 1000,
            "succeeded": succeeded, "authority": "DIAGNOSTIC_ONLY"]
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
            try? FileHandle.standardError.write(contentsOf: data + Data([10]))
        }
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

/// Codes come from Chrome's installed scripting.sdef (Standard/Chromium suites),
/// not undocumented browser internals. Submission and identity reads retain the
/// five-second per-event timeout; receipt reads use their remaining one-second
/// budget. This never activates or sends a ChatGPT message. The URL setter
/// receives only a void JavaScript expression, not a navigation URL.
private struct ChromePIDEvents {
    let pid: pid_t
    let trace: ChromeBridgeTrace
    let requestID: String
    var deadline: TimeInterval? = nil
    var captureTicket: CaptureReadPriority.Ticket? = nil
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
                      javascript: String? = nil, value: String? = nil,
                      receiptBudget: MainWorldReceiptReadBudget? = nil) throws -> NSAppleEventDescriptor {
        let request = NSAppleEventDescriptor(eventClass: code(suite), eventID: code(event),
            targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
        request.setParam(direct, forKeyword: code("----"))
        if let javascript { request.setParam(.init(string: javascript), forKeyword: code("JvSc")) }
        if let value { request.setParam(.init(string: value), forKeyword: code("data")) }
        var timeout: TimeInterval
        if let receiptBudget {
            timeout = try receiptBudget.timeout(at: ProcessInfo.processInfo.systemUptime)
        } else { timeout = 5 }
        if let deadline {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining >= 0.05 else { throw WebAdapterError.nativeExecutionFailed }
            timeout = min(timeout, remaining)
        }
        try captureTicket?.check()
        let reply: NSAppleEventDescriptor
        do { reply = try request.sendEvent(options: [.waitForReply], timeout: timeout) }
        catch {
            // Never surface the native localized description: it can contain
            // script source, user paths or page payload. A numeric OSStatus is
            // sufficient to distinguish denied Automation from timeout/transport.
            let native = error as NSError
            guard native.domain == NSOSStatusErrorDomain,
                  let status = Int32(exactly: native.code) else { throw WebAdapterError.nativeExecutionFailed }
            throw WebAdapterError.nativeEventFailed(status)
        }
        try captureTicket?.check()
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
            throw WebAdapterError.nativeEventFailed(error.int32Value)
        }
        guard let result = reply.paramDescriptor(forKeyword: code("----")) else {
            if value != nil { return .null() }
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

    func frontmost() throws -> Bool { try get(property("pisf")).booleanValue }

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
        let windowID = try identifier(front)
        // Resolve the tab from the captured window, not a second front-window read.
        let window = try object("cwin", form: "ID  ", key: .init(string: windowID))
        let active = try get(property("acTa", of: window))
        let tabID = try identifier(active)
        succeeded = true
        return (windowID, tabID)
    }

    func execute(_ source: String, window: String, tab: String,
                 receiptBudget: MainWorldReceiptReadBudget) throws -> String {
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
