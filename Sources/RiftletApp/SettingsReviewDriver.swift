import AppKit
import CoreGraphics
import CryptoKit
import Darwin
import ImageIO
import QuartzCore
import RiftletCore
import RiftletUI
import UniformTypeIdentifiers

/// Deliberately invoked in the UUID-scoped settings-review mode of the same App.
/// Uses the real host/model/SQLite/controls; never constructs upload receipts or
/// changes another process, system preference, login item, or production root.
@MainActor
final class SettingsReviewDriver {
    private enum Failure: Error { case unsafeEnvironment, assertion(String), controlUnavailable(String), encoding, restoreFailed }
    // Read the written number independently of the product decoder's legacy-interval fallback.
    private struct ArchiveDocument: Decodable {
        let archiveAfterSeconds: Double?
    }
    private let environment: SettingsReviewEnvironment
    private let host: SettingsProductHost
    private let store: QueueStore
    private let historyController: RiftHistoryController?
    private var historyStyleReview: Bool { CommandLine.arguments.contains("--history-style-review") }
    private var historyFixtureIDs: [UUID] = []
    private var historyReadOnlyBaseline: [AssetRecord] = []
    private let desktopPanel: RiftPanelController?
    private let statusItem: NSStatusItem
    private let onRefresh: @MainActor () async -> Void
    private let onHistory: @MainActor () -> Void
    private let onRecheck: @MainActor () -> Bool
    private var directory: URL!
    private var cases: [[String: Any]] = []
    private var frames: [[String: Any]] = []
    private var artifacts: [[String: Any]] = []
    private var restorationFailures: [String] = []
    private let began = Date()
    private let beganUptime = ProcessInfo.processInfo.systemUptime
    private var beganPID: pid_t?
    private var originalAppearance = SettingsAppearanceChoice.system
    private var initialAssetIDs: Set<UUID> = []
    private var presentationObservers: [NSObjectProtocol] = []
    private var presentationMouseMonitor: Any?
    private var presentationTraceCount = 0
    private var presentationMouseTraceCount = 0
    private var presentationCloseStackCount = 0

    init(environment: SettingsReviewEnvironment, host: SettingsProductHost, store: QueueStore,
         statusItem: NSStatusItem, onRefresh: @escaping @MainActor () async -> Void,
         onHistory: @escaping @MainActor () -> Void, onRecheck: @escaping @MainActor () -> Bool,
         history: RiftHistoryController? = nil, panel: RiftPanelController? = nil) {
        self.desktopPanel = panel
        self.environment = environment; self.host = host; self.store = store
        self.statusItem = statusItem; self.onRefresh = onRefresh; self.onHistory = onHistory
        self.onRecheck = onRecheck; self.historyController = history
    }

