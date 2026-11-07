import AppKit
import Carbon
import CryptoKit
import RiftletCore
import RiftletCapture

private typealias Facts = [String: Any]
private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
private func errorCodes(_ error: Error) -> [[String: Any]] {
    var current: NSError? = error as NSError
    var result: [[String: Any]] = []
    while let value = current, result.count < 4 {
        let known = [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain].contains(value.domain)
        result.append(["domain": known ? value.domain : "other", "code": value.code])
        current = value.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return result
}

private func readMarker(_ dir: URL, expected: String) -> Facts {
    do {
        let bytes = try Data(contentsOf: dir.appendingPathComponent("marker"))
        return ["state": digest(bytes) == expected ? "MATCH" : "WRONG_BYTES"]
    } catch { return ["state": "ERROR", "codes": errorCodes(error)] }
}

private struct Location: CaptureLocationProviding {
    let directory: URL
    func currentDirectory() async throws -> URL { directory }
    func start(onChange: @escaping @Sendable () async -> Void) async throws {}
    func stop() async {}
}

@main @MainActor
private final class Probe: NSObject, NSApplicationDelegate {
    let nonce: String, role: String, phase: String, member: String, expected: String
    let fixtureHome: URL, installedRoot: URL
    var facts: Facts = [:]
    var panel: NSOpenPanel?

    static func main() {
        let app = NSApplication.shared
        let probe = Probe()
        app.delegate = probe
        withExtendedLifetime(probe) { app.run() }
    }

    override init() {
        let args = CommandLine.arguments
        guard args.count == 7,
              let token = Bundle.main.object(forInfoDictionaryKey: "FixtureNonce") as? String,
              let kind = Bundle.main.object(forInfoDictionaryKey: "FixtureRole") as? String,
              UUID(uuidString: token) != nil, Bundle.main.bundleIdentifier == "org.riftlet.scopedlab.\(kind).\(token)",
              ["book", "docallow", "docdeny", "aeallow", "aedeny", "receiver"].contains(kind),
              ["select", "capture", "live", "inspect", "read", "request", "passive", "serve", "settings"].contains(args[3]),
              ["A", "M", "none"].contains(args[4]) else { exit(64) }
        fixtureHome = URL(fileURLWithPath: args[1], isDirectory: true)
        installedRoot = URL(fileURLWithPath: args[2], isDirectory: true)
        guard fixtureHome.lastPathComponent == "Riftlet-Bookmark-Lab-" + token,
              installedRoot.lastPathComponent == "riftlet-scoped-lab-" + token,
              Bundle.main.bundleURL.resolvingSymlinksInPath() == installedRoot.appendingPathComponent(kind + ".app", isDirectory: true).resolvingSymlinksInPath()
        else { exit(65) }
        nonce = token; role = kind; phase = args[3]; member = args[4]; expected = args[5]
        super.init()
    }

    func emit(_ stage: String) {
        let msg: Facts = ["token": nonce, "pid": getpid(), "role": role, "phase": phase, "stage": stage, "facts": facts]
        guard var bytes = try? JSONSerialization.data(withJSONObject: msg, options: [.sortedKeys]) else { exit(66) }
        bytes.append(10)
        FileHandle.standardOutput.write(bytes)
    }

    func finish() { emit("done"); NSApplication.shared.terminate(nil) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        facts["display"] = !NSScreen.screens.isEmpty
        emit("launched")
        Task { @MainActor in
            do {
                if phase == "settings" {
                    guard ["docdeny", "aedeny"].contains(role) else { exit(73) }
                    let pane = role == "docdeny" ? "Privacy_FilesAndFolders" : "Privacy_Automation"
                    emit("recovering")
                    facts["openedSettings"] = NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane)!)
                    try await Task.sleep(nanoseconds: 12_000_000_000)
                    finish(); return
                }
                switch role {
                case "book": try await bookmark()
                case "docallow", "docdeny":
                    guard phase == "read", let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { exit(67) }
                    emit("reading")
                    facts["read"] = readMarker(documents.appendingPathComponent("Riftlet-Files-" + nonce), expected: expected)
                case "receiver":
                    guard phase == "serve" else { exit(68) }
                    NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(receive(_:withReplyEvent:)),
                                                               forEventClass: 0x7266746c, andEventID: 0x70696e67)
                    emit("serving")
                    return
                case "aeallow", "aedeny": try automation()
                default: exit(69)
                }
            } catch { facts["failure"] = errorCodes(error) }
            finish()
        }
    }

    @objc func receive(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        reply.setDescriptor(NSAppleEventDescriptor(boolean: true), forKeyword: keyDirectObject)
    }

    func automation() throws {
        guard ["passive", "request"].contains(phase), let receiverPID = Int32(CommandLine.arguments[6]) else { exit(70) }
        let receiverPath = installedRoot.appendingPathComponent("receiver.app", isDirectory: true).resolvingSymlinksInPath()
        func receiverDate() -> Date? {
            guard let app = NSRunningApplication(processIdentifier: receiverPID),
                  app.bundleIdentifier == "org.riftlet.scopedlab.receiver." + nonce, !app.isTerminated,
                  app.bundleURL?.resolvingSymlinksInPath() == receiverPath else { return nil }
            return app.launchDate
        }
        guard let birth = receiverDate() else { facts["receiverVerified"] = false; return }
        let desc = NSAppleEventDescriptor(processIdentifier: receiverPID)
        func permission(_ request: Bool) -> OSStatus {
            guard receiverDate() == birth else { return OSStatus(procNotFound) }
            return AEDeterminePermissionToAutomateTarget(desc.aeDesc, typeWildCard, typeWildCard, request)
        }
        let before = permission(false)
        facts["before"] = before
        if phase == "request" && before == OSStatus(errAEEventWouldRequireUserConsent) {
            emit("requesting")
            facts["request"] = permission(true)
        }
        facts["after"] = permission(false)
        facts["receiverVerified"] = receiverDate() == birth
    }

    func bookmark() async throws {
        guard ["select", "capture", "live", "inspect"].contains(phase), ["A", "M"].contains(member) else { exit(71) }
        let source = fixtureHome.appendingPathComponent(member, isDirectory: true)
        let owner = ScreenshotFolderAccess(modeName: "Hosted")
        let key = "Riftlet.sourceAccess.v1.Hosted"
        func summary() -> String { UserDefaults.standard.data(forKey: key).map(digest) ?? "ABSENT" }
        facts["bookmarkBefore"] = summary()
        defer { owner.stop() }
        if phase == "select" {
            facts["beforeSelectionRead"] = readMarker(source, expected: expected)
            let panel = NSOpenPanel()
            self.panel = panel
            panel.title = "Riftlet Folder " + nonce
            panel.message = "Choose fixture " + nonce
            panel.prompt = "Select fixture"; panel.canChooseDirectories = true
            panel.canChooseFiles = false; panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false; panel.directoryURL = source
            emit("showingPanel")
            let answer = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            guard answer == .OK, let selected = panel.url,
                  SourceAccessSelection.matches(selected: selected, actualSource: source) else {
                facts["panel"] = answer == .OK ? "WRONG_FOLDER" : "CANCELLED"
                return
            }
            facts["panel"] = "CONFIRMED_EXACT_FOLDER"
            try owner.accept(selected, actualSource: source)
            _ = UserDefaults.standard.synchronize()
            facts["bookmarkAfter"] = summary()
            facts["afterSelectionRead"] = readMarker(source, expected: expected)
            return
        }
        // Measure the product owner's decision before a separate diagnostic bookmark resolution.
        let outcome = owner.restore(for: source)
        let state: String
        switch outcome {
        case .matchingBookmark: state = "MATCHING"
        case .needsSelection: state = "NEEDS_SELECTION"
        case .noApplicableBookmark: state = "NOT_APPLICABLE"
        }
        facts["owner"] = state
        facts["bookmarkAfter"] = summary()
        if phase == "capture" || phase == "live" {
            try await capture(source: source, owner: owner)
        } else {
            facts["readAfterOwner"] = readMarker(source, expected: expected)
            if let raw = UserDefaults.standard.data(forKey: key) {
                var stale = false
                do {
                    let resolved = try URL(resolvingBookmarkData: raw, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                           relativeTo: nil, bookmarkDataIsStale: &stale)
                    facts["rawResolution"] = ["stale": stale, "samePath": SourceAccessSelection.matches(selected: resolved, actualSource: source)]
                } catch { facts["rawResolution"] = ["errors": errorCodes(error)] }
            }
        }
    }

    func capture(source: URL, owner: ScreenshotFolderAccess) async throws {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { exit(72) }
        let root = support.appendingPathComponent("Riftlet-Folder-Experiment", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try QueueStore(databaseURL: root.appendingPathComponent("fixture.sqlite"))
        let service = CaptureService(store: store, privateRoot: root, sourceDirectory: source,
                                    permitsRead: { url in await owner.permitsRead(of: url) })
        let binding = CaptureSourceBinding(service: service, provider: Location(directory: source),
            permitsSource: { url in await owner.restore(for: url) != .needsSelection })
        let rowsBefore = try await store.assets(includeUsed: true).count
        facts["rowsBefore"] = rowsBefore
        do {
            try await binding.start()
        } catch {
            let status = await service.statusSnapshot()
            facts["watchRunning"] = status.isRunning
            facts["watchReadable"] = status.sourceAccessible
            facts["startError"] = errorCodes(error)
            facts["rowsAfter"] = try await store.assets(includeUsed: true).count
            await binding.stop()
            return
        }
        let status = await service.statusSnapshot()
        facts["watchRunning"] = status.isRunning; facts["watchReadable"] = status.sourceAccessible
        emit("watching")
        if phase == "live" {
            // The independent host replaces the directory only after this watch is active.
            // Give native vnode/parent events and retries a chance before explicit scans.
            try await Task.sleep(nanoseconds: 2_400_000_000)
            facts["passiveRows"] = try await store.assets(includeUsed: true).count
            for _ in 0..<3 {
                try? await service.rescan()
                try await Task.sleep(nanoseconds: 180_000_000)
            }
            let blocked = await service.statusSnapshot()
            facts["runningAfterReplacement"] = blocked.isRunning
            facts["accessibleAfterReplacement"] = blocked.sourceAccessible
            facts["rowsAfter"] = try await store.assets(includeUsed: true).count
            await binding.stop()
            return
        }
        let until = ProcessInfo.processInfo.systemUptime + 10
        while ProcessInfo.processInfo.systemUptime < until {
            let rows = try await store.assets(includeUsed: true)
            if let row = rows.first(where: { $0.image.sha256 == expected }) {
                let file = root.appendingPathComponent("media").appendingPathComponent(row.image.fileName)
                facts["privateCopyMatches"] = digest(try Data(contentsOf: file)) == expected
                facts["rowsAfter"] = rows.count
                break
            }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        await binding.stop()
    }
}
