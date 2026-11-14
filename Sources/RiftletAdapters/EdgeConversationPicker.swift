import ApplicationServices
import Foundation
#if RIFTLET_CONTROLLED_EDGE
import Darwin
#endif

/// Native file-list candidate. No commercial receiver is admitted. In particular
/// a response from Edge's page JavaScript cannot manufacture this capability.
@MainActor
final class EdgeConversationPicker: AttachmentTransport {
    enum Outcome: Equatable {
        case refusedBeforeEntry, alreadyAttempted, entryAttempted, inputAttempted, uncertain
    }

    enum OpenedChooser {
        case fileList(Controls)
        case systemPanel(selectAndConfirm: () throws -> Outcome)
    }

    struct Controls {
        let choice: MacAXElement
        let submit: MacAXElement
        let matchesFile: (AXPickerFileHandoff.Stage) throws -> Bool
        let selectionSettled: () throws -> Bool
    }

    struct Input {
        /// Read the original receiver's native chooser. Nil in the initial
        /// state is checked separately from discovery after the unique press.
        let chooserIsAbsent: () throws -> Bool
        let findOpenedControls: (URL) throws -> OpenedChooser?
    }

    private let binding: AXPickerInspection
    private let originalDraft: () throws -> Bool
    private let file: URL
    private let verified: NativeMacVerifiedFile
    private var attempted = false

    private init(binding: AXPickerInspection, originalDraft: @escaping () throws -> Bool,
                 directory: URL, file: URL, bytes: Int64, sha256: String) throws {
        let pinned = try Self.pinPNG(directory: directory, file: file, bytes: bytes, sha256: sha256)
        guard try binding.originalDraftIsCurrent(originalDraft) else { throw NativeMacAXError.targetChanged }
        self.binding = binding
        self.originalDraft = originalDraft
        self.file = file.standardizedFileURL
        self.verified = pinned
    }

    static func pinPNG(directory: URL, file: URL, bytes: Int64, sha256: String) throws -> NativeMacVerifiedFile {
        let original = file.standardizedFileURL
        guard directory.isFileURL, original.isFileURL, original.pathExtension.lowercased() == "png",
              directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path,
              original.resolvingSymlinksInPath().path == original.path,
              // Foundation also spells Darwin's system /private/var mount /var.
              // Accept that exact spelling pair only. Arbitrary aliased leaves
              // and directories still have to pass resolution and fd rechecks.
              (file.path == original.path || original.path.hasPrefix("/var/") && file.path == "/private" + original.path),
              sha256.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw NativeMacAXError.invalidPrivateFile }
        let pinned = try NativeMacVerifiedFile(fileURL: original, mediaDirectory: directory.standardizedFileURL,
                                               name: original.lastPathComponent, byteCount: bytes, sha256: sha256)
        try pinned.verifyBytes(expectedPrefix: Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82]))
        return pinned
    }

    #if DEBUG || RIFTLET_CONTROLLED_PICKER
    /// Exclusive to the controlled receiver. An arbitrary bundle, including a
    /// real Edge process, cannot opt in by supplying callbacks or a URL.
    static func controlled(fixtureID: UUID, binding: AXPickerInspection, originalDraft: @escaping () throws -> Bool,
                           directory: URL, file: URL, bytes: Int64, sha256: String) throws -> EdgeConversationPicker {
        guard binding.process.bundleID == "org.riftlet.axpicker." + fixtureID.uuidString else {
            throw NativeMacAXError.unsupportedClient
        }
        return try EdgeConversationPicker(binding: binding, originalDraft: originalDraft, directory: directory,
                                          file: file, bytes: bytes, sha256: sha256)
    }
    #endif

    func handOff(_ input: Input) throws -> Outcome {
        guard !attempted else { return .alreadyAttempted }
        attempted = true
        guard try binding.originalDraftIsCurrent(originalDraft),
              try input.chooserIsAbsent(),
              try binding.driver.boolAttribute(kAXEnabledAttribute, of: binding.entry) == true,
              try binding.originalDraftIsCurrent(originalDraft) else { return .refusedBeforeEntry }
        try verified.verifyPathAndMetadata()
        // Both the chooser and the call that opens it can be asynchronous. Once
        // a press is entered there is no second entry press or alternate input.
        do {
            try binding.driver.press(binding.entry)
            guard let chooser = try input.findOpenedControls(file) else { return .entryAttempted }
            switch chooser {
            case .systemPanel(let selectAndConfirm):
                guard try binding.originalDraftIsCurrent(originalDraft) else { return .entryAttempted }
                try verified.verifyPathAndMetadata()
                return try selectAndConfirm()
            case .fileList(let controls):
                return try handOffFileList(controls)
            }
        } catch { return .uncertain }
    }

    private func handOffFileList(_ controls: Controls) throws -> Outcome {
        let delivery = AXPickerFileHandoff(binding: binding, choice: controls.choice, submit: controls.submit)
        let request = AXPickerFileHandoff.Input(matchesDraft: originalDraft, matchesChoice: { [self] stage in
            guard try controls.matchesFile(stage), try binding.originalDraftIsCurrent(originalDraft) else {
                return false
            }
            try verified.verifyPathAndMetadata()
            return true
        }, selectionSettled: controls.selectionSettled)
        switch try delivery.handOff(request) {
        case .refused: return .entryAttempted
        case .submitted: return .inputAttempted
        case .uncertain: return .uncertain
        }
    }
}

