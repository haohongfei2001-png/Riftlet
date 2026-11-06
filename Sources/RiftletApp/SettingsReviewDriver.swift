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
    private let environment: SettingsReviewEnvironment
    private let host: SettingsProductHost
    private let store: QueueStore
    private let statusItem: NSStatusItem
    private let onRefresh: @MainActor () async -> Void
    private let onHistory: @MainActor () -> Void
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
         onHistory: @escaping @MainActor () -> Void) {
        self.environment = environment; self.host = host; self.store = store
        self.statusItem = statusItem; self.onRefresh = onRefresh; self.onHistory = onHistory
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

        await runCase("environment-and-default-window") {
            try await self.wait { self.host.snapshot.capabilities.initialized }
            try self.validateEnvironment()
            self.host.onboarding.closeForTeardown()
            self.host.show(page: .general)
            await self.settle()
            let window = self.host.center.window
            try self.require(window.isVisible, "settingsWindowNotVisible")
            let content = window.contentRect(forFrameRect: window.frame)
            let titleHeight = window.frame.height - content.height
            if let screen = window.screen, screen.visibleFrame.width >= 960, screen.visibleFrame.height >= 684 + titleHeight {
                try self.require(abs(content.width - 960) <= 1 && abs(content.height - 684) <= 1,
                                 "initialContentSizeMismatch")
            }
            try self.require(!self.host.snapshot.capabilities.canCapture, "reviewCaptureCapabilityEnabled")
            try self.require(!self.host.snapshot.login.available, "reviewLoginCapabilityEnabled")
            await self.capture("initial-general", window: window)
        }

        await runCase("real-collector-synthetic-fixture") { try await self.collectFixture() }
        await runCase("six-pages-light-and-dark") { try await self.capturePages() }
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

        recordPresentationEvent("driver.finalCloseIntent")
        host.control.close(); host.onboarding.closeForTeardown()
        host.center.closeForTeardown()
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
        await check("persisted-json-and-loaded-owners") {
            guard prior != nil else { throw Failure.assertion("priorRunRequired") }
            let names = ["rift-configuration.json", "lifecycle-settings.json", "arrival-motion-settings.json",
                         "capture-entry-settings.json", "app-presentation-settings.json"]
            for name in names { documentBytes[name] = try self.reviewDocument(name) }
            let settings = self.host.snapshot.state.owner.settings
            let configuration = try JSONDecoder().decode(RiftConfiguration.self, from: documentBytes["rift-configuration.json"]!)
            try configuration.validate()
            try self.require(configuration == settings.configuration, "restartedConfigurationMismatch")
            let lifecycle = try JSONDecoder().decode(LifecycleSettings.self, from: documentBytes["lifecycle-settings.json"]!)
            try lifecycle.validate()
            try self.require(lifecycle.archiveAfterSeconds.map { $0 / 3600 } == settings.archiveAfterHours, "restartedArchiveMismatch")
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
            return ["allConfigurationFieldsEqual": true, "archiveHours": settings.archiveAfterHours as Any? ?? NSNull(),
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
    private func select(_ id: String, index: Int) throws {
        guard let popup = try control(id) as? NSPopUpButton, popup.itemArray.indices.contains(index),
              let action = popup.action else { throw Failure.controlUnavailable(id) }
        popup.selectItem(at: index)
        NSApp.sendAction(action, to: popup.target, from: popup)
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
        host.show(page: .general)
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
        try await setToggle("settings.center.paused", false)
        try await wait { !self.host.snapshot.state.owner.collectionPaused }
        let fixtureSHA256 = try createFixture("first")
        try await wait(timeout: 10) { try await self.store.assets(includeUsed: true).contains { $0.image.sha256 == fixtureSHA256 } }
        await onRefresh()
        let records = try await store.assets(includeUsed: true)
        try require(records.allSatisfy { $0.activeOperationID == nil }, "collectorCreatedOperation")
        artifacts.append(["kind": "collector", "input": "generatedPNGWithExplicitTestScreenshotMetadata", "assetCount": records.count])
    }

    private func pauseAndHide() async throws {
        try await appearance(.light)
        for (name, paused, hidden) in [("normal", false, false), ("paused", true, false),
                                       ("paused-hidden", true, true), ("hidden", false, true)] {
            try await closeControl(); host.show(page: .general)
            try await setToggle("settings.center.paused", paused)
            try await wait { self.host.snapshot.state.owner.collectionPaused == paused && self.host.snapshot.capabilities.canChangeCollection }
            try await setToggle("settings.center.hidden", hidden)
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
        try await setToggle("settings.center.hidden", false)
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
        try select("settings.center.archive.preset", index: 5)
        let (field, editor) = try edit("settings.center.archive.hours", text: "1.5")
        let originalSelection = NSRange(location: 1, length: 1)
        editor.setSelectedRange(originalSelection)
        let text = editor.string
        await onRefresh(); await settle(50)
        try require(field.currentEditor() === editor && editor.string == text && editor.selectedRange() == originalSelection,
                    "archiveEditorChangedOnRefresh")
        try click("settings.center.archive.save")
        try await wait { self.host.snapshot.state.owner.settings.archiveAfterHours == 1.5 && !self.host.model.hasArchiveDraft }
        try require(try read(LifecycleSettings.self, "lifecycle-settings.json").archiveAfterSeconds == 5_400,
                    "archiveJSONMismatch")
        _ = try edit("settings.center.archive.hours", text: "2.5")
        try click("settings.center.archive.discard")
        try await wait { !self.host.model.hasArchiveDraft }
        host.show(page: .general); host.show(page: .history)
        await onRefresh()
        try require(!host.model.hasArchiveDraft && host.snapshot.state.owner.settings.archiveAfterHours == 1.5,
                    "discardedArchiveReappeared")
        await capture("archive-first-activation-save", window: host.center.window)
    }

    private func configurationEditing() async throws {
        host.show(page: .display)
        try click("settings.center.disclosure.display.details")
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
        let (_, editor) = try edit("settings.center.archive.hours", text: "3.5")
        let selection = NSRange(location: 1, length: 1); editor.setSelectedRange(selection)
        let text = editor.string
        host.center.window.performClose(nil)
        try await wait { self.host.center.window.attachedSheet != nil }
        let sheet = host.center.window.attachedSheet!
        await capture("close-draft-sheet", window: sheet)
        try click("settings.center.close.continue", window: sheet)
        try await wait { self.host.center.window.attachedSheet == nil }
        await settle(60)
        let field = try control("settings.center.archive.hours") as! NSTextField
        let restored = field.currentEditor() as? NSTextView
        try require(restored?.string == text && restored?.selectedRange() == selection, "continueDidNotRestoreEditor")
        host.center.window.performClose(nil)
        try await wait { self.host.center.window.attachedSheet != nil }
        try click("settings.center.close.discard", window: host.center.window.attachedSheet!)
        try await wait { !self.host.center.isVisible && !self.host.model.hasArchiveDraft }
        try require(try read(LifecycleSettings.self, "lifecycle-settings.json").archiveAfterSeconds == 5_400,
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
        host.show(page: .general)
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
        _ = try edit("settings.center.archive.hours", text: "1.75")
        try click("settings.center.archive.save")
        try await wait { self.host.snapshot.state.owner.settings.archiveAfterHours == 1.75 }
        try require(host.snapshot.appearance.failure != nil && host.snapshot.state.domains[.layout]?.saveFailure != nil,
                    "unrelatedSaveClearedErrors")
        host.show(page: .general); try click("settings.center.appearance.retry")
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
                if let visible = window.screen?.visibleFrame, visible.width >= 652, visible.height >= 608 {
                    try require(abs(window.frame.width - 652) <= 1 && abs(window.frame.height - 608) <= 1,
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
        host.center.window.performClose(nil)
        try await wait { !self.host.center.isVisible }
        host.show(page: .display)
        try require(host.center.window.frame.size == size, "reopenLostWindowSize")
        host.center.window.setFrame(original, display: true)
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
        // host.show() has already requested activation for our settings window.
        // Wait for that asynchronous handoff before simulating its next native
        // action. This is only driver sequencing, never a product focus gate.
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

    @discardableResult private func createFixture(_ suffix: String) throws -> String {
        try validateEnvironment()
        let name = "settings-review-synthetic-" + UUID().uuidString.lowercased() + "-" + suffix + ".png"
        let file = environment.source.appendingPathComponent(name)
        guard let context = CGContext(data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 160 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.encoding }
        context.setFillColor(CGColor(red: 0.12, green: 0.44, blue: 0.35, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        context.setFillColor(CGColor(gray: 0.94, alpha: 1)); context.fill(CGRect(x: 15, y: 20, width: 112, height: 12))
        // Each generated fixture has distinct pixels as well as a distinct
        // source filename, so a later import cannot match an earlier image.
        for (index, byte) in SHA256.hash(data: Data(name.utf8)).enumerated() {
            context.setFillColor(CGColor(gray: CGFloat(byte) / 255, alpha: 1))
            context.fill(CGRect(x: 15 + index * 4, y: 60, width: 4, height: 12))
        }
        guard let image = context.makeImage() else { throw Failure.encoding }
        let data = try png(image)
        try data.write(to: file, options: .withoutOverwriting)
        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = marker.withUnsafeBytes { setxattr(file.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0) }
        try require(result == 0, "fixtureMetadataWriteFailed")
        artifacts.append(["kind": "syntheticCollectorInput", "file": "fixture-source/" + name,
                          "sha256": digest(data), "pixels": [160, 100], "systemScreenshot": false,
                          "testMetadataExplicitlyAdded": true])
        return digest(data)
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
            "inputMethod": "Native NSControl actions and NSTextView insertion; no physical pointer or OS IME claim",
            "scope": "UUID-isolated real host/model/SQLite/collector and AppKit windows in the same App binary",
            "notRun": ["realChatGPTAttachment", "physicalPointer", "OSInputMethod", "VoiceOver", "realLoginRegistration", "realTCCPrompt", "multiDisplayHotplug"],
            "productionDataAccess": false, "browserAccess": false, "networkUpload": false,
            "cases": cases, "frames": frames, "artifacts": artifacts, "restorationFailures": restorationFailures]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("report.json"), options: .atomic)
    }
}