    /// A report is checkpointed after each case, including failures. Main owns
    /// process lifetime; the driver neither launches nor terminates an App.
    func run() async -> URL? {
        defer { stopPresentationTrace() }
        do {
            try validateEnvironment()
            let parent = environment.root.appendingPathComponent("evidence", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            guard parent.resolvingSymlinksInPath().standardizedFileURL == parent.standardizedFileURL else { throw Failure.unsafeEnvironment }
            directory = parent.appendingPathComponent("run-" + UUID().uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            beganPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            originalAppearance = host.snapshot.appearance.selection
            initialAssetIDs = Set(try await store.assets(includeUsed: true).map(\.id))
            startPresentationTrace()
            try saveReport(completed: false)
        } catch {
            fputs("Riftlet settings review could not establish its isolated evidence directory.\n", stderr)
            return nil
        }

        if CommandLine.arguments.contains("--desktop-forms-review") {
            let inputs = environment.root.appendingPathComponent("reference-inputs", isDirectory: true)
            if FileManager.default.fileExists(atPath: inputs.path) {
                return await referenceTrayRun(inputs: inputs)
            }
            return await desktopRun()
        }
        await runCase("environment-and-default-window") {
            try await self.wait { self.host.snapshot.capabilities.initialized }
            try self.validateEnvironment()
            self.host.onboarding.closeForTeardown()
            self.host.show()
            await self.settle()
            let window = self.host.center.window
            try self.require(window.isVisible, "settingsWindowNotVisible")
            let content = window.contentRect(forFrameRect: window.frame)
            let titleHeight = window.frame.height - content.height
            if let screen = window.screen, screen.visibleFrame.width >= 814, screen.visibleFrame.height >= 580 + titleHeight {
                try self.require(abs(content.width - 814) <= 1 && abs(content.height - 580) <= 1,
                                 "initialContentSizeMismatch")
            }
            try self.require(!self.host.snapshot.capabilities.canCapture, "reviewCaptureCapabilityEnabled")
            try self.require(!self.host.snapshot.login.available, "reviewLoginCapabilityEnabled")
            try self.require(self.host.center.selectedPage == .display, "initialSettingsPageMismatch")
            await self.capture("initial-display", window: window)
        }

        if historyStyleReview {
            await runHistoryStyleCases()
        } else {
            await runCase("real-collector-synthetic-fixture") { try await self.collectFixture() }
            await runCase("accepted-collection-during-recheck") { try await self.collectionDuringRecheck() }
            await runCase("four-pages-light-and-dark") { try await self.capturePages() }
            await runCase("orthogonal-pause-hidden-sqlite") { try await self.pauseAndHide() }
            await runCase("archive-editor-first-save-discard") { try await self.archiveEditing() }
            await runCase("configuration-editor-refresh-defaults") { try await self.configurationEditing() }
            await runCase("close-sheet-continue-discard") { try await self.closeEditing() }
            await runCase("independent-write-failures-and-retry") { try await self.saveFailures() }
            await runCase("motion-explicit-play-and-navigation-stop") { try await self.motion() }
            await runCase("three-step-guidance-light-and-dark") { try await self.onboarding() }
            await runCase("resizing-and-reopen") { try await self.resize() }
            await runCase("history-real-records") { try await self.history() }
            await runCase("original-media-and-no-upload-operations") { try await self.integrity() }
        }

        recordPresentationEvent("driver.finalCloseIntent")
        host.control.close(); host.onboarding.closeForTeardown()
        host.center.closeForTeardown()
        if historyStyleReview { historyController?.close() }
        if restorationFailures.isEmpty { await host.perform(.appearance(originalAppearance)) }
        do { try saveReport(completed: true) }
        catch { fputs("Riftlet settings review final report write failed; prior checkpoint remains.\n", stderr) }
        return directory.appendingPathComponent("report.json")
    }

    /// A separate process verifies what the ordinary run actually left behind.
    /// This path never presents a window, creates a fixture, or submits a setting.
    func verifyRestart() async -> URL? {
        let manager = FileManager.default
        let output: URL
        do {
            try validateEnvironment()
            let parent = environment.root.appendingPathComponent("evidence", isDirectory: true)
            guard manager.fileExists(atPath: parent.path),
                  parent.resolvingSymlinksInPath().standardizedFileURL == parent.standardizedFileURL else { throw Failure.unsafeEnvironment }
            let folder = parent.appendingPathComponent("restart-" + UUID().uuidString.lowercased(), isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            output = folder.appendingPathComponent("restart-report.json")
        } catch {
            fputs("Riftlet restart review requires an existing isolated evidence root.\n", stderr)
            return nil
        }

        if CommandLine.arguments.contains("--desktop-forms-review") {
            return await desktopRestart(output)
        }
        var checks: [[String: Any]] = []
        var prior: [String: Any]?
        let executableSHA = Bundle.main.executableURL.flatMap { try? Data(contentsOf: $0) }.map(digest)
        var documentBytes: [String: Data] = [:]
        func check(_ name: String, body: () async throws -> [String: Any]) async {
            do {
                var result = try await body(); result["check"] = name; result["status"] = "PASS"
                checks.append(result)
            } catch { checks.append(["check": name, "status": "FAIL", "reason": code(error)]) }
        }
        await check("same-binary-new-process-after-completed-run") {
            try await self.wait { self.host.snapshot.capabilities.initialized }
            try self.require(executableSHA != nil, "currentExecutableUnreadable")
            let parent = self.environment.root.appendingPathComponent("evidence", isDirectory: true)
            var matches: [(URL, [String: Any])] = []
            for folder in try manager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
                guard folder.lastPathComponent.hasPrefix("run-"),
                      UUID(uuidString: String(folder.lastPathComponent.dropFirst(4))) != nil,
                      folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL else { continue }
                let file = folder.appendingPathComponent("report.json")
                guard file.resolvingSymlinksInPath().standardizedFileURL == file.standardizedFileURL,
                      let data = try? Data(contentsOf: file), data.count <= 2_097_152,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      json["reviewID"] as? String == self.environment.identifier.uuidString.lowercased(),
                      json["completed"] as? Bool == true,
                      (!self.historyStyleReview || json["reviewMode"] as? String == "historyStyle"),
                      json["executableSHA256"] as? String == executableSHA else { continue }
                matches.append((file, json))
            }
            let latest = matches.max { ($0.1["beganUTC"] as? String ?? "") < ($1.1["beganUTC"] as? String ?? "") }
            guard let latest, let previousPID = (latest.1["processPID"] as? NSNumber)?.int32Value else {
                throw Failure.assertion("completedRunFromSameExecutableMissing")
            }
            try self.require(previousPID != ProcessInfo.processInfo.processIdentifier, "restartReusedOriginalProcess")
            prior = latest.1
            return ["priorReport": latest.0.path, "priorReportSHA256": self.digest(try Data(contentsOf: latest.0)),
                    "priorProcessPID": previousPID, "priorStatus": latest.1["status"] as? String ?? "unknown"]
        }
        if historyStyleReview {
            return await verifyHistoryStyleRestart(output: output, initialChecks: checks, prior: prior, executableSHA: executableSHA)
        }
        await check("persisted-json-and-loaded-owners") {
            guard prior != nil else { throw Failure.assertion("priorRunRequired") }
            let names = ["rift-configuration.json", "lifecycle-settings.json", "arrival-motion-settings.json",
                         "capture-entry-settings.json", "app-presentation-settings.json"]
            for name in names { documentBytes[name] = try self.reviewDocument(name) }
            let settings = self.host.snapshot.state.owner.settings
            let configuration = try JSONDecoder().decode(RiftConfiguration.self, from: documentBytes["rift-configuration.json"]!)
            try configuration.validate()
            try self.require(configuration == settings.configuration, "restartedConfigurationMismatch")
            let lifecycleBytes = documentBytes["lifecycle-settings.json"]!
            try JSONDecoder().decode(LifecycleSettings.self, from: lifecycleBytes).validate()
            let stored = try JSONDecoder().decode(ArchiveDocument.self, from: lifecycleBytes)
            try self.require(stored.archiveAfterSeconds.map { $0 / 60 } == settings.archiveAfterMinutes, "restartedArchiveMismatch")
            let arrival = ArrivalMotionPreferences(url: self.environment.root.appendingPathComponent("arrival-motion-settings.json"))
            try self.require(arrival.loadState == .selected && arrival.mode == settings.arrivalMode && settings.hasArrivalSelection,
                             "restartedArrivalMismatch")
            let entry = try JSONDecoder().decode(ScreenshotEntryPreferences.self, from: documentBytes["capture-entry-settings.json"]!)
            try self.require(entry.version == 1 && settings.entryAvailable && entry.builtInScreenshotEnabled == settings.entryEnabled
                             && entry.defaultMode == settings.defaultCaptureMode, "restartedEntryMismatch")
            let appearance = try JSONSerialization.jsonObject(with: documentBytes["app-presentation-settings.json"]!) as? [String: Any]
            try self.require(appearance?["version"] as? Int == 1 && appearance?["appearance"] as? String == self.host.appearance.selection.rawValue
                             && self.host.appearance.loadState == .selected && self.host.appearance.appliedSelection == self.host.appearance.selection
                             && self.host.appearance.failure == nil, "restartedAppearanceMismatch")
            return ["allConfigurationFieldsEqual": true, "archiveMinutes": settings.archiveAfterMinutes as Any? ?? NSNull(),
                    "arrival": arrival.mode.rawValue, "entryEnabled": settings.entryEnabled,
                    "captureMode": entry.defaultMode.rawValue, "appearance": self.host.appearance.selection.rawValue,
                    "jsonSHA256": documentBytes.mapValues(self.digest)]
        }
        await check("sqlite-pause-and-visibility") {
            let paused = try await self.store.capturePaused(), hidden = try await self.store.userHidden()
            try self.require(paused == self.host.snapshot.state.owner.collectionPaused && hidden == self.host.snapshot.state.owner.isHidden,
                             "restartedSQLiteOwnerMismatch")
            return ["paused": paused, "hidden": hidden]
        }
        await check("existing-first-use-not-presented-again") {
            let firstUse = FirstUsePreferences(defaults: self.environment.defaults,
                modeName: SettingsReviewEnvironment.directoryName(for: self.environment.identifier))
            try self.require(!firstUse.needsAutomaticPresentation && !self.host.onboarding.isVisible,
                             "firstUsePresentedAgain")
            return ["existingPresentedPreference": true, "onboardingVisible": false,
                    "settingsVisible": self.host.center.isVisible, "controlVisible": self.host.control.isShown]
        }
        await check("assets-media-and-operation-readback") {
            guard let prior else { throw Failure.assertion("priorRunRequired") }
            let original = (prior["artifacts"] as? [[String: Any]])?.last { $0["kind"] as? String == "integrity" }
            guard let priorCount = original?["assetCount"] as? Int else { throw Failure.assertion("priorIntegrityMissing") }
            let records = try await self.store.assets(includeUsed: true)
            try self.require(records.count >= priorCount, "assetsLostAcrossRestart")
            try await self.integrity()
            return ["priorAssetCount": priorCount, "assetCount": records.count, "mediaHashesMatch": true,
                    "unresolvedOperations": 0, "successfulOperations": 0, "assetsWithOperation": 0,
                    "operationScope": "Existing QueueStore queries; independent read-only SQL supplies the complete operation table count"]
        }
        await check("verification-left-preference-bytes-unchanged") {
            try self.require(documentBytes.count == 5, "initialPreferenceReadIncomplete")
            for (name, data) in documentBytes { try self.require(try self.reviewDocument(name) == data, "restartCheckChangedPreferenceBytes") }
            return ["allFiveFilesUnchangedDuringCheck": true]
        }
        let report: [String: Any] = ["schema": 1, "reviewID": environment.identifier.uuidString.lowercased(),
            "status": checks.contains { $0["status"] as? String == "FAIL" } ? "FAIL" : "PASS_SCOPED_NATIVE_RESTART",
            "completed": true, "processPID": ProcessInfo.processInfo.processIdentifier,
            "executableSHA256": executableSHA as Any? ?? NSNull(), "beganUTC": ISO8601DateFormatter().string(from: began),
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - beganUptime,
            "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier as Any? ?? NSNull(),
            "checks": checks, "driverChangedPreferences": false, "createdFixtures": 0,
            "scope": "Readback after normal Main initialization of an existing UUID; only this restart evidence report is written",
            "notRun": ["productionData", "browserAttachment", "systemPermissions", "loginRegistration", "completeOperationTableCount"]]
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
            return output
        } catch { fputs("Riftlet restart review could not save its report.\n", stderr); return nil }
    }

    private func reviewDocument(_ name: String) throws -> Data {
        let url = environment.root.appendingPathComponent(name)
        guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL,
              (try FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeRegular else {
            throw Failure.unsafeEnvironment
        }
        let data = try Data(contentsOf: url)
        try require(data.count <= 262_144, "reviewDocumentTooLarge")
        return data
    }

    private func validateEnvironment() throws {
        guard try SettingsReviewEnvironment.identifier(in: CommandLine.arguments) == environment.identifier,
              environment.root.lastPathComponent == SettingsReviewEnvironment.directoryName(for: environment.identifier),
              environment.root.resolvingSymlinksInPath().standardizedFileURL == environment.root.standardizedFileURL,
              environment.source.resolvingSymlinksInPath().standardizedFileURL == environment.source.standardizedFileURL,
              host.snapshot.reviewEnvironment, !host.snapshot.capabilities.canCapture,
              host.snapshot.setup.attachment == .productionDisabled else { throw Failure.unsafeEnvironment }
        let marker = environment.root.appendingPathComponent("settings-review-identity.txt")
        guard marker.resolvingSymlinksInPath() == marker,
              try Data(contentsOf: marker) == Data((environment.identifier.uuidString.lowercased() + "\n").utf8) else { throw Failure.unsafeEnvironment }
    }

    private func runCase(_ name: String, body: () async throws -> Void) async {
        let start = ProcessInfo.processInfo.systemUptime
        guard restorationFailures.isEmpty else {
            cases.append(["case": name, "status": "NOT_RUN", "reason": "isolatedFaultRestorationFailed"])
            try? saveReport(completed: false); return
        }
        do {
            try await body()
            cases.append(["case": name, "status": "PASS", "seconds": ProcessInfo.processInfo.systemUptime - start,
                          "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier as Any? ?? NSNull()])
        } catch {
            cases.append(["case": name, "status": "FAIL", "reason": code(error),
                          "seconds": ProcessInfo.processInfo.systemUptime - start])
            // Only close our own confirmation; do not change or discard a draft
            // to conceal the failed case. Later independent cases may continue.
            if let sheet = host.center.window.attachedSheet {
                if let button = find("settings.center.close.continue", in: sheet.contentView) as? NSButton { button.performClick(nil) }
            }
        }
        try? saveReport(completed: false)
    }

    private func require(_ value: Bool, _ reason: String) throws { if !value { throw Failure.assertion(reason) } }
    private func code(_ error: Error) -> String {
        switch error {
        case Failure.unsafeEnvironment: return "unsafeEnvironment"
        case Failure.assertion(let reason): return reason
        case Failure.controlUnavailable(let identifier): return "controlUnavailable:" + identifier
        case Failure.encoding: return "encoding"
        case Failure.restoreFailed: return "restoreFailed"
        default: return "frameworkError:" + String((error as NSError).code)
        }
    }
    private func settle(_ milliseconds: UInt64 = 120) async { try? await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
    private func wait(timeout: Double = 5, _ condition: () async throws -> Bool) async throws {
        let limit = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < limit {
            if try await condition() { return }
            await settle(25)
        }
        let collection = host.snapshot.state.domains[.collection]
        artifacts.append(["kind": "nativeWaitTimeout", "timeoutSeconds": timeout,
            "ownerPaused": host.snapshot.state.owner.collectionPaused,
            "canChangeCollection": host.snapshot.capabilities.canChangeCollection,
            "collectionSaving": collection?.isSaving ?? false,
            "collectionPending": collection?.pending.map { String(describing: $0) } ?? "none",
            "collectionFailure": collection?.saveFailure.map { String(describing: $0) } ?? "none"])
        throw Failure.assertion("conditionTimedOut")
    }

    private func find(_ identifier: String, in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view.identifier?.rawValue == identifier { return view }
        for child in view.subviews { if let result = find(identifier, in: child) { return result } }
        return nil
    }
    private func control(_ id: String, window: NSWindow? = nil) throws -> NSControl {
        let window = window ?? host.center.window
        guard let control = find(id, in: window.contentView) as? NSControl,
              !control.isHiddenOrHasHiddenAncestor, control.isEnabled else { throw Failure.controlUnavailable(id) }
        control.scrollToVisible(control.bounds)
        window.contentView?.layoutSubtreeIfNeeded()
        return control
    }
    private func click(_ id: String, window: NSWindow? = nil) throws {
        let control = try control(id, window: window)
        if let button = control as? NSButton { button.performClick(nil) }
        else if let action = control.action { NSApp.sendAction(action, to: control.target, from: control) }
        else { throw Failure.controlUnavailable(id) }
    }
    private func setToggle(_ id: String, _ target: Bool) async throws {
        let start = ProcessInfo.processInfo.systemUptime
        var ready = false
        defer { artifacts.append(["kind": "nativeControlEnabledWait", "identifier": id,
            "seconds": ProcessInfo.processInfo.systemUptime - start, "ready": ready]) }
        // Showing the page may trigger an asynchronous owner refresh. A real
        // disabled native switch is not yet an eligible user action target.
        try await wait(timeout: 5) {
            guard let value = self.find(id, in: self.host.center.window.contentView) as? NSControl else { return false }
            return self.host.center.window.isVisible && value.isEnabled
                && !value.isHiddenOrHasHiddenAncestor && value.window === self.host.center.window
        }
        ready = true
        let control = try control(id)
        if let toggle = control as? NSSwitch {
            let before = toggle.state.rawValue
            guard (toggle.state == .on) != target else {
                artifacts.append(["kind": "nativeSwitchAction", "identifier": id,
                    "target": target, "stateBefore": before, "action": "alreadyAtTarget"])
                return
            }
            toggle.state = target ? .on : .off
            let afterSet = toggle.state.rawValue
            guard let action = toggle.action else { throw Failure.controlUnavailable(id) }
            let dispatched = NSApp.sendAction(action, to: toggle.target, from: toggle)
            artifacts.append(["kind": "nativeSwitchAction", "identifier": id, "target": target,
                "stateBefore": before, "stateAfterSet": afterSet, "stateAfterAction": toggle.state.rawValue,
                "dispatchReturned": dispatched, "enabledAfterAction": toggle.isEnabled,
                "targetClass": toggle.target.map { String(describing: type(of: $0)) } ?? "nil",
                "ownerPaused": host.snapshot.state.owner.collectionPaused,
                "ownerHidden": host.snapshot.state.owner.isHidden])
        } else if let button = control as? NSButton {
            if (button.state == .on) != target { button.performClick(nil) }
        } else { throw Failure.controlUnavailable(id) }
    }
    private func select(_ id: String, index: Int, window: NSWindow? = nil) throws {
        let sender = try control(id, window: window)
        guard let action = sender.action else { throw Failure.controlUnavailable(id) }
        switch sender {
        case let popup as NSPopUpButton:
            guard popup.itemArray.indices.contains(index), popup.item(at: index)?.isEnabled == true else { throw Failure.controlUnavailable(id) }
            popup.selectItem(at: index)
        case let segments as NSSegmentedControl:
            guard (0..<segments.segmentCount).contains(index), segments.isEnabled(forSegment: index) else { throw Failure.controlUnavailable(id) }
            segments.selectedSegment = index
        default: throw Failure.controlUnavailable(id)
        }
        try require(NSApp.sendAction(action, to: sender.target, from: sender), "nativeChoiceActionNotDispatched")
    }
    private func edit(_ id: String, text: String) throws -> (NSTextField, NSTextView) {
        guard let field = try control(id) as? NSTextField else { throw Failure.controlUnavailable(id) }
        host.center.window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else { throw Failure.assertion("nativeFieldEditorMissing") }
        let local = text.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
        editor.insertText(local, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        return (field, editor)
    }
    private func read<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: environment.root.appendingPathComponent(name)))
    }
    private func appearance(_ value: SettingsAppearanceChoice) async throws {
        host.show(page: .display)
        try select("settings.center.appearance", index: SettingsAppearanceChoice.allCases.firstIndex(of: value)!)
        try await wait { self.host.snapshot.appearance.selection == value && self.host.snapshot.appearance.failure == nil }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: environment.root.appendingPathComponent("app-presentation-settings.json"))) as? [String: Any]
        try require(json?["appearance"] as? String == value.rawValue, "appearanceJSONMismatch")
    }

    private func capturePages() async throws {
        for theme in [SettingsAppearanceChoice.light, .dark] {
            try await appearance(theme)
            for page in SettingsPage.allCases {
                host.show(page: page); await settle()
                artifacts.append(["kind": "settingsPageObservation", "theme": theme.rawValue,
                    "expectedPage": page.rawValue, "actualPage": host.center.selectedPage.rawValue,
                    "visible": host.center.isVisible,
                    "elapsedSeconds": ProcessInfo.processInfo.systemUptime - beganUptime])
                try require(host.center.selectedPage == page && host.center.isVisible, "pageNotPresented")
                await capture("settings-\(theme.rawValue)-\(page.rawValue)", window: host.center.window)
            }
            try await openControl()
            await capture("control-" + theme.rawValue, window: host.control.window)
            try await closeControl()
        }
    }

    private func collectFixture() async throws {
        host.show(page: .general)
        try await setToggle("settings.center.paused", true)
        try await wait { !self.host.snapshot.state.owner.collectionPaused }
        let fixtureSHA256 = try createFixture("first")
        try await wait(timeout: 10) { try await self.store.assets(includeUsed: true).contains { $0.image.sha256 == fixtureSHA256 } }
        await onRefresh()
        let records = try await store.assets(includeUsed: true)
        try require(records.allSatisfy { $0.activeOperationID == nil }, "collectorCreatedOperation")
        artifacts.append(["kind": "collector", "input": "generatedPNGWithExplicitTestScreenshotMetadata", "assetCount": records.count])
    }

    /// Exercise the actual native callback/owner boundary in a fixed order:
    /// accepted enabled switch, synchronous background recheck, deferred command.
    /// No scheduling sleep, fake write receipt or production data is involved.
    private func collectionDuringRecheck() async throws {
        host.show(page: .general)
        var rejectedTargets: [Bool] = []
        for target in [true, false] {
            try await wait { self.host.snapshot.capabilities.canChangeCollection }
            guard let toggle = try control("settings.center.paused") as? NSSwitch,
                  (toggle.state == .on) == target, let action = toggle.action else {
                throw Failure.controlUnavailable("settings.center.paused")
            }
            let before = try await store.capturePaused()
            let hiddenBefore = try await store.userHidden()
            toggle.state = target ? .off : .on
            let dispatched = NSApp.sendAction(action, to: toggle.target, from: toggle)
            // This is synchronous: the enabled callback has captured target, but
            // its MainActor Task has not yet called the persistence owner.
            let recheckOwned = onRecheck()
            try require(dispatched && recheckOwned, "collectionRaceOrderingNotEstablished")
            try await wait {
                let domain = self.host.snapshot.state.domains[.collection]
                return domain?.isSaving == false &&
                    (self.host.snapshot.state.owner.collectionPaused == target || domain?.saveFailure != nil)
            }
            let domain = host.snapshot.state.domains[.collection]
            let persisted = try await store.capturePaused()
            let accepted = persisted == target && host.snapshot.state.owner.collectionPaused == target
                && domain?.saveFailure == nil && domain?.pending == nil
            artifacts.append(["kind": "acceptedCollectionDuringRecheck", "target": target,
                "nativeActionAccepted": dispatched, "recheckOwnedBeforeDeferredCommand": recheckOwned,
                "persistedBefore": before, "persistedAfter": persisted,
                "ownerPaused": host.snapshot.state.owner.collectionPaused,
                "pending": domain?.pending.map { String(describing: $0) } ?? "none",
                "failure": domain?.saveFailure.map { String(describing: $0) } ?? "none",
                "sameDirectionCompletedWithoutRetry": accepted])
            try require(try await store.userHidden() == hiddenBefore, "collectionRaceChangedVisibility")
            if !accepted {
                rejectedTargets.append(target)
                // Retain the failed observation, then use the existing explicit
                // same-direction retry to restore a known isolated test state.
                try await wait { self.host.snapshot.capabilities.canChangeCollection }
                await host.perform(.settings(.retry(.collection)))
            }
            try await wait {
                self.host.snapshot.state.owner.collectionPaused == target
                    && self.host.snapshot.capabilities.canChangeCollection
                    && self.host.snapshot.state.domains[.collection]?.saveFailure == nil
            }
        }
        try require(rejectedTargets.isEmpty, "acceptedCollectionRejectedByBackgroundRecheck")
    }

    private func pauseAndHide() async throws {
        try await appearance(.light)
        for (name, paused, hidden) in [("normal", false, false), ("paused", true, false),
                                       ("paused-hidden", true, true), ("hidden", false, true)] {
            try await closeControl(); host.show(page: .general)
            try await setToggle("settings.center.paused", !paused)
            try await wait { self.host.snapshot.state.owner.collectionPaused == paused && self.host.snapshot.capabilities.canChangeCollection }
            try await setToggle("settings.center.hidden", !hidden)
            try await wait { self.host.snapshot.state.owner.isHidden == hidden && self.host.snapshot.capabilities.canChangeVisibility }
            let persistedPaused = try await store.capturePaused()
            let persistedHidden = try await store.userHidden()
            try require(persistedPaused == paused && persistedHidden == hidden, "sqliteIntentMismatch")
            if name == "paused" { try await observePausedCollector() }
            if name == "hidden" { try await observeResumedCollector() }
            await onRefresh()
            try await openControl()
            await capture("control-" + name, window: host.control.window)
            try await closeControl()
        }
        host.show(page: .general)
        try await setToggle("settings.center.hidden", true)
        try await wait { !self.host.snapshot.state.owner.isHidden }
    }

    private func observePausedCollector() async throws {
        let before = try await store.assets(includeUsed: true).count
        let fixtureSHA256 = try createFixture("during-pause")
        // The normal watcher is event-driven (60 ms debounce, then a 150 ms
        // first stability retry), not an idle poll. This fixed two-second
        // interval covers that ordinary event/stability opportunity only.
        let requestedSeconds = 2.0
        let start = ProcessInfo.processInfo.systemUptime
        var samples = 0
        var lastCount = before
        repeat {
            lastCount = try await store.assets(includeUsed: true).count
            samples += 1
            if lastCount != before { break }
            if Task.isCancelled { throw Failure.assertion("reviewCancelled") }
            await settle(50)
        } while ProcessInfo.processInfo.systemUptime - start < requestedSeconds
        // Include a read at/after the end rather than treating the last sleep
        // as an observation of the store.
        lastCount = try await store.assets(includeUsed: true).count
        samples += 1
        artifacts.append(["kind": "pausedCollectorObservation", "fixtureSHA256": fixtureSHA256,
            "requestedSeconds": requestedSeconds, "actualSeconds": ProcessInfo.processInfo.systemUptime - start,
            "samples": samples, "baselineAssetCount": before, "finalAssetCount": lastCount,
            "scope": "No added assets within this fixed interval; no claim about pause-era catch-up after resume"])
        try require(lastCount == before, "pausedCollectorImportedFixture")
    }

    private func observeResumedCollector() async throws {
        let fixtureSHA256 = try createFixture("after-resume")
        let start = ProcessInfo.processInfo.systemUptime
        try await wait(timeout: 10) {
            try await self.store.assets(includeUsed: true).contains { $0.image.sha256 == fixtureSHA256 }
        }
        let record = try await store.assets(includeUsed: true).first { $0.image.sha256 == fixtureSHA256 }
        try require(record != nil, "resumedCollectorDidNotImportNewFixture")
        artifacts.append(["kind": "resumedCollectorObservation", "fixtureSHA256": fixtureSHA256,
            "assetID": record!.id.uuidString.lowercased(), "seconds": ProcessInfo.processInfo.systemUptime - start,
            "scope": "A newly created post-resume fixture was imported; pause-era fixture handling is not asserted"])
    }

    private func archiveEditing() async throws {
        host.show(page: .history)
        // Each selection is saved through the native control and read from the real seconds-based document.
        let presets: [(index: Int, minutes: Double?)] = [(3, 5), (4, 10), (0, nil), (1, 1), (2, 2)]
        for (index, minutes) in presets {
            try select("settings.center.archive.preset", index: index)
            if host.snapshot.state.owner.settings.archiveAfterMinutes != minutes {
                try click("settings.center.archive.save")
                try await wait { self.host.snapshot.state.owner.settings.archiveAfterMinutes == minutes && !self.host.model.hasArchiveDraft }
            }
            try require(try read(ArchiveDocument.self, "lifecycle-settings.json").archiveAfterSeconds == minutes.map { $0 * 60 },
                        "archivePresetSecondsMismatch")
        }
        try select("settings.center.archive.preset", index: 5)
        let (field, editor) = try edit("settings.center.archive.minutes", text: "1.5")
        let originalSelection = NSRange(location: 1, length: 1)
        editor.setSelectedRange(originalSelection)
        let text = editor.string
        await onRefresh(); await settle(50)
        try require(field.currentEditor() === editor && editor.string == text && editor.selectedRange() == originalSelection,
                    "archiveEditorChangedOnRefresh")
        try click("settings.center.archive.save")
        try await wait { self.host.snapshot.state.owner.settings.archiveAfterMinutes == 1.5 && !self.host.model.hasArchiveDraft }
        try require(try read(ArchiveDocument.self, "lifecycle-settings.json").archiveAfterSeconds == 90,
                    "archiveJSONMismatch")
        _ = try edit("settings.center.archive.minutes", text: "2.5")
        try click("settings.center.archive.discard")
        try await wait { !self.host.model.hasArchiveDraft }
        host.show(page: .display); host.show(page: .history)
        await onRefresh()
        try require(!host.model.hasArchiveDraft && host.snapshot.state.owner.settings.archiveAfterMinutes == 1.5,
                    "discardedArchiveReappeared")
        await capture("archive-first-activation-save", window: host.center.window)
    }

    private func expandLayoutDetails() throws {
        for id in ["settings.center.disclosure.display.advanced", "settings.center.disclosure.display.details"] {
            guard let button = try control(id) as? NSButton else { throw Failure.controlUnavailable(id) }
            if button.state != .on { try click(id) }
        }
    }
    private func configurationEditing() async throws {
        host.show(page: .display)
        try expandLayoutDetails()
        let (field, editor) = try edit("settings.center.field.fitWidth", text: "83.25")
        let selection = NSRange(location: 1, length: 2)
        editor.setSelectedRange(selection)
        let text = editor.string
        let old = try Data(contentsOf: environment.root.appendingPathComponent("rift-configuration.json"))
        await onRefresh(); await settle(50)
        try require(field.currentEditor() === editor && editor.string == text && editor.selectedRange() == selection,
                    "configurationEditorChangedOnRefresh")
        try require(try Data(contentsOf: environment.root.appendingPathComponent("rift-configuration.json")) == old,
                    "backgroundRefreshSavedDraft")
        try click("settings.center.layout.apply.display")
        try await wait { self.host.snapshot.state.owner.settings.configuration.fitWidth == 83.25 && !self.host.model.hasLayoutDraft }
        try require(try read(RiftConfiguration.self, "rift-configuration.json").fitWidth == 83.25,
                    "firstConfigurationSaveDidNotPersist")
        _ = try edit("settings.center.field.fitWidth", text: "91.25")
        try click("settings.center.layout.defaults.display")
        let defaultWidth = RiftConfiguration().fitWidth
        try await wait { self.host.snapshot.state.configurationDraft?.fitWidth == defaultWidth }
        try click("settings.center.layout.apply.display")
        try await wait { !self.host.model.hasLayoutDraft }
        try require(try read(RiftConfiguration.self, "rift-configuration.json").fitWidth == defaultWidth, "defaultsDidNotSave")
        let displayedWidth = Double(host.model.text(for: .fitWidth).replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."))
        try require(displayedWidth == defaultWidth, "oldEditorRestoredDiscardedText")
        await capture("display-defaults-after-active-edit", window: host.center.window)
    }

    private func closeEditing() async throws {
        host.show(page: .history)
        try select("settings.center.archive.preset", index: 5)
        let (_, editor) = try edit("settings.center.archive.minutes", text: "3.5")
        let selection = NSRange(location: 1, length: 1); editor.setSelectedRange(selection)
        let text = editor.string
        host.center.window.performClose(nil)
        try await wait { self.host.center.window.attachedSheet != nil }
        let sheet = host.center.window.attachedSheet!
        await capture("close-draft-sheet", window: sheet)
        try click("settings.center.close.continue", window: sheet)
        try await wait { self.host.center.window.attachedSheet == nil }
        await settle(60)
        let field = try control("settings.center.archive.minutes") as! NSTextField
        let restored = field.currentEditor() as? NSTextView
        try require(restored?.string == text && restored?.selectedRange() == selection, "continueDidNotRestoreEditor")
        host.center.window.performClose(nil)
        try await wait { self.host.center.window.attachedSheet != nil }
        try click("settings.center.close.discard", window: host.center.window.attachedSheet!)
        try await wait { !self.host.center.isVisible && !self.host.model.hasArchiveDraft }
        try require(try read(ArchiveDocument.self, "lifecycle-settings.json").archiveAfterSeconds == 90,
                    "closeDiscardChangedSavedArchive")
        host.show(page: .history)
    }

    private func saveFailures() async throws {
        host.show(page: .display)
        _ = try edit("settings.center.field.visibleCountPreference", text: "4")
        let oldCount = host.snapshot.state.owner.settings.configuration.visibleCountPreference
        try await blockedJSON("rift-configuration.json") {
            try self.click("settings.center.layout.apply.display")
            try await self.wait { self.host.snapshot.state.domains[.layout]?.saveFailure != nil }
            try self.require(self.host.snapshot.state.owner.settings.configuration.visibleCountPreference == oldCount,
                             "failedLayoutChangedEffectiveValue")
            self.host.center.window.performClose(nil)
            try await self.wait { self.host.center.window.attachedSheet != nil }
            try self.click("settings.center.close.apply", window: self.host.center.window.attachedSheet!)
            await self.settle(200)
            try self.require(self.host.center.isVisible && self.host.model.hasLayoutDraft,
                             "failedCloseApplyDismissedDraft")
        }
        if let sheet = host.center.window.attachedSheet {
            try click("settings.center.close.continue", window: sheet)
            try await wait { self.host.center.window.attachedSheet == nil }
        }
        host.show(page: .display)
        let beforeAppearance = host.snapshot.appearance.selection
        let target = beforeAppearance == .dark ? SettingsAppearanceChoice.light : .dark
        try await blockedJSON("app-presentation-settings.json") {
            try self.select("settings.center.appearance", index: SettingsAppearanceChoice.allCases.firstIndex(of: target)!)
            try await self.wait { self.host.snapshot.appearance.failure != nil }
            try self.require(self.host.snapshot.appearance.selection == beforeAppearance, "failedAppearanceChangedEffectiveValue")
        }
        try require(host.snapshot.state.domains[.layout]?.saveFailure != nil, "appearanceClearedLayoutError")
        try await openControl()
        try require(RiftControlCenterPresentation(host.snapshot).state == .attention, "saveFailureNotVisibleInControl")
        await capture("control-save-failure", window: host.control.window)
        try await closeControl()
        host.show(page: .history)
        try select("settings.center.archive.preset", index: 5)
        _ = try edit("settings.center.archive.minutes", text: "1.75")
        try click("settings.center.archive.save")
        try await wait { self.host.snapshot.state.owner.settings.archiveAfterMinutes == 1.75 }
        try require(host.snapshot.appearance.failure != nil && host.snapshot.state.domains[.layout]?.saveFailure != nil,
                    "unrelatedSaveClearedErrors")
        host.show(page: .display); try click("settings.center.appearance.retry")
        try await wait { self.host.snapshot.appearance.failure == nil && self.host.snapshot.appearance.selection == target }
        try require(host.snapshot.state.domains[.layout]?.saveFailure != nil, "appearanceRetryClearedLayoutError")
        host.show(page: .display); try click("settings.center.retry.layout")
        try await wait { self.host.snapshot.state.domains[.layout]?.saveFailure == nil && !self.host.model.hasLayoutDraft }
        try require(try read(RiftConfiguration.self, "rift-configuration.json").visibleCountPreference == 4,
                    "retrySavedWrongConfigurationTarget")
        await capture("independent-errors-resolved", window: host.center.window)
    }

    private func motion() async throws {
        host.show(page: .motion)
        try select("settings.center.arrival", index: 1)
        try await wait { self.host.snapshot.state.owner.settings.arrivalMode == .magnet }
        guard let preview = find("settings.center.arrivalPreview", in: host.center.window.contentView) else { throw Failure.controlUnavailable("arrivalPreview") }
        try require(animationCount(preview.layer) == 0, "selectingMotionAutoPlayed")
        try click("settings.center.arrival.preview")
        await settle(50)
        if !host.snapshot.accessibility.reduceMotion { try require(animationCount(preview.layer) > 0, "explicitMotionDidNotPlay") }
        await capture("explicit-arrival-preview", window: host.center.window)
        host.show(page: .general)
        try require(animationCount(preview.layer) == 0, "navigationDidNotStopPreview")
    }

    private func onboarding() async throws {
        let beforePaused = try await store.capturePaused(), beforeHidden = try await store.userHidden()
        for theme in [SettingsAppearanceChoice.light, .dark] {
            try await appearance(theme)
            try require(host.showOnboarding(), "onboardingNotPresented")
            for step in 0..<3 {
                try require(host.onboarding.currentStep == step, "onboardingWrongStep")
                await settle()
                let window = host.onboarding.window
                artifacts.append(["kind": "onboardingGeometry", "theme": theme.rawValue, "step": step + 1,
                    "windowFrame": rect(window.frame), "contentBounds": rect(window.contentView?.bounds ?? .zero),
                    "minimumSize": [window.minSize.width, window.minSize.height],
                    "contentMinimumSize": [window.contentMinSize.width, window.contentMinSize.height],
                    "contentFittingSize": [window.contentView?.fittingSize.width ?? 0, window.contentView?.fittingSize.height ?? 0],
                    "contentHasAmbiguousLayout": window.contentView?.hasAmbiguousLayout ?? false])
                // Preserve the real frame and pixels even when the size check
                // fails; an assertion must not erase the evidence it rejects.
                await capture("onboarding-\(theme.rawValue)-\(step + 1)", window: window)
                if let visible = window.screen?.visibleFrame, visible.width >= 584, visible.height >= 453 {
                    try require(abs(window.frame.width - 584) <= 1 && abs(window.frame.height - 453) <= 1,
                                "onboardingOuterSizeMismatch")
                }
                try click("onboarding.next", window: host.onboarding.window)
            }
            try await wait { !self.host.onboarding.isVisible }
        }
        let afterPaused = try await store.capturePaused()
        let afterHidden = try await store.userHidden()
        try require(afterPaused == beforePaused && afterHidden == beforeHidden,
                    "onboardingChangedCollectionOrVisibility")
    }

    private func resize() async throws {
        host.show(page: .display)
        let original = host.center.window.frame
        var small = original; small.size = SettingsNativeStyle.settingsMinimumSize
        host.center.window.setFrame(small, display: true)
        await settle()
        let size = host.center.window.frame.size
        await capture("settings-minimum-size", window: host.center.window)
        for page in SettingsPage.allCases {
            host.show(page: page)
            await settle()
            guard let scroll = find("settings.center.scroll", in: host.center.window.contentView) as? NSScrollView,
                  let document = scroll.documentView else { throw Failure.controlUnavailable("settingsScroll") }
            try require(document.frame.width <= scroll.contentView.bounds.width + 1, "minimumWindowHorizontalOverflow")
            if page != .display { await capture("settings-minimum-" + page.rawValue, window: host.center.window) }
        }
        host.show(page: .display)
        try expandLayoutDetails()
        let originalWidth = host.snapshot.state.owner.settings.configuration.fitWidth
        let testWidth = originalWidth == 82 ? 83.0 : 82.0
        _ = try edit("settings.center.field.fitWidth", text: String(testWidth))
        try await wait { self.host.model.hasLayoutDraft }
        await settle()
        guard let scroll = find("settings.center.scroll", in: host.center.window.contentView) as? NSScrollView,
              let document = scroll.documentView,
              let apply = find("settings.center.layout.apply.display", in: document) else {
            throw Failure.controlUnavailable("minimumWindowScrollTarget")
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        let applyRect = apply.convert(apply.bounds, to: scroll.contentView)
        try require(!apply.isHiddenOrHasHiddenAncestor && scroll.contentView.bounds.contains(applyRect), "minimumWindowApplyUnreachableByScrolling")
        artifacts.append(["kind": "minimumWindowScroll", "page": "display", "detailsExpanded": true,
            "documentHeight": document.bounds.height, "viewportHeight": scroll.contentView.bounds.height,
            "scrollOffset": scroll.contentView.bounds.origin.y, "applyFullyVisible": true])
        await capture("settings-minimum-display-scrolled", window: host.center.window)
        try click("settings.center.layout.apply.display")
        try await wait { self.host.snapshot.state.owner.settings.configuration.fitWidth == testWidth && !self.host.model.hasLayoutDraft }
        _ = try edit("settings.center.field.fitWidth", text: String(originalWidth))
        try click("settings.center.layout.apply.display")
        try await wait { self.host.snapshot.state.owner.settings.configuration.fitWidth == originalWidth && !self.host.model.hasLayoutDraft }
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        host.center.window.performClose(nil)
        try await wait { !self.host.center.isVisible }
        host.show(page: .display)
        try require(host.center.window.frame.size == size, "reopenLostWindowSize")
        host.center.window.setFrame(original, display: true)
    }

    // A focused mode in the same UUID-scoped App, using its actual owners and
    // native control actions. No business callback is invoked directly by this suite.
    private func runHistoryStyleCases() async {
        await runCase("history-default-and-three-collector-assets") { try await self.historyFixtures() }
        await runCase("history-two-window-style-search-filter-uuid") { try await self.historySynchronization() }
        await runCase("history-original-200-percent-survives-renderer-change") { try await self.historyOriginal() }
        await runCase("history-both-renderers-light-dark-minimum") { try await self.historyVisuals() }
        await runCase("history-one-asset-remove-and-restore") { try await self.historyVisibilityActions() }
        await runCase("history-final-integrity-and-persisted-style") {
            let history = try self.reviewHistory()
            self.host.show(page: .history)
            try await self.chooseHistoryStyle(.imageGrid, fromSettings: true)
            try self.require(history.displayStyle == .imageGrid, "historyFinalRendererMismatch")
            try await self.integrity()
            let records = try await self.store.assets(includeUsed: true)
            let domain = try self.historyDomain()
            try self.require(domain.value[HistoryDisplayPreferences.key] as? String == HistoryDisplayStyle.imageGrid.rawValue,
                             "historyFinalRawPreferenceMismatch")
            self.artifacts.append(["kind": "historyFinalState", "assetRowsSHA256": try self.assetRowsDigest(records),
                "assetCount": records.count, "selectedStyle": self.host.historyDisplay.selection.rawValue,
                "rawDomainSHA256": self.digest(domain.bytes), "rawDomain": domain.value,
                "inputMethod": "PROGRAMMATIC_NATIVE_CONTROLS", "pageScope": "First real page with three collected fixtures; next/previous are disabled, no fabricated second page"])
        }
    }

    private func reviewHistory() throws -> RiftHistoryController {
        guard historyStyleReview, let historyController else { throw Failure.controlUnavailable("actualHistoryController") }
        return historyController
    }
    private func allViews(_ view: NSView?) -> [NSView] {
        guard let view else { return [] }; return [view] + view.subviews.flatMap { allViews($0) }
    }
    private func assetRowsDigest(_ records: [AssetRecord]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return digest(try encoder.encode(records.sorted { $0.id.uuidString < $1.id.uuidString }))
    }
    private func historyDomain() throws -> (value: [String: Any], bytes: Data) {
        let name = HistoryDisplayPreferences.reviewSuiteName(root: environment.root)
        guard name.hasPrefix("com.riftlet.history-display.review."), let defaults = UserDefaults(suiteName: name) else {
            throw Failure.unsafeEnvironment
        }
        let value = defaults.persistentDomain(forName: name) ?? [:]
        return (value, try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }
    private func assertHistoryReadOnly(_ phase: String) async throws {
        let records = try await store.assets(includeUsed: true)
        try require(!historyReadOnlyBaseline.isEmpty && records == historyReadOnlyBaseline, "historyReadOnlyChangedAssetRows:" + phase)
        try await integrity()
        artifacts.append(["kind": "historyReadOnlyAssets", "phase": phase,
            "allAssetRowsEqual": true, "assetRowsSHA256": try assetRowsDigest(records)])
    }
    private func chooseHistoryStyle(_ style: HistoryDisplayStyle, fromSettings: Bool) async throws {
        let history = try reviewHistory()
        let window = fromSettings ? host.center.window : history.window
        let id = fromSettings ? "settings.center.history.displayStyle" : "history.displayStyle"
        guard let index = HistoryDisplayStyle.allCases.firstIndex(of: style) else { throw Failure.controlUnavailable(id) }
        try select(id, index: index, window: window)
        try await wait {
            let settings = self.find("settings.center.history.displayStyle", in: self.host.center.window.contentView) as? NSSegmentedControl
            let local = self.find("history.displayStyle", in: history.window.contentView) as? NSSegmentedControl
            return self.host.historyDisplay.selection == style && history.displayStyle == style
                && settings?.selectedSegment == index && local?.selectedSegment == index
        }
    }
    private func historySearch(_ text: String) async throws {
        let window = try reviewHistory().window
        guard let field = try control("history.search", window: window) as? NSSearchField else { throw Failure.controlUnavailable("history.search") }
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else { throw Failure.assertion("historyNativeSearchEditorMissing") }
        editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        window.makeFirstResponder(nil)
        try await wait { field.stringValue == text }
    }
    private func historyTable() throws -> NSTableView {
        guard let table = find("history.current.table", in: try reviewHistory().window.contentView) as? NSTableView else {
            throw Failure.controlUnavailable("history.current.table")
        }
        return table
    }
    private func selectHistoryFixture() async throws -> UUID {
        guard let id = historyFixtureIDs.first else { throw Failure.assertion("historyFixtureIdentityMissing") }
        let history = try reviewHistory()
        if history.displayStyle != .current { try await chooseHistoryStyle(.current, fromSettings: false) }
        try await historySearch(id.uuidString)
        try await wait { try self.historyTable().numberOfRows == 1 }
        let table = try historyTable(); table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try await wait {
            history.selectedRecordID == id && (self.find("history.detail.image", in: history.window.contentView) as? NSImageView)?.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil
        }
        try require(allViews(history.window.contentView).contains { $0.toolTip == id.uuidString }, "historyFullDetailUUIDMissing")
        return id
    }
    private func historyFixtures() async throws {
        let history = try reviewHistory()
        try require(host.historyDisplay.selection == .current && history.displayStyle == .current, "freshHistoryDefaultNotCurrent")
        try require(try historyDomain().value[HistoryDisplayPreferences.key] == nil, "freshHistoryDomainNotEmpty")
        host.show(page: .general)
        try await setToggle("settings.center.paused", true)
        try await wait { !self.host.snapshot.state.owner.collectionPaused }
        for (index, size) in [(640, 640), (320, 640), (800, 400)].enumerated() {
            let hash = try createFixture("history-\(index)", width: size.0, height: size.1)
            try await wait(timeout: 10) { try await self.store.assets(includeUsed: true).contains { $0.image.sha256 == hash } }
            let records = try await store.assets(includeUsed: true)
            guard let record = records.first(where: { $0.image.sha256 == hash }) else { throw Failure.assertion("collectedHistoryFixtureMissing") }
            historyFixtureIDs.append(record.id)
        }
        await onRefresh(); onHistory()
        try await wait {
            let rows = try self.historyTable().numberOfRows
            return history.window.isVisible && rows == self.initialAssetIDs.count + 3
        }
        historyReadOnlyBaseline = try await store.assets(includeUsed: true)
        try require(historyReadOnlyBaseline.count == initialAssetIDs.count + 3 && Set(historyFixtureIDs).count == 3,
                    "historyCollectorCountMismatch")
        host.show(page: .history)
        artifacts.append(["kind": "historyFixtures", "UUIDs": historyFixtureIDs.map(\.uuidString),
            "source": "three synthetic PNGs through the real isolated collector", "assetRowsSHA256": try assetRowsDigest(historyReadOnlyBaseline)])
    }
    private func historySynchronization() async throws {
        let history = try reviewHistory(), id = try await selectHistoryFixture()
        let frame = history.window.frame
        guard let count = find("history.count", in: history.window.contentView) as? NSTextField else { throw Failure.controlUnavailable("history.count") }
        let page = count.stringValue
        try require(page.contains("第 1 页"), "historyFirstPageNotPresented")
        for key in ["history.previous", "history.next"] {
            try require((find(key, in: history.window.contentView) as? NSControl)?.isEnabled == false, "historyUnexpectedPaginationEnabled")
        }
        // Both windows remain instantiated; each real popup updates the other.
        try await chooseHistoryStyle(.imageGrid, fromSettings: true)
        try require(history.selectedRecordID == id && history.window.frame == frame && count.stringValue == page,
                    "settingsStyleChangedSelectionPageOrFrame")
        try require((find("history.search", in: history.window.contentView) as? NSSearchField)?.stringValue == id.uuidString,
                    "settingsStyleClearedSearch")
        await capture("history-settings-grid-synchronized", window: host.center.window)
        try await chooseHistoryStyle(.current, fromSettings: false)
        try require(history.selectedRecordID == id && count.stringValue == page, "historyStyleLostUUIDOrPage")
        try select("history.grid.filter", index: 3, window: history.window)
        try await wait { try self.historyTable().numberOfRows == 0 }
        try await chooseHistoryStyle(.imageGrid, fromSettings: true)
        try require((find("history.grid.filter", in: history.window.contentView) as? NSPopUpButton)?.indexOfSelectedItem == 3,
                    "historyStyleLostFilter")
        try await chooseHistoryStyle(.current, fromSettings: false)
        try require((find("history.grid.filter", in: history.window.contentView) as? NSPopUpButton)?.indexOfSelectedItem == 3, "historyCurrentFilterLost")
        try select("history.grid.filter", index: 0, window: history.window)
        _ = try await selectHistoryFixture()
        try await assertHistoryReadOnly("search-filter-two-window-style")
        artifacts.append(["kind": "historyTwoWindowState", "fullSelectedUUID": id.uuidString,
            "searchPreserved": true, "filterPreserved": true, "firstPagePreserved": true,
            "settingsToHistory": "imageGrid", "historyToSettings": "current"])
    }
    private func visibleGridImages(_ window: NSWindow) -> [NSImageView] {
        allViews(window.contentView).filter {
            $0.identifier?.rawValue.hasPrefix("history.grid.item.") == true && !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty
        }.flatMap { allViews($0).compactMap { $0 as? NSImageView } }.filter { !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty }
    }
    private func historyOriginal() async throws {
        let history = try reviewHistory(), id = try await selectHistoryFixture(), table = try historyTable()
        guard let action = table.doubleAction else { throw Failure.controlUnavailable("history.table.doubleAction") }
        try require(NSApp.sendAction(action, to: table.target, from: table), "historyOriginalActionNotDispatched")
        try await wait { NSApp.windows.contains { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible } }
        guard let preview = NSApp.windows.first(where: { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible }),
              let image = find("history.preview.image", in: preview.contentView) as? NSImageView,
              let zoom = try control("history.preview.zoom", window: preview) as? NSSegmentedControl, let action = zoom.action,
              let record = historyReadOnlyBaseline.first(where: { $0.id == id }) else { throw Failure.controlUnavailable("history.preview") }
        try await wait { image.image != nil }
        zoom.selectedSegment = 2
        try require(NSApp.sendAction(action, to: zoom.target, from: zoom), "historyZoomActionNotDispatched")
        try await wait { image.image != nil && abs(image.frame.width - Double(record.image.pixelWidth * 2)) <= 1
            && abs(image.frame.height - Double(record.image.pixelHeight * 2)) <= 1 }
        let originalWindow = preview.windowNumber
        for style in [HistoryDisplayStyle.imageGrid, .current, .imageGrid] {
            try await chooseHistoryStyle(style, fromSettings: style != .current)
            try require(history.selectedRecordID == id && preview.isVisible && preview.windowNumber == originalWindow
                && zoom.selectedSegment == 2 && image.image != nil
                && abs(image.frame.width - Double(record.image.pixelWidth * 2)) <= 1
                && abs(image.frame.height - Double(record.image.pixelHeight * 2)) <= 1, "rendererChangeLostOriginalUUIDWindowZoom")
            if style == .imageGrid {
                try await wait { let images = self.visibleGridImages(history.window); return !images.isEmpty && images.allSatisfy { $0.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil } }
                artifacts.append(["kind": "historyGridWithOriginal", "fullSelectedUUID": id.uuidString,
                    "originalWindowNumber": originalWindow, "zoomSegment": 2, "loadedVisibleThumbnailCount": visibleGridImages(history.window).count])
            }
        }
        await capture("history-original-200-percent", window: preview)
        await capture("history-grid-with-original-still-open", window: history.window)
        preview.performClose(nil)
        try await wait { !preview.isVisible }
        // Exercise the grid's own accessible item selection and its native
        // original button as a second entry, not a direct controller method.
        try await historySearch("")
        guard historyFixtureIDs.count == 3 else { throw Failure.assertion("gridOriginalFixtureMissing") }
        let gridID = historyFixtureIDs[1]
        let cellID = "history.grid.item." + gridID.uuidString
        try await wait { self.find(cellID, in: history.window.contentView)?.isHiddenOrHasHiddenAncestor == false }
        guard let cell = find(cellID, in: history.window.contentView) else { throw Failure.controlUnavailable(cellID) }
        try require(cell.accessibilityPerformPress(), "historyGridNativeAccessibilitySelectionRejected")
        try await wait { history.selectedRecordID == gridID }
        try click("history.original", window: history.window)
        try await wait { NSApp.windows.contains { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible } }
        guard let gridPreview = NSApp.windows.first(where: { $0.identifier?.rawValue == "RiftletHistoryPreview" && $0.isVisible }),
              let gridImage = find("history.preview.image", in: gridPreview.contentView) as? NSImageView else {
            throw Failure.controlUnavailable("history.grid.original")
        }
        try await wait { gridImage.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil }
        try require(history.selectedRecordID == gridID && gridPreview.title.contains(String(gridID.uuidString.prefix(8)))
            && allViews(history.window.contentView).contains { $0.toolTip == gridID.uuidString }, "gridOriginalIdentityMismatch")
        artifacts.append(["kind": "historyGridOriginalEntry", "fullSelectedUUID": gridID.uuidString,
            "selectionAction": "native item accessibilityPerformPress", "openAction": "native history.original NSButton", "bitmapLoaded": true])
        await capture("history-grid-original-button", window: gridPreview)
        gridPreview.performClose(nil)
        try await wait { !gridPreview.isVisible }
        try await assertHistoryReadOnly("original-and-renderer-changes")
    }
    private func historyDetailScroll(_ window: NSWindow) throws -> NSScrollView {
        guard let image = find("history.detail.image", in: window.contentView),
              let scroll = image.enclosingScrollView, scroll.window === window,
              let document = scroll.documentView, image.isDescendant(of: document) else {
            throw Failure.controlUnavailable("history.detail.scroll")
        }
        return scroll
    }
    private func historyDetailInitialViewport(_ window: NSWindow) throws {
        let scroll = try historyDetailScroll(window)
        guard let document = scroll.documentView else { throw Failure.controlUnavailable("history.detail.document") }
        window.contentView?.layoutSubtreeIfNeeded(); scroll.tile()
        let y = document.isFlipped ? document.bounds.minY : max(document.bounds.minY, document.bounds.maxY - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: document.bounds.minX, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func verifyHistoryDetailReachability(_ name: String, window: NSWindow) async throws {
        let scroll = try historyDetailScroll(window)
        guard let document = scroll.documentView else { throw Failure.controlUnavailable("history.detail.document") }
        let ids = ["history.original", "history.reveal", "history.restore", "history.remove"]
        let actions = ids.compactMap { find($0, in: document) as? NSControl }.filter {
            !$0.isHiddenOrHasHiddenAncestor && $0.isEnabled
        }
        try require(!actions.isEmpty, "historyNoAvailableDetailActions")
        do {
            for action in actions {
                let before = document.visibleRect
                let target = document.convert(action.bounds, from: action)
                let requested = document.scrollToVisible(target)
                scroll.reflectScrolledClipView(scroll.contentView)
                window.contentView?.layoutSubtreeIfNeeded()
                let actual = document.convert(action.bounds, from: action)
                let visible = document.visibleRect
                let reachable = !actual.isEmpty && visible.insetBy(dx: -1, dy: -1).contains(actual)
                artifacts.append(["kind": "historyDetailActionReachability", "frameName": name,
                    "identifier": action.identifier?.rawValue ?? "", "enabled": action.isEnabled,
                    "documentFrame": rect(document.frame), "documentFittingSize": [document.fittingSize.width, document.fittingSize.height],
                    "visibleRectBefore": rect(before), "visibleRectAfter": rect(visible), "actionRectInDocument": rect(actual),
                    "scrollRequestedMovement": requested, "fullyReachable": reachable,
                    "method": "Existing detail NSScrollView document.scrollToVisible; no action invoked"])
                try require(reachable, "historyDetailActionClippedAfterScroll:" + (action.identifier?.rawValue ?? "unknown"))
            }
            let y = document.isFlipped ? max(document.bounds.minY, document.bounds.maxY - scroll.contentView.bounds.height) : document.bounds.minY
            scroll.contentView.scroll(to: NSPoint(x: document.bounds.minX, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            await capture(name + "-bottom-actions", window: window)
        } catch {
            await capture(name + "-unreachable-actions", window: window)
            throw error
        }
    }
    private func historyVisuals() async throws {
        let history = try reviewHistory()
        try await chooseHistoryStyle(.current, fromSettings: false)
        try await historySearch("")
        try await wait { try self.historyTable().numberOfRows == self.historyReadOnlyBaseline.count }
        let originalFrame = history.window.frame
        for theme in [SettingsAppearanceChoice.light, .dark] {
            try await appearance(theme); host.show(page: .history)
            for style in HistoryDisplayStyle.allCases {
                try await chooseHistoryStyle(style, fromSettings: true)
                for minimum in [false, true] {
                    let size = minimum ? history.window.minSize : NSSize(width: style == .current ? 760 : 828, height: style == .current ? 560 : 582)
                    history.window.setFrame(NSRect(origin: originalFrame.origin, size: size), display: true)
                    history.window.contentView?.layoutSubtreeIfNeeded()
                    try await wait { abs(history.window.frame.width - size.width) <= 1 && abs(history.window.frame.height - size.height) <= 1 }
                    if style == .imageGrid {
                        try await wait { let images = self.visibleGridImages(history.window); return !images.isEmpty && images.allSatisfy { $0.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil } }
                    } else {
                        try await wait { (self.find("history.detail.image", in: history.window.contentView) as? NSImageView)?.image != nil }
                    }
                    let name = "history-" + theme.rawValue + "-" + style.rawValue + (minimum ? "-minimum" : "-standard")
                    try historyDetailInitialViewport(history.window)
                    await capture(name, window: history.window)
                    guard let captured = frames.last, captured["name"] as? String == name,
                          captured["status"] as? String == "RECORDED_NATIVE_WINDOWSERVER",
                          let actual = captured["windowServerBounds"] as? [Double], actual.count == 4 else {
                        throw Failure.assertion("historyOwnedWindowFrameNotCaptured")
                    }
                    try require(abs(actual[2] - size.width) <= 1 && abs(actual[3] - size.height) <= 1,
                                "historyWindowServerSizeMismatch")
                    if minimum { try await verifyHistoryDetailReachability(name, window: history.window) }
                }
            }
        }
        history.window.setFrame(originalFrame, display: true)
        try await assertHistoryReadOnly("all-renderer-theme-size-presentations")
    }
    private func historyVisibilityActions() async throws {
        let history = try reviewHistory(), id = try await selectHistoryFixture()
        let initial = try await store.assets(includeUsed: true)
        guard let original = initial.first(where: { $0.id == id }) else { throw Failure.assertion("historyRemoveTargetMissing") }
        for style in HistoryDisplayStyle.allCases {
            try await chooseHistoryStyle(style, fromSettings: true)
            try require(history.selectedRecordID == id, "historyVisibilityActionLostUUID")
            history.window.setFrame(NSRect(origin: history.window.frame.origin, size: history.window.minSize), display: true)
            let before = try await store.assets(includeUsed: true)
            guard let target = before.first(where: { $0.id == id }) else { throw Failure.assertion("historyRemoveTargetMissing") }
            try require(target.visibility == .visible, "historyRemoveTargetNotVisible")
            try click("history.remove", window: history.window)
            try await wait { try await self.store.asset(id: id)?.visibility == .removed }
            await onRefresh()
            let removed = try await store.assets(includeUsed: true)
            try require(removed.filter { $0.id != id } == before.filter { $0.id != id }, "historyRemoveChangedOtherAssets")
            try await wait { (self.find("history.restore", in: history.window.contentView) as? NSControl)?.isEnabled == true }
            try await verifyHistoryDetailReachability("history-" + style.rawValue + "-removed-minimum", window: history.window)
            try click("history.restore", window: history.window)
            try await wait { try await self.store.asset(id: id)?.visibility == .visible }
            await onRefresh()
            let restored = try await store.assets(includeUsed: true)
            guard let after = restored.first(where: { $0.id == id }) else { throw Failure.assertion("historyRestoredTargetMissing") }
            try require(restored.count == before.count && restored.filter { $0.id != id } == before.filter { $0.id != id }, "historyRestoreChangedOtherAssets")
            try require(after.image == target.image && after.sequence == target.sequence && after.status == target.status
                && after.activeOperationID == target.activeOperationID && after.visibilityRevision == target.visibilityRevision + 2,
                "historyRemoveRestoreChangedImmutableState")
            try await integrity()
            artifacts.append(["kind": "historyRemoveRestore", "style": style.rawValue, "fullTargetUUID": id.uuidString,
                "otherAssetRowsUnchanged": true, "mediaUnchanged": true, "visibilityPath": ["visible", "removed", "visible"],
                "beforeVisibilityRevision": target.visibilityRevision, "afterVisibilityRevision": after.visibilityRevision,
                "beforeAssetRowsSHA256": try assetRowsDigest(before), "afterAssetRowsSHA256": try assetRowsDigest(restored)])
        }
        let final = try await store.assets(includeUsed: true)
        try require(final.first(where: { $0.id == id })?.visibilityRevision == original.visibilityRevision + 4
            && final.filter { $0.id != id } == initial.filter { $0.id != id }, "historyBothStylesVisibilityRoundtripMismatch")
    }

    private func verifyHistoryStyleRestart(output: URL, initialChecks: [[String: Any]], prior: [String: Any]?, executableSHA: String?) async -> URL? {
        var checks = initialChecks
        var beforeDomain: Data?
        do {
            guard let prior, prior["status"] as? String == "PASS_SCOPED_NATIVE_REVIEW",
                  let expected = (prior["artifacts"] as? [[String: Any]])?.last(where: { $0["kind"] as? String == "historyFinalState" }),
                  let expectedRows = expected["assetRowsSHA256"] as? String,
                  let expectedDomain = expected["rawDomainSHA256"] as? String else { throw Failure.assertion("successfulHistoryRunRequired") }
            let history = try reviewHistory(), raw = try historyDomain(); beforeDomain = raw.bytes
            try require(digest(raw.bytes) == expectedDomain && raw.value[HistoryDisplayPreferences.key] as? String == "imageGrid",
                        "historyRestartRawPreferenceMismatch")
            try require(host.historyDisplay.selection == .imageGrid && host.snapshot.historyDisplayStyle == .imageGrid
                && history.displayStyle == .imageGrid, "historyRestartLoadedOwnerMismatch")
            checks.append(["check": "history-raw-domain-and-actual-loaded-owner", "status": "PASS",
                "selection": host.historyDisplay.selection.rawValue, "rawDomainSHA256": digest(raw.bytes)])
            let records = try await store.assets(includeUsed: true)
            try require(try assetRowsDigest(records) == expectedRows, "historyRestartChangedFullAssetRows")
            try await integrity()
            checks.append(["check": "history-full-asset-rows-and-media", "status": "PASS", "assetRowsSHA256": expectedRows,
                "assetCount": records.count, "completeOperationTableCount": "runner read-only SQL" ])
            try require(!history.window.isVisible && !host.center.isVisible && !host.onboarding.isVisible && !host.control.isShown,
                        "historyRestartPresentedWindow")
            checks.append(["check": "history-read-only-restart-no-window", "status": "PASS"])
            try require(try historyDomain().bytes == beforeDomain, "historyRestartChangedRawDomain")
            checks.append(["check": "history-preference-unchanged-during-readback", "status": "PASS"])
        } catch { checks.append(["check": "history-restart", "status": "FAIL", "reason": code(error)]) }
        let report: [String: Any] = ["schema": 1, "reviewID": environment.identifier.uuidString.lowercased(),
            "reviewMode": "historyStyle", "status": checks.contains { $0["status"] as? String == "FAIL" } ? "FAIL" : "PASS_SCOPED_NATIVE_RESTART",
            "completed": true, "processPID": ProcessInfo.processInfo.processIdentifier,
            "executableSHA256": executableSHA as Any? ?? NSNull(), "beganUTC": ISO8601DateFormatter().string(from: began),
            "checks": checks, "driverChangedPreferences": false, "createdFixtures": 0,
            "scope": "Same binary, new process, exact prior report and UUID root; real loaded history owner and raw isolated suite readback; no window presentation",
            "notRun": ["productionData", "browserAttachment", "physicalInput", "systemPermissions", "loginRegistration"]]
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
            return output
        } catch { return nil }
    }

    private func history() async throws {
        let old = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        try await closeControl(); onHistory()
        try await wait { NSApp.windows.contains { $0.isVisible && !old.contains($0.windowNumber) && $0.styleMask.contains(.titled) } }
        let history = NSApp.windows.first { $0.isVisible && !old.contains($0.windowNumber) && $0.styleMask.contains(.titled) }
        await capture("history-real-isolated-records", window: history)
        try require(try await store.history().count >= initialAssetIDs.count + 1, "historyLostCollectedFixture")
        history?.close()
    }

    private func integrity() async throws {
        let records = try await store.assets(includeUsed: true)
        try require(initialAssetIDs.isSubset(of: Set(records.map(\.id))), "initialAssetsMissing")
        for record in records {
            let url = environment.root.appendingPathComponent("media").appendingPathComponent(record.image.fileName)
            try require(url.resolvingSymlinksInPath() == url, "privateMediaSymlink")
            let data = try Data(contentsOf: url)
            try require(Int64(data.count) == record.image.byteCount && digest(data) == record.image.sha256,
                        "originalPrivateMediaChanged")
        }
        let unresolved = try await store.unresolvedOperations()
        let successful = try await store.successfulOperations()
        try require(unresolved.isEmpty && successful.isEmpty && records.allSatisfy { $0.activeOperationID == nil },
                    "unexpectedUploadOperation")
        artifacts.append(["kind": "integrity", "assetCount": records.count,
                          "allPrivateMediaDigestsMatch": true, "unresolvedOperations": unresolved.count,
                          "successfulOperations": successful.count, "assetsWithOperation": 0])
    }

    private func openControl() async throws {
        guard let button = statusItem.button, button.isEnabled, button.window?.isVisible == true,
              let action = button.action, let target = button.target else { throw Failure.controlUnavailable("statusItem") }
        let start = ProcessInfo.processInfo.systemUptime
        defer { recordControlTransition("open", began: start) }
        // A collector observation can yield for seconds after host.show().
        // Request our own window once if that earlier activation no longer
        // holds, then retain the actual foreground/stability assertion. This
        // is software-driver sequencing, never a product focus requirement.
        if !NSApp.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            recordPresentationEvent("driver.activationBeforeStatusAction")
            host.show(page: host.center.selectedPage)
        }
        var activeSamples = 0
        try await wait(timeout: 5) {
            let active = self.host.center.window.isVisible && NSApp.isActive
                && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            activeSamples = active ? activeSamples + 1 : 0
            return activeSamples >= 2
        }
        recordPresentationEvent("beforeStatusAction")
        // isShown reports presentation intent before the animated native window
        // is attached/visible. One action, then wait for the actual owned window;
        // never issue a second toggle to recover a missing screenshot.
        if !host.control.isShown {
            // Exercise the real target/action and popover, without asking
            // NSStatusBarButton.performClick to simulate tracking. Its native
            // activation handback was observed to close a reused key popover.
            // This remains software native-action evidence, not pointer input.
            artifacts.append(["kind": "statusBarInvocation", "method": "NSApplication.sendAction",
                              "scope": "native target-action; physical status-bar pointer NOT_RUN"])
            try require(NSApp.sendAction(action, to: target, from: button), "statusActionNotDispatched")
        }
        recordPresentationEvent("afterStatusAction")
        try await wait {
            guard self.host.control.isShown, let window = self.host.control.window else { return false }
            return window.isVisible && window.windowNumber > 0 && NSApp.windows.contains { $0 === window }
        }
        if let window = host.control.window {
            do { try await waitForFullOwnedWindow(window, context: "popover-open") }
            catch {
                await capture("control-unsettled-\(frames.count)", window: window, verifyPresentation: false)
                throw error
            }
        }
    }

    private func closeControl() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        defer { recordControlTransition("close", began: start) }
        recordPresentationEvent("driver.explicitCloseIntent")
        host.control.close()
        try await wait { !self.host.control.isShown && self.host.control.window?.isVisible != true }
    }

    private func recordControlTransition(_ action: String, began: Double) {
        artifacts.append(["kind": "controlPresentationTransition", "action": action,
            "seconds": ProcessInfo.processInfo.systemUptime - began, "isShown": host.control.isShown,
            "applicationActive": NSApp.isActive,
            "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier as Any? ?? NSNull(),
            "windowVisible": host.control.window?.isVisible ?? false,
            "windowNumber": host.control.window?.windowNumber as Any? ?? NSNull(),
            "ownedWindow": host.control.window.map { window in NSApp.windows.contains { $0 === window } } ?? false])
    }

    private func startPresentationTrace() {
        stopPresentationTrace()
        let center = NotificationCenter.default
        for (name, event) in [(NSApplication.didBecomeActiveNotification, "app.didBecomeActive"),
                              (NSApplication.didResignActiveNotification, "app.didResignActive")] {
            presentationObservers.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recordPresentationEvent(event) }
            })
        }
        for (name, event) in [(NSPopover.willShowNotification, "popover.willShow"),
                              (NSPopover.didShowNotification, "popover.didShow"),
                              (NSPopover.willCloseNotification, "popover.willClose"),
                              (NSPopover.didCloseNotification, "popover.didClose")] {
            presentationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let popover = notification.object as? NSPopover,
                          popover.contentViewController?.view === self.host.control.contentView else { return }
                    self.recordPresentationEvent(event)
                }
            })
        }
        for (name, event) in [(NSWindow.didBecomeKeyNotification, "popover.windowDidBecomeKey"),
                              (NSWindow.didResignKeyNotification, "popover.windowDidResignKey")] {
            presentationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let window = notification.object as? NSWindow,
                          window === self.host.control.window,
                          NSApp.windows.contains(where: { $0 === window }) else { return }
                    self.recordPresentationEvent(event)
                }
            })
        }
        presentationMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.presentationMouseTraceCount < 64,
                      var metadata = self.ownedMouseMetadata(event) else { return }
                self.presentationMouseTraceCount += 1
                metadata["kind"] = "ownPresentationMouseEvent"
                metadata["elapsedSeconds"] = ProcessInfo.processInfo.systemUptime - self.beganUptime
                self.artifacts.append(metadata)
            }
            return event
        }
        recordPresentationEvent("traceStarted")
    }

    private func stopPresentationTrace() {
        if let presentationMouseMonitor { NSEvent.removeMonitor(presentationMouseMonitor) }
        presentationMouseMonitor = nil
        for observer in presentationObservers { NotificationCenter.default.removeObserver(observer) }
        presentationObservers.removeAll()
    }

    private func ownedMouseMetadata(_ event: NSEvent) -> [String: Any]? {
        guard [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type),
              let window = event.window, NSApp.windows.contains(where: { $0 === window }) else { return nil }
        let role = window === statusItem.button?.window ? "statusItem"
            : window === host.control.window ? "popover"
            : window === host.center.window ? "settings"
            : window === host.onboarding.window ? "onboarding" : "otherOwnWindow"
        let insideStatus = statusItem.button.map { button in
            window === button.window && button.bounds.contains(button.convert(event.locationInWindow, from: nil))
        } ?? false
        let hit = window.contentView.flatMap { view in
            view.hitTest(view.convert(event.locationInWindow, from: nil))
        }
        return ["type": event.type.rawValue, "eventNumber": event.eventNumber,
            "timestamp": event.timestamp, "ageSeconds": ProcessInfo.processInfo.systemUptime - event.timestamp,
            "windowNumber": window.windowNumber, "windowRole": role,
            "buttonNumber": event.buttonNumber, "clickCount": event.clickCount,
            "modifierFlags": event.modifierFlags.rawValue, "insideStatusButton": insideStatus,
            "ownHitIdentifier": hit?.identifier?.rawValue ?? "none",
            "ownHitClass": hit.map { String(describing: type(of: $0)) } ?? "none",
            "settingsPage": host.center.selectedPage.rawValue]
    }

    private func recordPresentationEvent(_ event: String) {
        guard presentationTraceCount < 256 else { return }
        presentationTraceCount += 1
        var record: [String: Any] = ["kind": "ownPresentationEvent", "event": event,
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - beganUptime,
            "applicationActive": NSApp.isActive,
            "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier as Any? ?? NSNull(),
            "processPID": ProcessInfo.processInfo.processIdentifier,
            "settingsVisible": host.center.window.isVisible, "settingsKey": host.center.window.isKeyWindow,
            "popoverShown": host.control.isShown, "popoverWindowVisible": host.control.window?.isVisible ?? false,
            "popoverWindowKey": host.control.window?.isKeyWindow ?? false,
            "popoverWindowNumber": host.control.window?.windowNumber as Any? ?? NSNull()]
        if let current = NSApp.currentEvent, let metadata = ownedMouseMetadata(current) {
            record["currentOwnedMouseEvent"] = metadata
        }
        if event == "popover.willClose" {
            // Raw symbols remain in this explicitly invoked review's private
            // artifact. Capture synchronously so a direct host/driver close is
            // distinguishable from AppKit's native transient close path.
            if presentationCloseStackCount < 16 {
                presentationCloseStackCount += 1
                record["privateCallStackSymbols"] = Thread.callStackSymbols.prefix(48).map { String($0.prefix(512)) }
            } else {
                record["privateCallStackOmitted"] = "boundedCloseStackLimit"
            }
        }
        artifacts.append(record)
    }

    private func ownedWindowServerBounds(_ window: NSWindow) -> CGRect? {
        guard NSApp.windows.contains(where: { $0 === window }), window.windowNumber > 0,
              let id = CGWindowID(exactly: window.windowNumber), let scalar = UnsafeRawPointer(bitPattern: UInt(id)),
              let ids = CFArrayCreateMutable(kCFAllocatorDefault, 0, nil) else { return nil }
        CFArrayAppendValue(ids, scalar)
        guard let descriptions = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]],
              let description = descriptions.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id
                  && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ProcessInfo.processInfo.processIdentifier
              }), description[kCGWindowIsOnscreen as String] as? Bool == true,
              let value = description[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: value as CFDictionary)
    }

    private func waitForFullOwnedWindow(_ window: NSWindow, context: String) async throws {
        let start = ProcessInfo.processInfo.systemUptime
        var previous: CGRect?
        var previousTarget: NSSize?
        var last: CGRect?
        var samples = 0
        var stableSamples = 0
        var ready = false
        defer { artifacts.append(["kind": "ownedWindowPresentationReadiness", "context": context,
            "windowNumber": window.windowNumber, "seconds": ProcessInfo.processInfo.systemUptime - start,
            "samples": samples, "consecutiveFullStableSamples": stableSamples, "ready": ready,
            "expectedAppKitSize": [window.frame.width, window.frame.height],
            "lastWindowServerBounds": last.map(rect) as Any? ?? NSNull()]) }
        try await wait(timeout: 5) {
            samples += 1
            let target = window.frame.size
            let tolerance = 1 / max(1, window.backingScaleFactor)
            guard window.isVisible, let actual = self.ownedWindowServerBounds(window) else {
                previous = nil; previousTarget = nil; stableSamples = 0; return false
            }
            last = actual
            let full = abs(actual.width - target.width) <= tolerance && abs(actual.height - target.height) <= tolerance
            let stable = previous.map { old in
                abs(old.minX - actual.minX) <= tolerance && abs(old.minY - actual.minY) <= tolerance
                    && abs(old.width - actual.width) <= tolerance && abs(old.height - actual.height) <= tolerance
            } ?? false
            let sameTarget = previousTarget == target
            stableSamples = full ? (stable && sameTarget ? stableSamples + 1 : 1) : 0
            previous = actual; previousTarget = target
            ready = stableSamples >= 2
            return ready
        }
    }

    private func animationCount(_ layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        return (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + animationCount($1) }
    }

    private func blockedJSON(_ name: String, body: () async throws -> Void) async throws {
        let allowed = ["rift-configuration.json", "app-presentation-settings.json", "lifecycle-settings.json", "capture-entry-settings.json", "arrival-motion-settings.json"]
        try validateEnvironment()
        guard allowed.contains(name) else { throw Failure.unsafeEnvironment }
        let url = environment.root.appendingPathComponent(name)
        let token = UUID().uuidString.lowercased()
        let held = directory.appendingPathComponent("held-" + token + "-" + name)
        let marker = url.appendingPathComponent("review-injection-" + token)
        let manager = FileManager.default
        var original: Data?
        if manager.fileExists(atPath: url.path) {
            guard (try manager.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeRegular,
                  url.resolvingSymlinksInPath() == url else { throw Failure.unsafeEnvironment }
            original = try Data(contentsOf: url)
            let saved = directory.appendingPathComponent("before-fault-" + token + "-" + name)
            try manager.copyItem(at: url, to: saved)
            artifacts.append(["kind": "preFaultOriginal", "file": saved.lastPathComponent, "sha256": digest(original!)])
            try manager.moveItem(at: url, to: held)
        }
        var failure: Error?
        do {
            try manager.createDirectory(at: url, withIntermediateDirectories: false)
            try Data(token.utf8).write(to: marker, options: .withoutOverwriting)
            try await body()
        } catch { failure = error }
        do {
            try require(try manager.contentsOfDirectory(atPath: url.path) == [marker.lastPathComponent]
                        && Data(contentsOf: marker) == Data(token.utf8), "injectedDirectoryChanged")
            try manager.removeItem(at: marker)
            try manager.removeItem(at: url)
            if let original {
                try manager.moveItem(at: held, to: url)
                try require(try Data(contentsOf: url) == original, "originalJSONNotRestored")
            }
            artifacts.append(["kind": "faultRestoration", "file": name, "originalExisted": original != nil,
                              "originalBytesRestored": true])
        } catch {
            restorationFailures.append(name)
            throw Failure.restoreFailed
        }
        if let failure { throw failure }
    }

    @discardableResult private func createFixture(_ suffix: String, width: Int = 160, height: Int = 100) throws -> String {
        try validateEnvironment()
        let name = "settings-review-synthetic-" + UUID().uuidString.lowercased() + "-" + suffix + ".png"
        let file = environment.source.appendingPathComponent(name)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.encoding }
        context.setFillColor(CGColor(red: 0.12, green: 0.44, blue: 0.35, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.94, alpha: 1)); context.fill(CGRect(x: 15, y: 20, width: 112, height: 12))
        // Each generated fixture has distinct pixels as well as a distinct
        // source filename, so a later import cannot match an earlier image.
        for (index, byte) in SHA256.hash(data: Data(name.utf8)).enumerated() {
            context.setFillColor(CGColor(gray: CGFloat(byte) / 255, alpha: 1))
            context.fill(CGRect(x: 15 + index * 4, y: 60, width: 4, height: 12))
        }
        guard let image = context.makeImage() else { throw Failure.encoding }
        let data = try png(image)
        try writeReviewScreenshot(data, to: file)
        artifacts.append(["kind": "syntheticCollectorInput", "file": "fixture-source/" + name,
                          "sha256": digest(data), "pixels": [width, height], "systemScreenshot": false,
                          "testMetadataExplicitlyAdded": true])
        return digest(data)
    }

    private func writeReviewScreenshot(_ data: Data, to file: URL) throws {
        try data.write(to: file, options: .withoutOverwriting)
        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = marker.withUnsafeBytes { setxattr(file.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0) }
        try require(result == 0, "fixtureMetadataWriteFailed")
    }

    private func capture(_ name: String, window: NSWindow?, verifyPresentation: Bool = true) async {
        guard let window, window.isVisible, NSApp.windows.contains(where: { $0 === window }),
              window.windowNumber > 0, let firstScreen = NSScreen.screens.first,
              let id = CGWindowID(exactly: window.windowNumber), let scalar = UnsafeRawPointer(bitPattern: UInt(id)),
              let ids = CFArrayCreateMutable(kCFAllocatorDefault, 0, nil) else {
            frames.append(["name": name, "status": "NOT_RUN", "reason": "ownedWindowUnavailable"]); return
        }
        window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        var presentationFailure: String?
        if window === host.control.window {
            if verifyPresentation {
                do { try await waitForFullOwnedWindow(window, context: "capture:" + name) }
                catch { presentationFailure = "ownedWindowPresentationDidNotSettle" }
            } else { presentationFailure = "ownedWindowPresentationDidNotSettle" }
        } else { await settle(100) }
        CFArrayAppendValue(ids, scalar)
        let frame = window.frame
        let appKitQuartz = CGRect(x: frame.minX, y: firstScreen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        guard let descriptions = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]],
              let description = descriptions.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id
                  && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ProcessInfo.processInfo.processIdentifier
              }), let bounds = description[kCGWindowBounds as String] as? [String: Any],
              let quartz = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              quartz.width > 0, quartz.height > 0 else {
            frames.append(["name": name, "status": "NOT_RUN", "reason": "ownedWindowServerIdentityUnavailable"]); return
        }
        let visibleArea = NSScreen.screens.reduce(CGFloat.zero) { total, screen in
            let visible = screen.visibleFrame
            let rect = CGRect(x: visible.minX, y: firstScreen.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
            let intersection = quartz.intersection(rect)
            return total + (intersection.isNull ? 0 : intersection.width * intersection.height)
        }
        var result: [String: Any] = ["name": name, "windowNumber": window.windowNumber,
            "processPID": ProcessInfo.processInfo.processIdentifier, "windowFrame": rect(frame),
            "contentBounds": rect(window.contentView?.bounds ?? .zero),
            "contentRect": rect(window.contentRect(forFrameRect: frame)),
            "screenVisibleFrame": rect(window.screen?.visibleFrame ?? .zero),
            "screenFrame": rect(window.screen?.frame ?? .zero), "backingScale": window.backingScaleFactor,
            "quartzCaptureRect": rect(quartz), "windowServerBounds": rect(quartz), "appKitQuartzFrame": rect(appKitQuartz),
            "windowServerOnscreen": description[kCGWindowIsOnscreen as String] as? Bool ?? false,
            "windowServerVisibleAreaFraction": min(1, visibleArea / (quartz.width * quartz.height)),
            "captureRectMode": "CGRect.null: automatic bounds of exactly the requested owned window",
            "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier as Any? ?? NSNull(),
            "keyWindowNumber": NSApp.keyWindow?.windowNumber as Any? ?? NSNull(),
            "appearance": window.effectiveAppearance.name.rawValue,
            "method": "WindowServer CGImage(windowArray), exactly one NSApp-owned window; no desktop/display capture"]
        if window === host.control.window { result["presentationStable"] = presentationFailure == nil }
        guard let image = CGImage(windowListFromArrayScreenBounds: .null, windowArray: ids,
                                  imageOption: [.boundsIgnoreFraming, .bestResolution]) else {
            result["status"] = "NOT_RUN"; result["reason"] = "ownedWindowCaptureUnavailable"; frames.append(result); return
        }
        do {
            let data = try png(image)
            let file = directory.appendingPathComponent(name + ".png")
            try data.write(to: file, options: .withoutOverwriting)
            result["status"] = "RECORDED_NATIVE_WINDOWSERVER"; result["file"] = file.lastPathComponent
            result["sha256"] = digest(data); result["bytes"] = data.count; result["pixels"] = [image.width, image.height]
            if let presentationFailure { result["status"] = "FAIL"; result["reason"] = presentationFailure }
        } catch { result["status"] = "FAIL"; result["reason"] = code(error) }
        frames.append(result)
    }

    private func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw Failure.encoding }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encoding }
        return data as Data
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func rect(_ value: CGRect) -> [Double] { [value.origin.x, value.origin.y, value.width, value.height].map(Double.init) }
    private func saveReport(completed: Bool) throws {
        let executable = Bundle.main.executableURL.flatMap { try? Data(contentsOf: $0) }
        let hasFailure = cases.contains { $0["status"] as? String == "FAIL" }
            || frames.contains { $0["status"] as? String == "FAIL" } || !restorationFailures.isEmpty
        let incomplete = cases.contains { $0["status"] as? String == "NOT_RUN" }
            || frames.contains { $0["status"] as? String == "NOT_RUN" }
        let status = !completed ? "RUNNING" : hasFailure ? "FAIL"
            : incomplete ? "PARTIAL_NATIVE_REVIEW" : "PASS_SCOPED_NATIVE_REVIEW"
        let report: [String: Any] = ["schema": 1, "reviewID": environment.identifier.uuidString.lowercased(),
            "status": status,
            "completed": completed, "beganUTC": ISO8601DateFormatter().string(from: began),
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - beganUptime,
            "processPID": ProcessInfo.processInfo.processIdentifier,
            "frontmostPIDAtStart": beganPID as Any? ?? NSNull(),
            "executableSHA256": executable.map(digest) as Any? ?? NSNull(),
            "reviewMode": CommandLine.arguments.contains("--desktop-forms-review") ? "desktopForms" : historyStyleReview ? "historyStyle" : "settings",
            "inputMethod": historyStyleReview ? "PROGRAMMATIC_NATIVE_CONTROLS: NSControl actions, native selection/accessibility action and NSTextView insertion; not CGEvent or hardware" : "Native NSControl actions and NSTextView insertion; no physical pointer or OS IME claim",
            "scope": "UUID-isolated real host/model/SQLite/collector and AppKit windows in the same App binary",
            "notRun": ["realChatGPTAttachment", "physicalPointer", "OSInputMethod", "VoiceOver", "realLoginRegistration", "realTCCPrompt", "multiDisplayHotplug"],
            "productionDataAccess": false, "browserAccess": false, "networkUpload": false,
            "cases": cases, "frames": frames, "artifacts": artifacts, "restorationFailures": restorationFailures]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("report.json"), options: .atomic)
    }
}

