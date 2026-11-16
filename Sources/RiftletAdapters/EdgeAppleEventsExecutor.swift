import Foundation
import RiftletCore

/// Cancellation only controls work that has not entered its one native
/// submission. It never supplies a negative-input receipt after that boundary.
private final class EdgeCommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var submitted = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func checkBeforeSubmission() throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
    }
    func enterSubmission() throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        guard !submitted else { throw WebAdapterError.invalidRequest }
        submitted = true
    }
}

/// The ordinary Edge candidate implements the same input/receipt protocol as
/// Chrome, using Edge's independently addressed native receiver. It never
/// decides upload START, completion or retry admission; WebAttachmentAdapter
/// and Core retain those decisions and the original durable operation.
@MainActor public final class EdgeAppleEventsExecutor: WebClickTargetPinning {
    private struct Click: Sendable {
        let host: EdgeWindowTab
        let world: EdgeExecutionWorldWitness
        let captured: TimeInterval
    }
    private nonisolated static let commandQueue = DispatchQueue(label: "com.riftlet.edge-input", qos: .userInitiated)
    private nonisolated static let observationQueue = DispatchQueue(label: "com.riftlet.edge-observation", qos: .utility)
    private let driver: any EdgeWebExecutionDriver
    private let relays = MainWorldRelayStore()
    private let diagnosticTrace: BoundedDiagnosticTrace?
    private var clicks: [String: Click] = [:]
    private var committed = Set<UUID>()

    public convenience init(diagnosticTrace: BoundedDiagnosticTrace? = nil) {
        self.init(driver: NativeEdgeWebExecutionDriver(), diagnosticTrace: diagnosticTrace)
    }

    init(driver: any EdgeWebExecutionDriver, diagnosticTrace: BoundedDiagnosticTrace? = nil) {
        self.driver = driver; self.diagnosticTrace = diagnosticTrace
    }

    public func targetForClick(program: WebPageProgram) throws -> Task<TargetLease, Error> {
        try Task.checkCancellation()
        guard program.sourceID == ChatGPTWebPageProgram.sourceID else { throw WebAdapterError.invalidRequest }
        let started = ProcessInfo.processInfo.systemUptime
        let budget = MainWorldReceiptReadBudget.clickSnapshot(start: started)
        let deadline = budget.deadlineUptime
        var phase = "nativeIdentity"
        var phaseStarted = started
        var timings: [String: Double] = [:]
        defer {
            if let diagnosticTrace {
                let finished = ProcessInfo.processInfo.systemUptime
                var fields: [String: Any] = ["event": "edge_click_pin", "phase": phase,
                    "succeeded": phase == "pinned", "elapsedMS": (finished - started) * 1000,
                    "phaseElapsedMS": (finished - phaseStarted) * 1000]
                for (key, value) in timings { fields[key] = value }
                diagnosticTrace.record(fields)
            }
        }
        let host = try driver.freeze(deadline: deadline)
        timings["nativeIdentityMS"] = (ProcessInfo.processInfo.systemUptime - started) * 1000
        let address = try ChromeClickRoute.chatGPT(window: host.windowID, tab: host.tabID, url: host.address).address
        let witness = ChromeClickDocumentWitness(), world = EdgeExecutionWorldWitness()
        phase = "documentEditorPin"
        phaseStarted = ProcessInfo.processInfo.systemUptime
        guard try driver.evaluate(world.prepareAndBind(witness, address: address, program: program),
                                  target: host, budget: budget) == "bound"
        else { throw WebAdapterError.pageRejected(.clickPinRefused) }
        let pinned = ProcessInfo.processInfo.systemUptime
        timings["documentPinMS"] = (pinned - phaseStarted) * 1000
        timings["documentPinElapsedMS"] = (pinned - started) * 1000
        phase = "originalSelectionRecheck"
        phaseStarted = pinned
        // Address and original document/editor were just bound above. Avoid
        // repeating the three-read freeze on the UI thread; the worker still
        // performs full revalidate before capture and every attachment command.
        try driver.recheckClickSelection(host, deadline: deadline)
        let rechecked = ProcessInfo.processInfo.systemUptime
        timings["selectionRecheckMS"] = (rechecked - phaseStarted) * 1000
        timings["selectionRecheckElapsedMS"] = (rechecked - started) * 1000
        try budget.checkReturn(at: ProcessInfo.processInfo.systemUptime)
        phase = "pinned"
        let click = Click(host: host, world: world, captured: started)
        let driver = self.driver, relays = self.relays, trace = diagnosticTrace
        return Task { [weak self] in
            try Task.checkCancellation()
            let command = WebBridgeCommand(action: .captureTarget, clickWitnessID: witness.id)
            let data = try await Self.run(command, program: program, host: host, click: click,
                                          driver: driver, relays: relays, trace: trace)
            try Task.checkCancellation()
            let target = try Self.decodeCapture(data, host: host, witnessID: witness.id)
            guard let self, ProcessInfo.processInfo.systemUptime - started < 60 else { throw WebAdapterError.invalidTarget }
            self.clicks = self.clicks.filter { ProcessInfo.processInfo.systemUptime - $0.value.captured < 60 }
            self.clicks[target.stableKey] = click
            return target
        }
    }

