import Darwin
import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

private final class EdgeExecutorFixture: EdgeWebExecutionDriver, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    let host: EdgeWindowTab
    var failNextOriginalProcessRead = false
    var nextDescriptorFailure: EdgeDescriptorFailure?
    var selected = true, alive = true, worldSeparated = true, replaceAtPin = false
    var wrongCaptureWindow = false, loseCommitReply = false, latePin = false
    var navigated = false, originalDocumentCurrent = true
    var modelClickBudget = false
    var modeledPinDuration: TimeInterval = 0.024
    private var modeledUptime: TimeInterval?
    private(set) var synchronousEvaluations = 0
    var atPin: (() -> Void)?
    var atCommit: (() -> Void)?
    var worldBootstrapEntered: DispatchSemaphore?, releaseWorldBootstrap: DispatchSemaphore?
    var revalidateEntered: DispatchSemaphore?, releaseRevalidate: DispatchSemaphore?, recovered: DispatchSemaphore?
    private var currentPin: UUID?
    private var replies: [String: String] = [:]
    private var relayMarker: String?
    private(set) var actions: [String] = []
    private(set) var bootstraps = 0, selectionChecks = 0
    private(set) var fullSelectionChecks = 0, clickSelectionChecks = 0
    private var relayChannel: String?

    var returnedRoute: WebDraftRoute?
    init(address: String = "https://chatgpt.com/c/neutral") {
        var record = proc_bsdinfo(); record.pbi_pid = 71; record.pbi_start_tvsec = 10
        let birth = KernelProcessBirth(requestedPID: 71, record: record, bytesRead: Int32(MemoryLayout.size(ofValue: record)))!
        host = EdgeWindowTab(process: birth, windowID: "13", tabID: "45", address: address)
    }
    func freeze(deadline: TimeInterval) throws -> EdgeWindowTab {
        try revalidate(host, deadline: deadline)
        if modelClickBudget { modeledUptime = deadline - 0.15 + 0.045 }
        return host
    }
    func revalidate(_ target: EdgeWindowTab, deadline: TimeInterval,
                    descriptorFailure: (EdgeDescriptorFailure) -> Void) throws {
        lock.lock(); defer { lock.unlock() }; selectionChecks += 1; fullSelectionChecks += 1
        if let failure = nextDescriptorFailure {
            nextDescriptorFailure = nil
            descriptorFailure(failure)
            throw NativeEdgeWebExecutionDriver.mapped(EdgeHostError.unsupportedDescriptor(failure))
        }
        revalidateEntered?.signal()
        if let releaseRevalidate, releaseRevalidate.wait(timeout: .now() + 3) != .success {
            throw WebAdapterError.nativeExecutionFailed
        }
        guard alive, selected, !navigated, target == host else { throw WebAdapterError.nativeSelectionChanged }
        if let now = modeledUptime {
            // Three native identity reads still run, each requiring >=50 ms
            // before dispatch. No sleep or CI wall-clock performance assumption.
            for index in 0..<3 {
                guard deadline - (now + Double(index) * 0.015) >= 0.05 else {
                    throw WebAdapterError.nativeEventFailed(-1712)
                }
            }
            modeledUptime = now + 0.045
        }
    }
    func recheckClickSelection(_ target: EdgeWindowTab, deadline: TimeInterval) throws {
        lock.lock(); defer { lock.unlock() }; selectionChecks += 1; clickSelectionChecks += 1
        guard alive, selected, target == host else { throw WebAdapterError.nativeSelectionChanged }
        if let now = modeledUptime {
            guard deadline - now >= 0.05 else { throw WebAdapterError.nativeEventFailed(-1712) }
            modeledUptime = now + 0.015
        }
    }
    func isCurrent(_ target: EdgeWindowTab) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if failNextOriginalProcessRead { failNextOriginalProcessRead = false; return false }
        return alive && target.process == host.process
    }
    func retainInstalledRelay(_ relay: MainWorldCommandRelay) {
        relayChannel = relay.channel
        relayMarker = relay.marker
    }
    func recover(session: String, window: String, tab: String) -> EdgeWindowTab? {
        lock.lock(); defer { lock.unlock() }
        recovered?.signal()
        return alive && session == host.sessionID && window == host.windowID && tab == host.tabID ? host : nil
    }
    func evaluate(_ source: String, target: EdgeWindowTab, budget: MainWorldReceiptReadBudget) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard target == host, alive else { throw WebAdapterError.invalidTarget }
        if source.contains("edge-world-prepare") || source.contains("action:'pinTarget'") {
            synchronousEvaluations += 1
            if let now = modeledUptime {
                _ = try budget.timeout(at: now)
                modeledUptime = now + modeledPinDuration
            }
        }
        if source.contains("edge-world-prepare"), !source.contains("edge-click-prepare-and-pin") { return "prepared" }
        if source.contains("action:'pinTarget'") {
            let match = try match("clickWitnessID:'([^']+)'", source)
            currentPin = UUID(uuidString: match[0])
            if replaceAtPin { selected = false }
            if latePin { Thread.sleep(forTimeInterval: 0.16) }
            atPin?()
            return "bound"
        }
        if source.contains("edge-world-confirm") || source.contains("edge-world-validate") {
            return worldSeparated && originalDocumentCurrent ? "verified" : "refused"
        }
        if source.contains("root.attributes.length>1024") {
            guard let relayMarker, let relayChannel, source.contains(relayMarker) else { return "" }
            return relayChannel
        }
        if source.contains("?'ready':'missing'") { return relayChannel == nil ? "missing" : "ready" }
        if source.contains("data-riftlet-reply-") && !source.contains("riftlet-command-") {
            let nonce = try match("data-riftlet-reply-([a-f0-9-]+)", source)[0]
            return replies[nonce] ?? ""
        }
        return try dispatch(source)
    }
    func bootstrap(_ source: String, target: EdgeWindowTab) throws {
        lock.lock(); defer { lock.unlock() }; bootstraps += 1
        guard target == host, alive, selected else { throw WebAdapterError.nativeSelectionChanged }
        if source.contains("edge-world-bootstrap") {
            worldBootstrapEntered?.signal()
            if let releaseWorldBootstrap, releaseWorldBootstrap.wait(timeout: .now() + 3) != .success {
                throw WebAdapterError.nativeExecutionFailed
            }
            return
        }
        relayChannel = try match("data-riftlet-channel-([a-f0-9-]+)", source)[0]
        relayMarker = try match("marker='([a-f0-9]{64})'", source)[0]
        _ = try dispatch(source)
    }
    private func dispatch(_ source: String) throws -> String {
        let pieces = try match("\\{nonce:'([^']+)',command:(\\{[^\\n]*\\})\\}\\)", source)
        let command = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(pieces[1].utf8)) as? [String: Any])
        let action = try XCTUnwrap(command["action"] as? String)
        actions.append(action)
        let result: Any
        if action == "captureTarget" {
            let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.microsoft.edgemac",
                sessionID: host.sessionID, windowID: wrongCaptureWindow ? "14" : host.windowID, tabID: host.tabID,
                documentID: "original-document", composerID: "original-editor", draftGeneration: "original-draft",
                clickBindingID: try XCTUnwrap(currentPin), webDraftRoute: returnedRoute)
            result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(target))
        } else { result = ["original": true] }
        replies[pieces[0]] = String(decoding: try JSONSerialization.data(withJSONObject:
            ["nonce": pieces[0], "ok": true, "result": result]), as: UTF8.self)
        if action == "commit" { atCommit?() }
        if action == "commit", loseCommitReply {
            loseCommitReply = false
            throw WebAdapterError.nativeEventFailed(-1712)
        }
        return "submitted"
    }
    private func match(_ pattern: String, _ source: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let found = try XCTUnwrap(expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        return try (1..<found.numberOfRanges).map { index in
            String(source[try XCTUnwrap(Range(found.range(at: index), in: source))])
        }
    }
}