extension SettingsReviewDriver {
    private func chooseDesktopForm(_ form: RiftDesktopForm) async throws {
        host.show(page: .display)
        guard form.isAvailable, let index = RiftDesktopForm.allCases.firstIndex(of: form) else {
            throw Failure.controlUnavailable(form.rawValue)
        }
        try select("settings.center.desktopForm", index: index)
        try await wait { self.host.snapshot.state.owner.settings.configuration.desktopForm == form }
        await onRefresh()
        await settle(220)
    }

    /// Optional image fixtures are supplied outside the bundle, in this review UUID only.
    /// Capturing our own backdrop and floating windows works on a 1× guest without granting
    /// screen recording or including other applications. Input delivery is tested separately.
    private func referenceTrayRun(inputs: URL) async -> URL? {
        guard let panel = desktopPanel, let screen = panel.preferredScreen ?? NSScreen.main else { return nil }
        func input(_ name: String) throws -> Data {
            let url = inputs.appendingPathComponent(name)
            guard url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path else {
                throw Failure.unsafeEnvironment
            }
            let meta = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard meta.isRegularFile == true, let size = meta.fileSize, (1...4_194_304).contains(size) else {
                throw Failure.unsafeEnvironment
            }
            return try Data(contentsOf: url)
        }
        await runCase("reference-inputs-and-tray-states") {
            try self.require(self.initialAssetIDs.isEmpty, "requiresFreshIsolatedReviewUUID")
            let settings = self.host.snapshot.state.owner.settings
            try self.require(settings.configuration.desktopForm == .tray && settings.entryEnabled, "trayEntryNotEnabled")
            try self.require(settings.configuration.visibleCountPreference == 3, "expectedThreeThumbnailPreference")
            struct Scene: Decodable { let x, y, width, height: Double }
            let scene = try JSONDecoder().decode(Scene.self, from: input("scene.json"))
            let relative = CGRect(x: scene.x, y: scene.y, width: scene.width, height: scene.height)
            try self.require(relative.width > 0 && relative.height > 0 && relative.width <= 0.4 &&
                             CGRect(x: 0, y: 0, width: 1, height: 1).contains(relative), "invalidReviewBackdrop")
            guard let wallpaper = NSImage(data: try input("wallpaper.png")) else { throw Failure.encoding }
            let viewport = screen.frame
            let area = CGRect(x: viewport.minX + relative.minX * viewport.width,
                              y: viewport.maxY - relative.maxY * viewport.height,
                              width: relative.width * viewport.width, height: relative.height * viewport.height)
            let backing = NSPanel(contentRect: area, styleMask: [.nonactivatingPanel, .borderless],
                                  backing: .buffered, defer: false)
            backing.isReleasedWhenClosed = false
            backing.ignoresMouseEvents = true
            backing.hasShadow = false
            backing.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 2)
            let imageView = NSImageView(image: wallpaper)
            imageView.imageScaling = .scaleAxesIndependently
            backing.contentView = imageView
            backing.orderFrontRegardless()
            defer { backing.close() }
            self.host.onboarding.closeForTeardown()
            @MainActor func captureState(_ name: String, expanded: Bool, lines: Int, expectedIDs: [UUID]) async throws {
                await self.settle(500)
                let rows = panel.diagnosticSnapshot.rows
                try self.require(rows.map(\.assetID) == expectedIDs, "incorrectReviewUUIDs-" + name)
                let key = try self.checkReferenceTray(name, rows: rows, lines: lines, expanded: expanded)
                try self.desktopCapture(name, screen: screen, rows: rows, backdrop: backing, referenceKey: key)
            }
            var identities: [UUID] = []
            for count in 0...10 {
                if count > 0 {
                    let bytes = try input("card-\(count).png")
                    let source = self.environment.source.appendingPathComponent("reference-card-\(count).png")
                    try self.writeReviewScreenshot(bytes, to: source)
                    let hash = self.digest(bytes)
                    try await self.wait(timeout: 10) { try await self.store.assets(includeUsed: true).contains { $0.image.sha256 == hash } }
                    await self.onRefresh()
                }
                guard [0, 1, 2, 3, 4, 10].contains(count) else { continue }
                let assets = try await self.store.assets(includeUsed: true)
                let current = assets.map(\.id)
                try self.require(current.count == count && Set(current).count == count && current.starts(with: identities) &&
                                 assets.allSatisfy { $0.activeOperationID == nil }, "referenceIdentityChanged")
                identities = current
                let page = Array(current.suffix(3))
                let lines = count < 2 ? 1 : 2
                if count == 1 {
                    // Keep the empty menu open across the actual source-file import.
                    try await captureState("reference-1-arrived-open", expanded: true, lines: 2, expectedIDs: page)
                    panel.setTrayExpanded(false)
                }
                try await self.wait { !panel.diagnosticSnapshot.isTransitioning }
                panel.showLatest()
                let label = "reference-" + String(count)
                try await captureState(label + "-closed", expanded: false, lines: lines, expectedIDs: page)
                panel.setTrayExpanded(true)
                let upper = count < 2 ? [] : Array(page.suffix(2))
                try await captureState(label + "-open", expanded: true, lines: lines, expectedIDs: upper)
                if count > 0 {
                    panel.setTrayExpanded(false)
                    if count == 1 || count == 3 {
                        try await captureState(label + "-reclosed", expanded: false, lines: lines, expectedIDs: page)
                    }
                }
                let stored = try await self.store.assets(includeUsed: true)
                try self.require(stored.map(\.id) == current &&
                    stored.allSatisfy { $0.visibility == .visible && $0.activeOperationID == nil }, "menuChangedReferenceQueue-" + label)
            }
            self.artifacts.append(["kind": "referenceFixtureScope", "menu": "programmatic AppKit",
                                   "backdrop": "provided fixture in review UUID", "assets": identities.count])
        }
        try? saveReport(completed: true)
        return directory.appendingPathComponent("report.json")
    }

    private func trayKeyHasSettled(_ key: NSButton) -> Bool {
        guard let layer = key.layer else { return false }
        let actual = layer.presentation()?.frame ?? layer.frame
        return abs(layer.frame.midX - actual.midX) <= 1 && abs(layer.frame.midY - actual.midY) <= 1 &&
            abs(layer.frame.width - actual.width) <= 1 && abs(layer.frame.height - actual.height) <= 1
    }

    private func isDesktopPresentationWindow(_ window: NSWindow) -> Bool {
        window.isVisible && (window.level == .floating || window.level.rawValue == NSWindow.Level.floating.rawValue - 1)
    }

    private func checkReferenceTray(_ name: String, rows: [RiftDiagnosticRow], lines: Int,
                                    expanded: Bool) throws -> CGRect {
        func buttons(in view: NSView) -> [NSButton] {
            guard !view.isHidden else { return [] }
            if let button = view as? NSButton, button.toolTip != nil { return [button] }
            return view.subviews.flatMap { buttons(in: $0) }
        }
        let controls = NSApp.windows.filter(isDesktopPresentationWindow)
            .compactMap(\.contentView).flatMap { buttons(in: $0) }
        let keys = controls.sorted { $0.frame.minX < $1.frame.minX }
        let names = keys.compactMap(\.toolTip)
        artifacts.append(["kind": "observedReferenceControls", "name": name, "labels": names,
                          "windowNumbers": keys.map { $0.window?.windowNumber ?? -1 },
                          "activeLayerAnimations": keys.map { $0.layer?.animationKeys() ?? [] }])
        guard let window = keys.first?.window, let quartz = ownedWindowServerBounds(window),
              keys.allSatisfy({ $0.window === window }), names.count == (expanded ? 4 : 1) else {
            throw Failure.assertion("trayControlsNotOnScreen-" + name)
        }
        // AppKit may keep native focus/highlight animations alive. Only the actual
        // position and size of these keys need to settle before reading their geometry.
        try require(keys.allSatisfy(trayKeyHasSettled), "reviewKeyStillMoving-" + name)
        let keyFrames = keys.map { window.convertToScreen($0.convert($0.bounds, to: nil)) }
        try require(keys.compactMap { $0.accessibilityLabel() } == names, "wrongReviewAccessibilityLabels-" + name)
        if expanded {
            let roles = ["常用截图 1，", "常用截图 2，", "常用截图 3，", "默认截图，"]
            try require(zip(names, roles).allSatisfy { $0.hasPrefix($1) },
                        "wrongReviewActionRoles-" + name)
            try require(zip(keyFrames, keyFrames.dropFirst()).allSatisfy { $0.maxX <= $1.minX && $0.minY == $1.minY },
                        "overlappingReviewMenu-" + name)
            let strip = keyFrames.reduce(CGRect.null) { $0.union($1) }
            try require(strip.width > window.frame.width * 0.9 && rows.allSatisfy { $0.imageInputFrame.minY >= strip.maxY },
                        "reviewMenuSharesRow-" + name)
            try require(zip(rows, rows.dropFirst()).allSatisfy { first, next in
                first.frame.midX < next.frame.midX && abs(first.frame.midY - next.frame.midY) <= 1
            }, "reviewUpperRowOutOfOrder-" + name)
        } else {
            try require(names == ["展开截图方式"], "trayCameraNotRestored-" + name)
        }
        let designRatio = (lines == 2 ? 212.0 : 115.0) / 246.0
        try require(abs(quartz.height - quartz.width * designRatio) <= 2, "reviewRowCount-" + name)
        for row in rows {
            guard let window = NSApp.window(withWindowNumber: row.windowNumber),
                  ownedWindowServerBounds(window) != nil else { throw Failure.assertion("reviewRowNotOnScreen-" + name) }
        }
        artifacts.append(["kind": "referenceTrayControls", "name": name, "surface": rect(quartz),
                          "windowNumber": window.windowNumber, "controlLabels": names,
                          "keyScreenFrames": keyFrames.map(rect), "rowIDs": rows.map { $0.assetID.uuidString },
                          "geometryRows": lines])
        return keyFrames[keyFrames.count - 1]
    }

    private func desktopRun() async -> URL? {
        guard let panel = desktopPanel, let screen = NSScreen.main else { return nil }
        host.onboarding.closeForTeardown()
        await runCase("isolated-review-controls") {
            try self.require(self.initialAssetIDs.isEmpty, "requiresFreshIsolatedReviewUUID")
            self.host.show(page: .general)
            try await self.setToggle("settings.center.paused", true)
            self.host.show(page: .display)
            guard let control = try self.control("settings.center.desktopForm") as? NSSegmentedControl else {
                throw Failure.controlUnavailable("desktopForm")
            }
            try self.require(control.segmentCount == 3 && !control.isEnabled(forSegment: 1), "formAvailability")
            await self.capture("settings-form-selection", window: self.host.center.window)
        }
        guard cases.last?["status"] as? String == "PASS" else { return directory.appendingPathComponent("report.json") }
        let variants = RiftDesktopForm.allCases.filter(\.isAvailable)
        var expected = Set<UUID>()
        for count in 0...10 {
            if count > 0 {
                let dims = [(720,420),(360,720),(80,960),(900,80)]
                let size = dims[(count - 1) % dims.count]
                await runCase("collect-fixture-" + String(count)) {
                    let hash = try self.createFixture("form-" + String(count), width:size.0, height:size.1)
                    try await self.wait(timeout: 10) { try await self.store.assets(includeUsed:true).contains { $0.image.sha256 == hash } }
                    let all = try await self.store.assets(includeUsed:true)
                    expected = Set(all.map(\.id)); try self.require(expected.count == count, "fixtureCount")
                    await self.onRefresh()
                }
            }
            guard [0,1,2,3,4,5,10].contains(count) else { continue }
            for form in variants {
                let name = form.rawValue + "-" + String(count)
                await runCase(name) {
                    try await self.chooseDesktopForm(form)
                    let snapshot = panel.diagnosticSnapshot
                    let seen = Set(snapshot.rows.map(\.assetID))
                    try self.require(seen.isSubset(of: expected) && seen.count == snapshot.rows.count, "visibleForeignOrDuplicateUUID")
                    try self.require(count == 0 ? seen.isEmpty : !seen.isEmpty, "unexpectedEmptyRows")
                    let assets = try await self.store.assets(includeUsed:true)
                    try self.require(Set(assets.map(\.id)) == expected && assets.allSatisfy { $0.activeOperationID == nil }, "queueIdentityChanged")
                    try self.desktopCapture(name, screen: screen, rows: snapshot.rows)
                }
            }
        }
        for style in [SettingsAppearanceChoice.light, .dark] {
            for placement in [RiftPlacement.leftMiddle,.rightMiddle] {
                await runCase(style.rawValue + "-" + placement.rawValue) {
                    try await self.appearance(style)
                    self.host.show(page: .display)
                    guard let index = RiftPlacement.allCases.firstIndex(of: placement) else { throw Failure.controlUnavailable("placement") }
                    try self.select("settings.center.placement", index: index)
                    try await self.wait { self.host.snapshot.state.owner.settings.configuration.placement == placement }
                    for form in variants {
                        try await self.chooseDesktopForm(form)
                        try self.desktopCapture([style.rawValue,placement.rawValue,form.rawValue].joined(separator:"-"),
                                                screen: screen, rows: panel.diagnosticSnapshot.rows)
                    }
                }
            }
        }
        await runCase("tray-native-wheel") {
            try await self.chooseDesktopForm(.tray)
            panel.showOldest()
            await self.settle(350)
            let before = panel.diagnosticSnapshot.rows
            guard let row = before.first, let display=NSScreen.screens.first else { throw Failure.assertion("wheelTargetMissing") }
            let whereAt = CGPoint(x:row.imageInputFrame.midX,y:display.frame.maxY-row.imageInputFrame.midY)
            guard let wheel=CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:-80,wheel2:0,wheel3:0) else { throw Failure.assertion("wheelUnavailable") }
            guard let old = CGEvent(source:nil)?.location else {throw Failure.assertion("pointerUnavailable")}
            defer { CGWarpMouseCursorPosition(old) }
            CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:whereAt,mouseButton:.left)?.post(tap:.cghidEventTap)
            await self.settle(150)
            let hitWindow = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
            try self.require(NSApp.windows.contains { $0.windowNumber == hitWindow }, "wheelWindowNotOwned")
            var delivered = [Double]()
            let monitor = NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { event in
                delivered.append(event.scrollingDeltaY); return event
            }
            defer {
                if let monitor { NSEvent.removeMonitor(monitor) }
                self.artifacts.append(["kind":"trayWheel","deltas":delivered,"before":before.map(\.ordinal),
                                       "after":panel.diagnosticSnapshot.rows.map(\.ordinal)])
            }
            wheel.location=whereAt; wheel.post(tap:.cghidEventTap)
            try await self.wait { panel.diagnosticSnapshot.rows.map(\.assetID) != before.map(\.assetID) }
            try self.desktopCapture("tray-after-wheel",screen:screen,rows:panel.diagnosticSnapshot.rows)
        }
        await runCase("tray-owned-button-and-escape") {
            try await self.chooseDesktopForm(.tray)
            panel.showLatest()
            await self.settle(260)
            func buttons(_ view:NSView)->[NSButton] {
                guard !view.isHidden else {return []}
                return (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
            }
            let visible = NSApp.windows.filter(isDesktopPresentationWindow).compactMap(\.contentView).flatMap(buttons)
            guard let camera = visible.first(where: {$0.toolTip=="展开截图方式"}), let tray=camera.window,
                  let contents=tray.contentView else {throw Failure.assertion("visibleTrayCameraUnavailable")}
            guard let display = NSScreen.screens.first, let original = CGEvent(source:nil)?.location else {
                throw Failure.assertion("pointerUnavailable")
            }
            defer { CGWarpMouseCursorPosition(original) }
            // Snapshot the settled controls. The default key reuses the camera
            // object, so its mere visibility cannot prove either end state.
            func stableKeys() -> [NSButton] {
                let visible = buttons(contents).filter { $0.toolTip != nil }
                return visible.allSatisfy(self.trayKeyHasSettled) ? visible : []
            }
            for cycle in 1...2 {
                let frame = tray.convertToScreen(camera.convert(camera.bounds, to:nil))
                let point = CGPoint(x:frame.midX,y:frame.midY)
                let quartz = CGPoint(x:point.x,y:display.frame.maxY-point.y)
                CGWarpMouseCursorPosition(quartz)
                await self.settle(120)
                try self.require(NSWindow.windowNumber(at:point,belowWindowWithWindowNumber:0)==tray.windowNumber,
                                 "trayCameraObscured")
                for type in [CGEventType.leftMouseDown,.leftMouseUp] {
                    let event = CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:quartz,mouseButton:.left)
                    event?.setIntegerValueField(.mouseEventClickState,value:1)
                    event?.post(tap:.cghidEventTap)
                    await self.settle(50)
                }
                try await self.wait { stableKeys().count == 4 }
                let arranged = stableKeys().sorted { $0.frame.minX < $1.frame.minX }
                try self.require(Set(arranged.map { $0.frame.midY }).count == 1 &&
                                 zip(arranged, arranged.dropFirst()).allSatisfy { $0.frame.maxX <= $1.frame.minX },
                                 "menuNotSingleRow")
                try self.desktopCapture((cycle == 1 ? "tray-expanded-menu" : "tray-expanded-again"),screen:screen,rows:panel.diagnosticSnapshot.rows)
                guard let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                         windowNumber:tray.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)
                else {throw Failure.assertion("escapeUnavailable")}
                NSApp.postEvent(event,atStart:false)
                try await self.wait {
                    let keys = stableKeys()
                    return keys.count == 1 && keys.first === camera && camera.toolTip == "展开截图方式"
                }
                try self.desktopCapture((cycle == 1 ? "tray-closed-menu" : "tray-closed-again"),screen:screen,rows:panel.diagnosticSnapshot.rows)
            }
        }
        await runCase("violet-restart-and-material-switch") {
            try await self.chooseDesktopForm(.tray)
            try self.select("settings.center.trayTheme",index:1)
            try await self.wait { self.host.snapshot.state.owner.settings.configuration.trayTheme == .violetGlass }
            await self.settle(180)
            try self.desktopCapture("tray-violet",screen:screen,rows:panel.diagnosticSnapshot.rows)
            panel.setTrayExpanded(true)
            try await self.chooseDesktopForm(.microSlit)
            try self.require(panel.diagnosticSnapshot.rows.allSatisfy { expected.contains($0.assetID) }, "inFlightSwitchChangedUUID")
        }
        await runCase("physical-connected-displays") {
            for (index,display) in NSScreen.screens.enumerated() {
                self.host.show(page:.display)
                guard let popup = try self.control("settings.center.display") as? NSPopUpButton,
                      let id = display.deviceDescription[.init("NSScreenNumber")] as? NSNumber,
                      let item = popup.itemArray.firstIndex(where:{ ($0.representedObject as? NSNumber)?.uint32Value == id.uint32Value })
                else { throw Failure.assertion("physicalDisplayMenuMissing") }
                try self.select("settings.center.display",index:item)
                try await self.wait { panel.preferredScreen?.frame == display.frame }
                for form in variants {
                    try await self.chooseDesktopForm(form)
                    let rows = panel.diagnosticSnapshot.rows
                    try self.require(!rows.isEmpty && rows.allSatisfy{display.frame.intersects($0.frame)}, "wrongDisplay")
                    try self.desktopCapture("display-\(index)-"+form.rawValue,screen:display,rows:rows)
                }
            }
        }
        await runCase("native-high-contrast-appearance-override") {
            let saved = NSApp.appearance
            defer {NSApp.appearance = saved}
            for (index, look) in [NSAppearance.Name.accessibilityHighContrastAqua,.accessibilityHighContrastDarkAqua].enumerated() {
                NSApp.appearance = NSAppearance(named:look)
                for form in variants {
                    try await self.chooseDesktopForm(form)
                    try self.desktopCapture("native-contrast-\(index)-"+form.rawValue,screen:panel.preferredScreen ?? screen,rows:panel.diagnosticSnapshot.rows)
                }
            }
            self.artifacts.append(["kind":"contrastOverride","scope":"NSApp.appearance only",
                                   "systemIncreaseContrast":NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast])
        }
        await runCase("tray-restart-baseline") {
            try await self.chooseDesktopForm(.tray)
            let rows = try await self.store.assets(includeUsed:true)
            let digest = try self.assetRowsDigest(rows)
            let identity: [String:Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "digest":digest,
                "executable":self.digest(try Data(contentsOf: Bundle.main.executableURL!))]
            let file = self.directory.appendingPathComponent("restart-baseline.json")
            try JSONSerialization.data(withJSONObject: identity).write(to:file)
        }
        try? saveReport(completed:true)
        return directory.appendingPathComponent("report.json")
    }

    private func desktopCapture(_ name:String, screen:NSScreen, rows:[RiftDiagnosticRow],
                                backdrop:NSWindow? = nil, referenceKey: CGRect? = nil) throws {
        // Include only this process's visible floating windows. No user windows or desktop pixels.
        let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID) as? [[String:Any]] ?? []
        let ours = Set(NSApp.windows.filter { isDesktopPresentationWindow($0) || ($0.isVisible && $0 === backdrop) }.map(\.windowNumber))
        let entries = ordered.filter {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == getpid() &&
            ours.contains(($0[kCGWindowNumber as String] as? NSNumber)?.intValue ?? -1)
        }
        guard !entries.isEmpty else {
            try require(rows.isEmpty,"visibleRowsMissingInWindowServer")
            frames.append(["name":name,"status":"EMPTY","rowCount":0]); return
        }
        guard let ids = CFArrayCreateMutable(nil,0,nil) else {throw Failure.encoding}
        for e in entries {
            let id = (e[kCGWindowNumber as String] as! NSNumber).uintValue
            CFArrayAppendValue(ids,UnsafeRawPointer(bitPattern:id))
        }
        guard let image = CGImage(windowListFromArrayScreenBounds:.null,windowArray:ids,
                                  imageOption:[.boundsIgnoreFraming,.bestResolution]) else { throw Failure.assertion("ownedWindowCaptureFailed") }
        let quartzBounds = entries.compactMap { e -> CGRect? in
            guard let raw = e[kCGWindowBounds as String] as? [String:Any] else { return nil }
            return CGRect(dictionaryRepresentation:raw as CFDictionary)
        }.reduce(CGRect.null){$0.union($1)}
        let bytes = try png(image)
        try bytes.write(to:directory.appendingPathComponent(name+".png"),options:.withoutOverwriting)
        frames.append(["name":name,"status":"RECORDED_NATIVE_WINDOWSERVER","method":"owned floating windows only",
                       "pixels":[image.width,image.height],"quartzBounds":rect(quartzBounds),"uptime":ProcessInfo.processInfo.systemUptime,"screenCount":NSScreen.screens.count,
                       "backingScale":screen.backingScaleFactor,"sha256":digest(bytes),
                       "rowIDs":rows.map { $0.assetID.uuidString },"frames":rows.map { rect($0.frame) },
                       "inputFrames":rows.map { rect($0.imageInputFrame) }])
        if let key = referenceKey, let backdrop {
            try verifyRenderedKey(name, key: key, sample: image, sampleBounds: quartzBounds, backdrop: backdrop)
        }
    }

    /// A sleeping or locked WindowServer can return a transparent image with a valid
    /// window number. Verify the saved key pixels differ from the underlying fixture.
    private func verifyRenderedKey(_ name: String, key: CGRect, sample: CGImage,
                                   sampleBounds: CGRect, backdrop: NSWindow) throws {
        guard let primary = NSScreen.screens.first, let ids = CFArrayCreateMutable(nil, 0, nil) else {
            throw Failure.assertion("referenceDisplayUnavailable")
        }
        let box = key.insetBy(dx: key.width * 0.15, dy: key.height * 0.15)
        let quartz = CGRect(x: box.minX, y: primary.frame.maxY - box.maxY, width: box.width, height: box.height)
        let sx = CGFloat(sample.width) / sampleBounds.width, sy = CGFloat(sample.height) / sampleBounds.height
        let region = CGRect(x: (quartz.minX - sampleBounds.minX) * sx, y: (quartz.minY - sampleBounds.minY) * sy,
                            width: quartz.width * sx, height: quartz.height * sy)
        CFArrayAppendValue(ids, UnsafeRawPointer(bitPattern: backdrop.windowNumber))
        guard let foreground = sample.cropping(to: region),
              let background = CGImage(windowListFromArrayScreenBounds: quartz, windowArray: ids,
                                       imageOption: [.boundsIgnoreFraming, .bestResolution]) else {
            throw Failure.assertion("referencePixelsUnavailable-" + name)
        }
        func grid(_ source: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let context = CGContext(data: buffer.baseAddress, width: 16, height: 16,
                                              bitsPerComponent: 8, bytesPerRow: 16 * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.encoding }
                context.draw(source, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            }
            return bytes
        }
        let actual = try grid(foreground), under = try grid(background)
        var opaque = 0, difference = 0
        for index in stride(from: 0, to: actual.count, by: 4) where actual[index + 3] > 245 && under[index + 3] > 245 {
            opaque += 1
            for channel in 0..<3 { difference += abs(Int(actual[index + channel]) - Int(under[index + channel])) }
        }
        let delta = Double(difference) / Double(max(1, 3 * opaque))
        artifacts.append(["kind": "referenceKeyPixels", "name": name, "opaquePairs": opaque, "meanRGBDelta": delta])
        try require(opaque >= 240 && delta > 5, "missingRenderedKeyPixels-" + name)
    }

    private func desktopRestart(_ output: URL) async -> URL? {
        do {
            let parent = output.deletingLastPathComponent().deletingLastPathComponent()
            let urls = try FileManager.default.contentsOfDirectory(at:parent,includingPropertiesForKeys:nil)
            let baseline = urls.filter { $0.lastPathComponent.hasPrefix("run-") }.map { $0.appendingPathComponent("restart-baseline.json") }
            guard baseline.count == 1, let data = try JSONSerialization.jsonObject(with:Data(contentsOf:baseline[0])) as? [String:Any] else {throw Failure.assertion("missingBaseline")}
            let current = try await store.assets(includeUsed:true)
            try require(data["pid"] as? Int != Int(getpid()),"sameProcess")
            try require(data["executable"] as? String == digest(try Data(contentsOf:Bundle.main.executableURL!)), "differentExecutable")
            try require(try assetRowsDigest(current) == data["digest"] as? String, "assetRecordsChanged")
            try require(host.snapshot.state.owner.settings.configuration.desktopForm == .tray, "preferenceLostOnRestart")
            try JSONSerialization.data(withJSONObject:["status":"PASS","form":"tray","assetCount":current.count,"pid":getpid()]).write(to:output)
        } catch {
            try? JSONSerialization.data(withJSONObject:["status":"FAIL","reason":code(error)]).write(to:output)
        }
        return output
    }
}
