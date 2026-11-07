import AppKit
import CryptoKit

private typealias Facts = [String: Any]

private func errors(_ error: Error) -> [[String: Any]] {
    var result = [[String: Any]]()
    var current: NSError? = error as NSError
    // Never publish localized descriptions, userInfo, paths or bookmark bytes.
    while let value = current, result.count < 4 {
        let allowed = [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain]
        result.append(["domain": allowed.contains(value.domain) ? value.domain : "other", "code": value.code])
        current = value.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return result
}

@MainActor
private final class Probe: NSObject, NSApplicationDelegate, NSOpenSavePanelDelegate {
    let root: URL
    let phase: String
    let nonce: String
    let expectedHash: String
    let markerReady: Bool
    let defaults: UserDefaults
    let protectedFolder: URL
    var facts: Facts
    var panel: NSOpenPanel?

    override init() {
        let args = CommandLine.arguments
        guard args.count == 5, args[1] == "--fixture-root", args[3] == "--phase",
              let id = Bundle.main.bundleIdentifier, let token = Bundle.main.object(forInfoDictionaryKey: "FixtureNonce") as? String,
              UUID(uuidString: token) != nil, id == "org.riftlet.release-identity-host." + token else { exit(64) }
        root = URL(fileURLWithPath: args[2], isDirectory: true)
        phase = args[4]
        nonce = token
        let versions = ["v1-initial": "1", "v1-picker": "1", "v1-restart": "1",
                        "v2-update": "2", "v2-picker": "2", "rollback-v1": "1"]
        guard root.lastPathComponent == "riftlet-identity-host-" + token,
              let version = versions[phase], Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == version,
              Bundle.main.bundleURL.resolvingSymlinksInPath().path == root.appendingPathComponent("installed/Fixture.app").resolvingSymlinksInPath().path,
              let configBytes = try? Data(contentsOf: root.appendingPathComponent("fixture.json")),
              let config = (try? JSONSerialization.jsonObject(with: configBytes)) as? Facts,
              config["nonce"] as? String == token, let hash = config["markerSHA256"] as? String,
              let ready = config["markerReady"] as? Bool, let domain = UserDefaults(suiteName: id + ".fixture"),
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { exit(65) }
        expectedHash = hash
        markerReady = ready
        defaults = domain
        protectedFolder = downloads.appendingPathComponent("riftlet-host-" + token, isDirectory: true)
        facts = ["phase": phase, "verifiedLaunchedVersion": version, "verifiedSameInstalledPath": true]
        super.init()
    }

    func persist(_ stage: String, completed: Bool = false) {
        facts["stage"] = stage
        facts["completed"] = completed
        // The PID stays in the private driver handoff for exact-process teardown.
        let envelope: Facts = ["pid": ProcessInfo.processInfo.processIdentifier, "observations": facts]
        do {
            let bytes = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            try bytes.write(to: root.appendingPathComponent(phase + ".json"), options: .atomic)
        } catch { exit(74) }
    }

    func readMarker(_ folder: URL) -> Facts {
        do {
            let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            guard entries.contains(where: { $0.lastPathComponent == "marker" }) else { return ["state": "MARKER_MISSING"] }
            let data = try Data(contentsOf: folder.appendingPathComponent("marker"))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return ["state": hash == expectedHash ? "READ_VERIFIED" : "WRONG_BYTES"]
        } catch { return ["state": "READ_FAILED", "errors": errors(error)] }
    }

    func restore(_ folder: URL, mode: String) -> Facts {
        let key = "Riftlet.sourceAccess.v1." + mode
        guard let bytes = defaults.data(forKey: key) else { return ["state": "NO_BOOKMARK"] }
        // Measure the production restore and read before a second diagnostic
        // bookmark resolution could influence this process's access.
        let owner = ScreenshotFolderAccess(defaults: defaults, modeName: mode)
        owner.restore(for: folder)
        let afterRestore = readMarker(folder)
        owner.stop()
        var info: Facts = [:]
        do {
            var stale = false
            let resolved = try URL(resolvingBookmarkData: bytes, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
            info = ["state": "RESOLVED", "stale": stale, "matchesFolder": SourceAccessSelection.matches(selected: resolved, actualSource: folder)]
        } catch { info = ["state": "RESOLUTION_FAILED", "errors": errors(error)] }
        info["afterProductionRestore"] = afterRestore
        info["bookmarkBytesChangedByRestore"] = defaults.data(forKey: key) != bytes
        let reference = root.appendingPathComponent(mode + ".first-bookmark-digest")
        if let initial = try? Data(contentsOf: reference) {
            info["matchesFirstSavedBookmark"] = initial == Data(SHA256.hash(data: bytes))
        }
        return info
    }

    func accept(_ url: URL, folder: URL, mode: String) -> Facts {
        let owner = ScreenshotFolderAccess(defaults: defaults, modeName: mode)
        defer { owner.stop() }
        do {
            try owner.accept(url, actualSource: folder)
        } catch { return ["state": "SAVE_FAILED", "errors": errors(error)] }
        var result: Facts = ["state": "SAVED", "afterSave": readMarker(folder)]
        do {
            if phase == "v1-initial" || phase == "v1-picker",
               let bytes = defaults.data(forKey: "Riftlet.sourceAccess.v1." + mode) {
                try Data(SHA256.hash(data: bytes)).write(to: root.appendingPathComponent(mode + ".first-bookmark-digest"),
                                                       options: .withoutOverwriting)
                result["initialFingerprintSaved"] = true
            }
        } catch { result["initialFingerprintError"] = errors(error) }
        return result
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        facts["displayAvailable"] = !NSScreen.screens.isEmpty
        persist("launched")
        let control = root.appendingPathComponent("control", isDirectory: true)
        if phase == "v1-initial" {
            facts["controlSave"] = accept(control, folder: control, mode: "Control")
        }
        facts["controlBookmark"] = restore(control, mode: "Control")
        guard markerReady else {
            facts["protectedDirect"] = ["state": "NOT_RUN_MARKER_UNAVAILABLE"]
            finish()
            return
        }
        if phase.hasSuffix("-picker") { showPicker(); return }
        persist("directProtectedRead")
        facts["protectedDirect"] = readMarker(protectedFolder)
        persist("protectedBookmarkRestore")
        facts["protectedBookmark"] = restore(protectedFolder, mode: "Downloads")
        finish()
    }

    func showPicker() {
        guard !NSScreen.screens.isEmpty else {
            facts["picker"] = ["state": "NOT_RUN_NO_DISPLAY"]
            finish()
            return
        }
        let chooser = NSOpenPanel()
        panel = chooser
        chooser.delegate = self
        chooser.canChooseFiles = false
        chooser.canChooseDirectories = true
        chooser.canCreateDirectories = false
        chooser.allowsMultipleSelection = false
        chooser.directoryURL = protectedFolder
        chooser.title = "Choose fixture " + nonce
        chooser.prompt = "Select fixture"
        chooser.message = "Choose only the Downloads fixture folder for " + nonce
        persist("normalFolderPicker")
        chooser.begin { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = chooser.url,
               SourceAccessSelection.matches(selected: url, actualSource: self.protectedFolder) {
                self.facts["picker"] = ["state": "EXACT_NATIVE_SELECTION",
                    "save": self.accept(url, folder: self.protectedFolder, mode: "Downloads")]
                self.facts["protectedBookmark"] = self.restore(self.protectedFolder, mode: "Downloads")
            } else { self.facts["picker"] = ["state": "NO_VERIFIED_SELECTION"] }
            self.finish()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.panel?.cancel(nil) }
    }

    func panel(_ sender: Any, validate url: URL) throws {
        try SourceAccessSelection.validate(selected: url, actualSource: protectedFolder)
    }

    func finish() {
        panel = nil
        defaults.synchronize()
        persist("finished", completed: true)
        NSApp.terminate(nil)
    }
}

@main
private enum HostProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let probe = Probe()
        app.delegate = probe
        withExtendedLifetime(probe) { app.run() }
    }
}