final class EdgeAppleEventsExecutorTests: XCTestCase {
    private let program = WebPageProgram(sourceID: ChatGPTWebPageProgram.sourceID, functionSource: "function fixture(){return {};}")
    private func identity(_ target: TargetLease) -> ObservationIdentity {
        .init(operationID: UUID(), assetID: UUID(), attempt: 1, assetSHA256: String(repeating: "a", count: 64), target: target)
    }

    @MainActor func testPreDispatchChunkRefusalReportsOriginalCheckWithoutSending() async throws {
        let cases: [(failure: EdgeDescriptorFailure?, expected: String)] = [
            (nil, "processIdentity"), (.objectConstruction, "objectConstruction"),
            (.activeTabReplyMissing, "activeTabReplyMissing"), (.addressReplyMissing, "addressReplyMissing"),
            (.activeTabIdentity, "activeTabIdentity"), (.addressValue, "addressValue")
        ]
        for item in cases {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let trace = BoundedDiagnosticTrace(enabled: true, directory: directory, emitStandardError: false)
            let driver = EdgeExecutorFixture()
            let bridge = EdgeAppleEventsExecutor(driver: driver, diagnosticTrace: trace)
            let target = try await bridge.targetForClick(program: program).value
            let operation = identity(target)
            _ = try await bridge.execute(.init(action: .begin, target: target, identity: operation), program: program)
            func chunk(_ index: Int) -> WebBridgeCommand {
                .init(action: .chunk, target: target, identity: operation, chunkIndex: index, chunkBase64: "AQ==")
            }
            for index in 0..<4 { _ = try await bridge.execute(chunk(index), program: program) }
            if let failure = item.failure { driver.nextDescriptorFailure = failure }
            else { driver.failNextOriginalProcessRead = true }
            do {
                _ = try await bridge.execute(chunk(4), program: program)
                XCTFail("a missing native witness must refuse before this chunk")
            } catch { XCTAssertEqual(error as? WebAdapterError, .invalidTarget) }
            XCTAssertEqual(driver.actions, ["captureTarget", "begin", "chunk", "chunk", "chunk", "chunk"])
            trace.flushForTesting()
            let data = try Data(contentsOf: directory.appendingPathComponent("acceptance-recent.jsonl"))
            let rows = try data.split(separator: 10).map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String:Any]) }
            let row = try XCTUnwrap(rows.last)
            XCTAssertEqual(row["action"] as? String, "chunk")
            XCTAssertEqual(row["phase"] as? String, "process")
            XCTAssertEqual(row["error"] as? String, "invalidTarget")
            XCTAssertEqual(row["check"] as? String, item.expected)
            XCTAssertEqual(row["chunkIndex"] as? Int, 4)
            XCTAssertEqual((row["operationIDDigest"] as? String)?.count, 64)
            XCTAssertNil(row["operationID"])
        }
    }

    @MainActor func testTwoClicksRemainIndependentAfterUnknownCommitWithoutReplayingFirst() async throws {
        let driver = EdgeExecutorFixture()
        let bridge = EdgeAppleEventsExecutor(driver: driver)
        let a = try await bridge.targetForClick(program: program).value, first = identity(a)
        _ = try await bridge.execute(.init(action: .begin, target: a, identity: first), program: program)
        driver.loseCommitReply = true
        do {
            _ = try await bridge.execute(.init(action: .commit, target: a, identity: first, invocationID: UUID()), program: program)
            XCTFail("lost native reply must remain uncertain")
        } catch { XCTAssertEqual(error as? WebAdapterError, .nativeEventFailed(-1712)) }
        _ = try await bridge.execute(.init(action: .observe, target: a, identity: first), program: program)
        do {
            _ = try await bridge.execute(.init(action: .commit, target: a, identity: first, invocationID: UUID()), program: program)
            XCTFail("original operation must never commit again")
        } catch { XCTAssertEqual(error as? WebAdapterError, .invalidRequest) }
        let b = try await bridge.targetForClick(program: program).value, second = identity(b)
        XCTAssertNotEqual(a.clickBindingID, b.clickBindingID)
        XCTAssertEqual(a.documentID, b.documentID)
        _ = try await bridge.execute(.init(action: .begin, target: b, identity: second), program: program)
        _ = try await bridge.execute(.init(action: .commit, target: b, identity: second, invocationID: UUID()), program: program)
        XCTAssertEqual(driver.actions, ["captureTarget", "begin", "commit", "observe", "captureTarget", "begin", "commit"])
    }

    @MainActor func testSameWorldAndReplacedDocumentRefuseBeforeCaptureOrInput() async throws {
        let same = EdgeExecutorFixture(); same.worldSeparated = false
        do {
            _ = try await EdgeAppleEventsExecutor(driver: same).targetForClick(program: program).value
            XCTFail("same execution world must not authorize a relay")
        } catch { XCTAssertEqual(error as? WebAdapterError, .pageRejected(.bridgeUnavailable)) }
        XCTAssertTrue(same.actions.isEmpty)
        let replaced = EdgeExecutorFixture(); replaced.replaceAtPin = true
        XCTAssertThrowsError(try EdgeAppleEventsExecutor(driver: replaced).targetForClick(program: program))
        XCTAssertEqual(replaced.bootstraps, 0)
        XCTAssertTrue(replaced.actions.isEmpty)
    }

    @MainActor func testChatGPTOriginIsCheckedBeforeAnyEdgePageExecution() async throws {
        for address in ["https://chatgpt.com:8443/c/neutral", "https://u@chatgpt.com/c/neutral",
                        "https://u:p@chat.openai.com/", "http://chatgpt.com/", "https://chatgpt.com.example/"] {
            let driver = EdgeExecutorFixture(address: address)
            XCTAssertThrowsError(try EdgeAppleEventsExecutor(driver: driver).targetForClick(program: program)) {
                XCTAssertEqual($0 as? WebAdapterError, .pageRejected(.pageRouteUnsupported))
            }
            XCTAssertEqual(driver.synchronousEvaluations, 0)
            XCTAssertEqual(driver.bootstraps, 0)
            XCTAssertTrue(driver.actions.isEmpty)
        }
        for address in ["https://chatgpt.com:443/?temporary-chat=true", "https://chat.openai.com/g/project/c/neutral"] {
            let driver = EdgeExecutorFixture(address: address)
            let bridge = EdgeAppleEventsExecutor(driver: driver)
            _ = try await bridge.targetForClick(program: program).value
            XCTAssertEqual(driver.actions, ["captureTarget"])
        }
    }

    @MainActor func testPageNativeIdentityCannotOverrideFrozenWindow() async throws {
        let driver = EdgeExecutorFixture(); driver.wrongCaptureWindow = true
        do {
            _ = try await EdgeAppleEventsExecutor(driver: driver).targetForClick(program: program).value
            XCTFail("page cannot choose a native target")
        } catch { XCTAssertEqual(error as? WebAdapterError, .invalidTarget) }
        XCTAssertEqual(driver.actions, ["captureTarget"])
    }

    @MainActor func testRestartOnlyObservesOriginalRelayWithoutForegroundCaptureOrBootstrap() async throws {
        let driver = EdgeExecutorFixture()
        let live = EdgeAppleEventsExecutor(driver: driver)
        let target = try await live.targetForClick(program: program).value, operation = identity(target)
        let count = driver.bootstraps, checks = driver.selectionChecks
        driver.selected = false
        let restarted = EdgeAppleEventsExecutor(driver: driver)
        _ = try await restarted.execute(.init(action: .observe, target: target, identity: operation), program: program)
        XCTAssertEqual(driver.bootstraps, count)
        XCTAssertEqual(driver.selectionChecks, checks)
        do {
            _ = try await restarted.execute(.init(action: .commit, target: target, identity: operation, invocationID: UUID()), program: program)
            XCTFail("restart never reconstructs input authority")
        } catch { XCTAssertEqual(error as? WebAdapterError, .invalidTarget) }
        driver.alive = false
        do {
            _ = try await restarted.execute(.init(action: .observe, target: target, identity: operation), program: program)
            XCTFail("process exit invalidates original observation")
        } catch { XCTAssertEqual(error as? WebAdapterError, .invalidTarget) }
        XCTAssertEqual(driver.actions, ["captureTarget", "observe"])
    }

    @MainActor func testRestartReadsV18ThroughV21EdgeWithFrozenProgramsAndNoNewClickOrBootstrap() async throws {
        for source in [ChatGPTWebPageProgram.priorClickSource, ChatGPTWebPageProgram.priorOriginSource, ChatGPTWebPageProgram.priorProgressSource, ChatGPTWebPageProgram.priorLabelSource] {
            let old = try XCTUnwrap(ChatGPTWebPageProgram.originalObservationProgram(sourceID: source))
            let driver = EdgeExecutorFixture(), host = driver.host
            let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: EdgeApplicationHost.bundleID,
                sessionID: host.sessionID, windowID: host.windowID, tabID: host.tabID, documentID: "d",
                composerID: "c", draftGeneration: "g", clickBindingID: UUID())
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let context = try encoder.encode(["applicationID": target.applicationID, "sessionID": target.sessionID,
                                              "windowID": host.windowID, "tabID": host.tabID])
            driver.retainInstalledRelay(MainWorldCommandRelay(function: old.functionSource, contextJSON: String(decoding: context, as: UTF8.self)))
            driver.selected = false
            let restarted = EdgeAppleEventsExecutor(driver: driver)
            let operation = identity(target), observe = WebBridgeCommand(action: .observe, target: target, identity: operation)
            _ = try await restarted.execute(observe, program: old)
            do {
                _ = try await restarted.execute(observe, program: program)
                XCTFail("A different version discovered a historical-only relay")
            } catch { XCTAssertEqual(error as? WebAdapterError, .pageRejected(.bridgeUnavailable)) }
            for action in [WebBridgeAction.captureTarget, .begin, .chunk, .commit, .discard] {
                do {
                    _ = try await restarted.execute(.init(action: action, target: target, identity: operation), program: old)
                    XCTFail("Historical observation permitted \(action)")
                } catch { XCTAssertEqual(error as? WebAdapterError, .invalidRequest) }
            }
            XCTAssertEqual(driver.actions, ["observe"])
            XCTAssertEqual(driver.bootstraps, 0)
            XCTAssertEqual(driver.selectionChecks, 0)
        }
    }

    @MainActor func testLateSynchronousPinCannotPublishAnInputCapability() throws {
        let driver = EdgeExecutorFixture(); driver.latePin = true
        XCTAssertThrowsError(try EdgeAppleEventsExecutor(driver: driver).targetForClick(program: program)) { error in
            XCTAssertEqual(error as? WebAdapterError, .nativeEventFailed(-1712))
        }
        XCTAssertEqual(driver.bootstraps, 0)
        XCTAssertTrue(driver.actions.isEmpty)
    }

    @MainActor func testTemporaryRouteMustAgreeWithExactFrozenNativeAddress() async throws {
        let exact = "https://chatgpt.com/?temporary-chat=true"
        for (address, returned, matches) in [(exact, WebDraftRoute.chatGPTTemporaryHome as WebDraftRoute?, true),
                (exact, nil, true), ("https://chatgpt.com:443/?temporary-chat=true", .chatGPTTemporaryHome, true),
                ("https://chatgpt.com/c/sample", .chatGPTTemporaryHome, false),
                (exact + "&other=1", .chatGPTTemporaryHome, false)] {
            let driver = EdgeExecutorFixture(address: address); driver.returnedRoute = returned
            let bridge = EdgeAppleEventsExecutor(driver: driver)
            do {
                let target = try await bridge.targetForClick(program: program).value
                XCTAssertTrue(matches); XCTAssertEqual(target.webDraftRoute, returned)
            } catch { XCTAssertFalse(matches); XCTAssertEqual(error as? WebAdapterError, .invalidTarget) }
            XCTAssertFalse(driver.actions.contains("begin")); XCTAssertFalse(driver.actions.contains("commit"))
        }
    }

    @MainActor func testOnePinEvaluationLeavesBudgetForEveryOriginalIdentityRecheck() throws {
        let driver = EdgeExecutorFixture(); driver.modelClickBudget = true
        let bridge = EdgeAppleEventsExecutor(driver: driver)
        let task = try bridge.targetForClick(program: program)
        task.cancel() // This regression ends before the asynchronous capture/input path.
        XCTAssertEqual(driver.synchronousEvaluations, 1)
        XCTAssertEqual(driver.selectionChecks, 2)
        XCTAssertEqual(driver.fullSelectionChecks, 1)
        XCTAssertEqual(driver.clickSelectionChecks, 1)
        XCTAssertEqual(driver.bootstraps, 0)
        XCTAssertTrue(driver.actions.isEmpty)
    }

    @MainActor func testColdCombinedPinLeavesBudgetForExactSelectionWithoutRepeatingAddressFreeze() throws {
        let driver = EdgeExecutorFixture(); driver.modelClickBudget = true; driver.modeledPinDuration = 0.044
        let bridge = EdgeAppleEventsExecutor(driver: driver)
        let task = try bridge.targetForClick(program: program)
        task.cancel()
        XCTAssertEqual(driver.synchronousEvaluations, 1)
        XCTAssertEqual(driver.clickSelectionChecks, 1)
        XCTAssertEqual(driver.fullSelectionChecks, 1)
        XCTAssertEqual(driver.bootstraps, 0)
        XCTAssertTrue(driver.actions.isEmpty)

        // Identical costs fail when the post-pin path unnecessarily repeats all
        // three freeze reads: their remaining budgets are 61, 46, then 31 ms.
        let repeated = EdgeExecutorFixture(); repeated.modelClickBudget = true; repeated.modeledPinDuration = 0.044
        let budget = MainWorldReceiptReadBudget.clickSnapshot(start: 100)
        let host = try repeated.freeze(deadline: budget.deadlineUptime)
        let world = EdgeExecutionWorldWitness(), document = ChromeClickDocumentWitness()
        XCTAssertEqual(try repeated.evaluate(world.prepareAndBind(document, address: host.address, program: ChatGPTWebPageProgram.edgeProgram.get()),
                                             target: host, budget: budget), "bound")
        XCTAssertThrowsError(try repeated.revalidate(host, deadline: budget.deadlineUptime)) { error in
            XCTAssertEqual(error as? WebAdapterError, .nativeEventFailed(-1712))
        }
        XCTAssertEqual(repeated.bootstraps, 0)
        XCTAssertTrue(repeated.actions.isEmpty)
    }

    @MainActor func testFinalClickSelectionRefusesSwitchOrExitBeforeCapture() throws {
        for exit in [false, true] {
            let driver = EdgeExecutorFixture()
            driver.atPin = { if exit { driver.alive = false } else { driver.selected = false } }
            XCTAssertThrowsError(try EdgeAppleEventsExecutor(driver: driver).targetForClick(program: program)) { error in
                XCTAssertEqual(error as? WebAdapterError, .nativeSelectionChanged)
            }
            XCTAssertEqual(driver.clickSelectionChecks, 1)
            XCTAssertEqual(driver.bootstraps, 0)
            XCTAssertTrue(driver.actions.isEmpty)
        }
    }

    @MainActor func testNavigationAfterPinCannotCaptureOrInputThroughSelectionOnlyRecheck() async throws {
        for sameAddressReplacement in [false, true] {
            let driver = EdgeExecutorFixture()
            driver.atPin = {
                if sameAddressReplacement { driver.originalDocumentCurrent = false }
                else { driver.navigated = true }
            }
            let original = EdgeAppleEventsExecutor(driver: driver)
            do {
                _ = try await original.targetForClick(program: program).value
                XCTFail("selection identity alone cannot authorize capture of another document")
            } catch {
                XCTAssertEqual(error as? WebAdapterError,
                    sameAddressReplacement ? .pageRejected(.bridgeUnavailable) : .nativeSelectionChanged)
            }
            XCTAssertEqual(driver.clickSelectionChecks, 1)
            XCTAssertGreaterThanOrEqual(driver.fullSelectionChecks, 2)
            XCTAssertEqual(driver.bootstraps, sameAddressReplacement ? 1 : 0)
            XCTAssertTrue(driver.actions.isEmpty)
        }
    }

    func testSeparatePrepareAndPinExhaustTheSameModeledRecheckBudget() throws {
        let driver = EdgeExecutorFixture(); driver.modelClickBudget = true
        let budget = MainWorldReceiptReadBudget.clickSnapshot(start: 100)
        let host = try driver.freeze(deadline: budget.deadlineUptime)
        let world = EdgeExecutionWorldWitness(), document = ChromeClickDocumentWitness()
        XCTAssertEqual(try driver.evaluate(world.prepare, target: host, budget: budget), "prepared")
        XCTAssertEqual(try driver.evaluate(document.bindScript(address: host.address, program: ChatGPTWebPageProgram.edgeProgram.get(), host: .edge),
                                           target: host, budget: budget), "bound")
        XCTAssertThrowsError(try driver.revalidate(host, deadline: budget.deadlineUptime)) { error in
            XCTAssertEqual(error as? WebAdapterError, .nativeEventFailed(-1712))
        }
        XCTAssertEqual(driver.synchronousEvaluations, 2)
        XCTAssertEqual(driver.bootstraps, 0)
        XCTAssertTrue(driver.actions.isEmpty)
    }

    @MainActor func testWindowOrDocumentChangeAfterCapturePreventsOriginalCommitWithoutRetargeting() async throws {
        for replaceDocument in [false, true] {
            let driver = EdgeExecutorFixture()
            let original = EdgeAppleEventsExecutor(driver: driver)
            let target = try await original.targetForClick(program: program).value, operation = identity(target)
            if replaceDocument { driver.worldSeparated = false } else { driver.selected = false }
            do {
                _ = try await original.execute(.init(action: .commit, target: target, identity: operation, invocationID: UUID()), program: program)
                XCTFail("changed original receiver must refuse before dispatch")
            } catch {
                XCTAssertEqual(error as? WebAdapterError, replaceDocument ? .pageRejected(.clickPinRefused) : .nativeSelectionChanged)
            }
            XCTAssertEqual(driver.actions, ["captureTarget"])
            driver.selected = true; driver.worldSeparated = true
            do {
                _ = try await original.execute(.init(action: .commit, target: target, identity: operation, invocationID: UUID()), program: program)
                XCTFail("one entered commit invocation cannot be reissued")
            } catch { XCTAssertEqual(error as? WebAdapterError, .invalidRequest) }
            XCTAssertEqual(driver.actions, ["captureTarget"])
        }
    }

    @MainActor func testOuterCaptureCancellationCancelsTheOriginalPinTask() async throws {
        let driver = EdgeExecutorFixture()
        let original = EdgeAppleEventsExecutor(driver: driver)
        var call: Task<Data, Error>?
        driver.atPin = { call?.cancel() }
        call = Task { try await original.execute(.init(action: .captureTarget), program: program) }
        do { _ = try await XCTUnwrap(call).value; XCTFail("cancelled capture must not publish its lease") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(driver.bootstraps, 0)
        XCTAssertTrue(driver.actions.isEmpty)
    }

    @MainActor func testCancellationBehindOccupiedQueuePreventsEveryNewSubmission() async throws {
        for action in [WebBridgeAction.captureTarget, .validate, .begin, .chunk, .commit] {
            let victim = EdgeExecutorFixture()
            let original = EdgeAppleEventsExecutor(driver: victim)
            let target = try await original.targetForClick(program: program).value, operation = identity(target)
            let blocker = EdgeExecutorFixture()
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            blocker.worldBootstrapEntered = entered; blocker.releaseWorldBootstrap = release
            let blockerBridge = EdgeAppleEventsExecutor(driver: blocker)
            let held = try blockerBridge.targetForClick(program: program)
            let occupied = await Task.detached { entered.wait(timeout: .now() + 2) == .success }.value
            XCTAssertTrue(occupied)
            let before = victim.bootstraps
            let passedEntry = DispatchSemaphore(value: 0)
            if action == .captureTarget { victim.atPin = { passedEntry.signal() } }
            else { victim.recovered = passedEntry }
            let command = WebBridgeCommand(action: action, target: action == .captureTarget ? nil : target,
                identity: action == .captureTarget ? nil : operation, invocationID: action == .commit ? UUID() : nil)
            let call = Task { try await original.execute(command, program: program) }
            let enteredAPI = await Task.detached { passedEntry.wait(timeout: .now() + 2) == .success }.value
            XCTAssertTrue(enteredAPI)
            call.cancel(); release.signal()
            do { _ = try await call.value; XCTFail("cancelled work must not first submit after the queue opens") }
            catch { XCTAssertTrue(error is CancellationError) }
            _ = try await held.value
            _ = blockerBridge
            XCTAssertEqual(victim.bootstraps, before)
            XCTAssertEqual(victim.actions, ["captureTarget"])
        }
    }

    @MainActor func testCancellationInsideWorkerStopsBeforeRelayDispatch() async throws {
        for action in [WebBridgeAction.captureTarget, .validate, .begin, .chunk, .commit] {
            let driver = EdgeExecutorFixture(), bridge = EdgeAppleEventsExecutor(driver: driver)
            let target = try await bridge.targetForClick(program: program).value, operation = identity(target)
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            if action == .captureTarget {
                driver.worldBootstrapEntered = entered; driver.releaseWorldBootstrap = release
            } else { driver.revalidateEntered = entered; driver.releaseRevalidate = release }
            let command = WebBridgeCommand(action: action, target: action == .captureTarget ? nil : target,
                identity: action == .captureTarget ? nil : operation, invocationID: action == .commit ? UUID() : nil)
            let call = Task { try await bridge.execute(command, program: program) }
            let enteredWorker = await Task.detached { entered.wait(timeout: .now() + 2) == .success }.value
            XCTAssertTrue(enteredWorker)
            call.cancel(); release.signal()
            do { _ = try await call.value; XCTFail("worker cancellation before dispatch must not execute the command") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(driver.actions, ["captureTarget"])
        }
    }

    @MainActor func testCancellationAfterCommitEntryReadsOnlyItsOriginalReceipt() async throws {
        let driver = EdgeExecutorFixture(), bridge = EdgeAppleEventsExecutor(driver: driver)
        let target = try await bridge.targetForClick(program: program).value, operation = identity(target)
        var call: Task<Data, Error>?
        driver.atCommit = { call?.cancel() }
        call = Task { try await bridge.execute(.init(action: .commit, target: target, identity: operation,
            invocationID: UUID()), program: program) }
        let result = try await XCTUnwrap(call).value
        XCTAssertEqual(try JSONSerialization.jsonObject(with: result) as? [String: Bool], ["original": true])
        XCTAssertEqual(driver.actions, ["captureTarget", "commit"])
        do {
            _ = try await bridge.execute(.init(action: .commit, target: target, identity: operation, invocationID: UUID()), program: program)
            XCTFail("post-submission cancellation cannot authorize a second commit")
        } catch { XCTAssertEqual(error as? WebAdapterError, .invalidRequest) }
    }
}