#if RIFTLET_CONTROLLED_EDGE
/// For a disposable owned Edge instance only. The caller supplies the exact
/// launched child, loopback draft URL and generated PNG; a native tab pin and
/// independently read WebArea, editor, entry, prior image and range are mandatory.
extension EdgeConversationPicker {
    static func handOffNeutralEdge(pid: pid_t, birth: String, address: URL, directory: URL,
                                   file: URL, bytes: Int64, sha256: String) throws -> Outcome {
        let env = ProcessInfo.processInfo.environment
        guard env["GITHUB_ACTIONS"] == "true", env["RUNNER_ENVIRONMENT"] == "github-hosted",
              env["GITHUB_REPOSITORY"] == "haohongfei2001-png/Riftlet",
              let runner = env["RUNNER_TEMP"],
              let parts = URLComponents(url: address, resolvingAgainstBaseURL: false),
              parts.scheme == "http", parts.host == "127.0.0.1", parts.port != nil, parts.query == nil,
              parts.fragment == nil, parts.user == nil, parts.password == nil,
              parts.percentEncodedPath.range(of: #"^/RiftletNeutral[a-f0-9]{32}$"#, options: .regularExpression) != nil
        else { throw NativeMacAXError.unsupportedClient }
        let scratch = directory.deletingLastPathComponent().resolvingSymlinksInPath()
        guard directory.lastPathComponent == "picker-images", scratch.lastPathComponent.hasPrefix("riftlet-edge-host-"),
              scratch.deletingLastPathComponent().path == URL(fileURLWithPath: runner).resolvingSymlinksInPath().path,
              file.lastPathComponent == "neutral.png" else { throw NativeMacAXError.invalidPrivateFile }
        let host = EdgeApplicationHost()
        let target = try host.freeze()
        guard target.process.pid == pid, "\(target.process.seconds):\(target.process.microseconds)" == birth,
              target.address == address.absoluteString else { throw NativeMacAXError.targetChanged }
        let driver = try NativeMacAXDriver(messagingTimeout: 0.12)
        let ax = EdgeNativeDraftProbe(driver: driver)
        func snapshot() throws -> EdgeNativeDraftProbe.Snapshot {
            try host.revalidate(target)
            let result = try ax.read(process: target.process, address: address, editorID: "riftlet-neutral-editor",
                                     controlledChooser: true)
            try host.revalidate(target)
            return result
        }
        let original = try snapshot()
        guard let entry = original.entry, original.prior != nil, original.text == "Neutral unsent draft",
              original.selection.location == 2, original.selection.length == 5,
              let identity = try driver.applicationIdentity(processID: pid), identity.bundleID == EdgeApplicationHost.bundleID
        else { throw NativeMacAXError.targetChanged }
        let binding = AXPickerInspection(driver: driver, process: identity, window: original.window,
                                        editor: original.editor, entry: entry)
        let same = { try snapshot() == original }
        let transport = try EdgeConversationPicker(binding: binding, originalDraft: same, directory: directory,
                                                   file: file, bytes: bytes, sha256: sha256)
        let input = Input(chooserIsAbsent: {
            let nodes = try driver.elementsAttribute(kAXChildrenAttribute, of: binding.window, maximumCount: 128)
            for node in nodes where try driver.stringAttribute(kAXRoleAttribute, of: node) == kAXSheetRole { return false }
            return true
        }, findOpenedControls: { url in
            let panel = EdgeOwnedFilePanel(binding: binding, originalDraft: same, file: url, pinned: transport.verified)
            guard let sheet = try panel.awaitSheet() else { return nil }
            return .systemPanel(selectAndConfirm: { try panel.submit(sheet) })
        })
        // Persist on this disposable run before AXPress. A restarted helper
        // cannot reopen the picker for the same generated file after a lost reply.
        let intent = scratch.appendingPathComponent("neutral-picker-input-intent")
        let descriptor = open(intent.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            if errno == EEXIST { return .alreadyAttempted }
            throw NativeMacAXError.invalidConfiguration
        }
        close(descriptor)
        return try transport.handOff(input)
    }
}
#endif