    public func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        try Task.checkCancellation()
        guard command.action != .pinTarget,
              program.sourceID == ChatGPTWebPageProgram.sourceID ||
                (command.action == .observe && program.sourceID == ChatGPTWebPageProgram.priorClickSource) else {
            throw WebAdapterError.invalidRequest
        }
        if command.action == .captureTarget {
            try Task.checkCancellation()
            let original = try targetForClick(program: program)
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let target = try await original.value
                try Task.checkCancellation()
                return try JSONEncoder().encode(target)
            } onCancel: { original.cancel() }
        }
        guard let target = command.target, target.adapterID == "chatgpt-web", target.surface == .webChat,
              target.applicationID == EdgeApplicationHost.bundleID, let tab = target.tabID,
              let host = driver.recover(session: target.sessionID, window: target.windowID, tab: tab) else {
            throw WebAdapterError.invalidTarget
        }
        let click = clicks[target.stableKey].flatMap {
            ProcessInfo.processInfo.systemUptime - $0.captured < 60 ? $0 : nil
        }
        // Restart has no input capability. Only original observation may recover
        // a stored process/window/tab; capture, begin and commit are never inferred.
        guard command.action == .observe || click != nil else { throw WebAdapterError.invalidTarget }
        if [.begin, .chunk, .commit, .discard, .observe].contains(command.action) {
            guard let identity = command.identity, identity.target == target else { throw WebAdapterError.invalidRequest }
            if [.begin, .chunk, .commit].contains(command.action), committed.contains(identity.operationID) {
                throw WebAdapterError.invalidRequest
            }
            if command.action == .commit {
                guard command.invocationID != nil else { throw WebAdapterError.invalidRequest }
                // Enter once BEFORE any async work. A lost native/reply result
                // never permits another commit, even with another invocation ID.
                committed.insert(identity.operationID)
            }
        }
        return try await Self.run(command, program: program, host: click?.host ?? host, click: click,
                                  driver: driver, relays: relays, trace: diagnosticTrace)
    }

    private nonisolated static func isTemporaryHome(_ address: String) -> Bool {
        guard let url = URLComponents(string: address) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == "chatgpt.com"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
            && (url.percentEncodedPath.isEmpty || url.percentEncodedPath == "/")
            && url.percentEncodedQuery == "temporary-chat=true" && url.fragment == nil
    }

    private nonisolated static func decodeCapture(_ data: Data, host: EdgeWindowTab, witnessID: UUID) throws -> TargetLease {
        guard data.count <= ObservationDecoder.maximumPayloadBytes,
              let target = try? JSONDecoder().decode(TargetLease.self, from: data),
              target.adapterID == "chatgpt-web", target.surface == .webChat,
              target.applicationID == EdgeApplicationHost.bundleID, target.sessionID == host.sessionID,
              target.windowID == host.windowID, target.tabID == host.tabID, target.clickBindingID == witnessID,
              target.webDraftRoute == nil || (target.webDraftRoute == .chatGPTTemporaryHome && isTemporaryHome(host.address)),
              !target.documentID.isEmpty, !target.composerID.isEmpty, !target.draftGeneration.isEmpty else {
            throw WebAdapterError.invalidTarget
        }
        return target
    }

    private nonisolated static func run(_ command: WebBridgeCommand, program: WebPageProgram,
        host: EdgeWindowTab, click: Click?, driver: any EdgeWebExecutionDriver,
        relays: MainWorldRelayStore, trace: BoundedDiagnosticTrace?) async throws -> Data {
        let json = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let context = String(decoding: try encoder.encode([
            "applicationID": EdgeApplicationHost.bundleID, "sessionID": host.sessionID,
            "windowID": host.windowID, "tabID": host.tabID]), as: UTF8.self)
        let queue = command.action == .observe ? observationQueue : commandQueue
        let cancellation = EdgeCommandCancellation()
        return try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var phase = "process"
                let result: Result<Data, Error> = Result {
                    try autoreleasepool {
                        func read(_ script: String, budget: MainWorldReceiptReadBudget? = nil,
                                  afterSubmission: Bool = false) throws -> String {
                            if !afterSubmission { try cancellation.checkBeforeSubmission() }
                            guard driver.isCurrent(host) else { throw WebAdapterError.invalidTarget }
                            return try driver.evaluate(script, target: host, budget: budget ??
                                .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 1))
                        }
                        func selection() throws {
                            try cancellation.checkBeforeSubmission()
                            guard driver.isCurrent(host) else { throw WebAdapterError.invalidTarget }
                            guard command.action != .observe else { return }
                            guard let click, ProcessInfo.processInfo.systemUptime - click.captured < 60 else {
                                throw WebAdapterError.invalidTarget
                            }
                            try driver.revalidate(click.host, deadline: ProcessInfo.processInfo.systemUptime + 1)
                        }
                        try selection()
                        if command.action == .captureTarget {
                            guard let click else { throw WebAdapterError.invalidTarget }
                            phase = "executionWorld"
                            // No attachment command has been sent. Same-world,
                            // replaced-document and blocked-bootstrap outcomes refuse.
                            try cancellation.checkBeforeSubmission()
                            try driver.bootstrap(click.world.bootstrap, target: host)
                            guard try read(click.world.confirm) == "verified" else {
                                throw WebAdapterError.pageRejected(.bridgeUnavailable)
                            }
                            try selection()
                        }
                        let envelope = MainWorldCommandEnvelope(function: program.functionSource,
                            commandJSON: json, contextJSON: context)
                        phase = "originalRelay"
                        let relay = try relays.resolve(command, program: program, contextJSON: context) { discovery in
                            try read(discovery)
                        }
                        var install = false
                        if command.action == .captureTarget { install = try read(relay.probe) != "ready" }
                        try selection()
                        if command.action != .observe {
                            guard let click, try read(click.world.validate) == "verified" else {
                                throw WebAdapterError.pageRejected(.clickPinRefused)
                            }
                            try selection()
                        }
                        phase = "submit"
                        // This is the final cancellation boundary. After entering
                        // the native call, preserve its exact original receipt even
                        // if the caller cancels; never report pre-input cancellation.
                        try cancellation.enterSubmission()
                        if install {
                            // Only capture may initialize MAIN. No failed dispatch
                            // or file input ever falls back to another world/path.
                            try driver.bootstrap("(()=>{\(relay.installer);return \(relay.dispatch(envelope));})()", target: host)
                        } else {
                            guard try read(relay.dispatch(envelope), budget:
                                .init(deadlineUptime: ProcessInfo.processInfo.systemUptime + 5, clickSnapshot: true),
                                afterSubmission: true) == "submitted"
                            else { throw WebAdapterError.nativeExecutionFailed }
                        }
                        phase = "receipt"
                        let receipt = try MainWorldReceiptReader.read(envelope,
                            timeout: command.action == .commit ? 8 : 1,
                            checkContinuation: { guard driver.isCurrent(host) else { throw WebAdapterError.invalidTarget } }) { budget in
                                try read(envelope.reader, budget: budget, afterSubmission: true)
                            }
                        guard driver.isCurrent(host), receipt.text.utf8.count <= ObservationDecoder.maximumPayloadBytes else {
                            throw WebAdapterError.invalidReply
                        }
                        let data = Data(receipt.text.utf8)
                        if command.action == .captureTarget {
                            try selection()
                            guard let id = command.clickWitnessID, let click,
                                  try read(click.world.validate) == "verified" else { throw WebAdapterError.invalidTarget }
                            let target = try decodeCapture(data, host: host, witnessID: id)
                            relays.bind(relay, to: target)
                        }
                        phase = "complete"
                        return data
                    }
                }
                var fields: [String: Any] = ["event": "edge_web_command", "action": command.action.rawValue,
                    "phase": phase, "succeeded": (try? result.get()) != nil]
                if case .failure(let error) = result { fields["error"] = NativeEdgeWebExecutionDriver.mapped(error).diagnosticLabel }
                trace?.record(fields, critical: command.action != .observe && command.action != .captureTarget)
                continuation.resume(with: result)
            }
          }
        } onCancel: {
            cancellation.cancel()
        }
    }
}
