import ApplicationServices
import CryptoKit
import Darwin
import Foundation
import RiftletCore

/// Version and surface admission is explicit. This value only selects native
/// evidence code; it does not register a completion or safe-retry receipt policy.
public struct MacAXClientProfile: Equatable, Sendable {
    public let adapterID: String
    public let bundleID: String
    public let version: String
    public let build: String
    public let surface: TargetSurface
    public let evidenceID: String

    public init(adapterID: String, bundleID: String, version: String, build: String,
                surface: TargetSurface, evidenceID: String) throws {
        guard [adapterID, bundleID, version, build, evidenceID].allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 512
                && !$0.unicodeScalars.contains(where: { $0.value < 32 })
        }), [TargetSurface.macChat, .macWork, .macClassic].contains(surface) else {
            throw NativeMacAXError.invalidConfiguration
        }
        self.adapterID = adapterID; self.bundleID = bundleID; self.version = version
        self.build = build; self.surface = surface; self.evidenceID = evidenceID
    }
}

public struct MacAXTargetBinding: Sendable {
    public let session: MacTargetSession
    public let profile: MacAXClientProfile
    public let application: MacAXElement
    public let window: MacAXElement
    public let composer: MacAXElement
    public let pasteMenuItem: MacAXElement

    /// A provider must identify Paste from real version-specific evidence. A
    /// generic AXMenuItem/AXPress match is never sufficient to choose this node.
    public init(session: MacTargetSession, profile: MacAXClientProfile,
                application: MacAXElement, window: MacAXElement,
                composer: MacAXElement, pasteMenuItem: MacAXElement) {
        self.session = session; self.profile = profile; self.application = application
        self.window = window; self.composer = composer; self.pasteMenuItem = pasteMenuItem
    }
}

/// Client-specific evidence boundary: real observed composer/draft binding,
/// exact Paste-menu identity and per-image observation. It must not activate,
/// mutate text/selection, press actions or silently bind a different draft.
/// Methods are synchronous so no actor suspension separates final checks/input.
/// Implementing a provider does not replace live selection, privacy, input and
/// abnormal-case acceptance of the complete native backend.
@MainActor public protocol MacAXBindingProvider: Sendable {
    func capture(using driver: any MacAXDriver) throws -> MacAXTargetBinding?
    func resolve(_ original: TargetLease, using driver: any MacAXDriver) throws -> MacAXTargetBinding?
    func isOriginalDraft(_ binding: MacAXTargetBinding, using driver: any MacAXDriver) throws -> Bool
    func observation(for request: TransferRequest, binding: MacAXTargetBinding,
                     using driver: any MacAXDriver) throws -> AttachmentObservation?
}

/// No guessed ChatGPT nodes or client versions are built in.
@MainActor public struct UnavailableMacAXBindingProvider: MacAXBindingProvider {
    public init() {}
    public func capture(using driver: any MacAXDriver) throws -> MacAXTargetBinding? { nil }
    public func resolve(_ original: TargetLease, using driver: any MacAXDriver) throws -> MacAXTargetBinding? { nil }
    public func isOriginalDraft(_ binding: MacAXTargetBinding, using driver: any MacAXDriver) throws -> Bool { false }
    public func observation(for request: TransferRequest, binding: MacAXTargetBinding,
                            using driver: any MacAXDriver) throws -> AttachmentObservation? { nil }
}

/// Native M0 executor. The App does not construct it, supported profiles are
/// empty, and even explicit development composition accepts synthetic assets
/// only. Actual AXPress success means neither image input nor completion.
@MainActor public final class NativeMacAttachmentExecutor: CoordinatedMacAttachmentExecutor {
    public static let supportedProfiles: [MacAXClientProfile] = []
    private let driver: any MacAXDriver
    private let bindingProvider: any MacAXBindingProvider
    private let clipboardOwner: any SynchronousClipboardOwner
    public nonisolated let clipboardCoordinator: MacClipboardCoordinator
    private let mediaDirectory: URL
    private let profile: MacAXClientProfile?
    private let mode: MacAdapterMode
    private var attemptedOperations: Set<UUID> = []

    public init(driver: any MacAXDriver, clipboardOwner: any SynchronousClipboardOwner,
                coordinator: MacClipboardCoordinator, mediaDirectory: URL,
                profile: MacAXClientProfile? = nil, mode: MacAdapterMode = .disabled,
                bindingProvider: (any MacAXBindingProvider)? = nil) {
        self.driver = driver; self.clipboardOwner = clipboardOwner; clipboardCoordinator = coordinator
        self.mediaDirectory = mediaDirectory.standardizedFileURL; self.profile = profile
        self.mode = mode; self.bindingProvider = bindingProvider ?? UnavailableMacAXBindingProvider()
    }

    public func captureTarget() async throws -> MacTargetSession {
        let profile = try requireEnabled()
        guard let binding = try bindingProvider.capture(using: driver) else { throw NativeMacAXError.unsupportedClient }
        try validate(binding, profile: profile, requireFocus: true)
        return binding.session
    }

    public func inspectTarget(_ original: TargetLease) async throws -> MacTargetSession? {
        let profile = try requireEnabled()
        guard let binding = try bindingProvider.resolve(original, using: driver), binding.session.target == original else { return nil }
        do { try validate(binding, profile: profile, requireFocus: false) }
        catch NativeMacAXError.targetChanged { return nil }
        return binding.session
    }

    public func paste(_ request: TransferRequest, owner: ClipboardOwnerState) async throws -> Data {
        let profile = try requireEnabled()
        try validateRequest(request, forInput: true)
        guard !attemptedOperations.contains(request.operation.id), attemptedOperations.count < 4_096 else {
            throw NativeMacAXError.inputAlreadyAttempted
        }
        guard let binding = try bindingProvider.resolve(request.operation.target, using: driver),
              binding.session.target == request.operation.target else { throw NativeMacAXError.targetChanged }
        let file = try NativeMacVerifiedFile(request: request, mediaDirectory: mediaDirectory)
        try file.verifyBytes()
        try validate(binding, profile: profile, requireFocus: true)
        try validateOwner(owner, request: request)

        // Durable at-most-once intent precedes the action, including any ambiguous
        // AX error. The shared journal is required; an in-memory set alone cannot
        // protect another instance or a process restart.
        try clipboardCoordinator.markInputIntent(for: request, owner: owner)
        attemptedOperations.insert(request.operation.id)

        // No await, fallback, activation or focus-setting in this final fragment.
        // These checks narrow races; AX/pasteboard do not offer a single OS CAS.
        try validate(binding, profile: profile, requireFocus: true)
        try file.verifyPathAndMetadata()
        try validateOwner(owner, request: request)
        do { try driver.press(binding.pasteMenuItem) }
        catch { return try encodeUnknown(request, profile: profile) }

        // A successful AX action has no positive attachment semantics. Query the
        // original evidence provider; its absence, changed target or query error
        // remains UNKNOWN and cannot trigger a second Paste.
        do {
            try validate(binding, profile: profile, requireFocus: false)
            return try encodeObservation(request, binding: binding, profile: profile)
        } catch { return try encodeUnknown(request, profile: profile) }
    }

    public func observe(_ request: TransferRequest) async throws -> Data {
        let profile = try requireEnabled()
        try validateRequest(request, forInput: false)
        guard let binding = try bindingProvider.resolve(request.operation.target, using: driver),
              binding.session.target == request.operation.target else { return try encodeUnknown(request, profile: profile) }
        do {
            try validate(binding, profile: profile, requireFocus: false)
            return try encodeObservation(request, binding: binding, profile: profile)
        } catch { return try encodeUnknown(request, profile: profile) }
    }

    private func requireEnabled() throws -> MacAXClientProfile {
        guard case .syntheticDevelopment = mode else { throw MacAdapterError.disabled }
        guard let profile else { throw NativeMacAXError.unsupportedClient }
        guard driver.isTrusted() else { throw NativeMacAXError.permissionUnavailable }
        return profile
    }

    private func validateRequest(_ request: TransferRequest, forInput: Bool) throws {
        guard request.asset.origin == .synthetic else { throw MacAdapterError.syntheticAssetsOnly }
        guard request.operation.assetID == request.asset.id, request.operation.attempt > 0,
              forInput ? request.operation.phase == .dispatchIntent
                : (request.operation.phase.isUnresolved && request.operation.phase != .prepared) else {
            throw MacAdapterError.invalidRequest
        }
    }

    private func validate(_ binding: MacAXTargetBinding, profile: MacAXClientProfile, requireFocus: Bool) throws {
        let session = binding.session
        let target = session.target
        let identity = MacAXApplicationIdentity(processID: session.processID, launchedAt: session.launchedAt,
            bundleID: profile.bundleID, version: profile.version, build: profile.build)
        guard binding.profile == profile, target.applicationID == profile.bundleID,
              target.adapterID == profile.adapterID, target.surface == profile.surface,
              target.tabID == nil,
              try driver.applicationIdentity(processID: session.processID) == identity,
              try driver.processID(of: binding.application) == session.processID,
              try driver.processID(of: binding.window) == session.processID,
              try driver.processID(of: binding.composer) == session.processID,
              try driver.processID(of: binding.pasteMenuItem) == session.processID,
              try driver.applicationElement(processID: session.processID) == binding.application,
              try driver.elementAttribute(kAXWindowAttribute as String, of: binding.composer) == binding.window,
              try bindingProvider.isOriginalDraft(binding, using: driver) else {
            throw NativeMacAXError.targetChanged
        }
        if requireFocus {
            guard try driver.frontmostApplication() == identity,
                  try driver.elementAttribute(kAXFocusedWindowAttribute as String, of: binding.application) == binding.window,
                  try driver.elementAttribute(kAXFocusedUIElementAttribute as String, of: binding.application) == binding.composer,
                  try driver.stringAttribute(kAXRoleAttribute as String, of: binding.pasteMenuItem) == (kAXMenuItemRole as String),
                  try driver.boolAttribute(kAXEnabledAttribute as String, of: binding.pasteMenuItem) == true,
                  try driver.actionNames(of: binding.pasteMenuItem).contains(kAXPressAction as String) else {
                throw NativeMacAXError.targetChanged
            }
        }
    }

    private func validateOwner(_ owner: ClipboardOwnerState, request: TransferRequest) throws {
        guard owner.changeCount >= 0, let marker = owner.marker,
              marker.hasPrefix(request.operation.id.uuidString + ":"),
              try clipboardOwner.currentOwnerSynchronously() == owner else { throw NativeMacAXError.clipboardChanged }
    }

    private func encodeObservation(_ request: TransferRequest, binding: MacAXTargetBinding,
                                   profile: MacAXClientProfile) throws -> Data {
        guard let observation = try bindingProvider.observation(for: request, binding: binding, using: driver) else {
            return try encodeUnknown(request, profile: profile)
        }
        let identity = expectedIdentity(request)
        guard observation.identity == identity else { throw ObservationError.identityMismatch }
        // The observer may itself need AX messages. Recheck membership after its
        // work too; a stale positive observation cannot outlive its draft proof.
        try validate(binding, profile: profile, requireFocus: false)
        let envelope = AttachmentObservationEnvelope(
            provenance: .init(source: .integratedDevelopment, evidenceID: profile.evidenceID), observation: observation)
        try ObservationDecoder.validate(envelope)
        return try JSONEncoder().encode(envelope)
    }

    private func encodeUnknown(_ request: TransferRequest, profile: MacAXClientProfile) throws -> Data {
        let observation = AttachmentObservation(identity: expectedIdentity(request), state: .unknown)
        return try JSONEncoder().encode(AttachmentObservationEnvelope(
            provenance: .init(source: .integratedDevelopment, evidenceID: profile.evidenceID), observation: observation))
    }

    private func expectedIdentity(_ request: TransferRequest) -> ObservationIdentity {
        ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
    }
}

/// Private regular-file identity is checked on an open descriptor, then against
/// the exact clipboard path before action. The importer remains codec authority.
private final class NativeMacVerifiedFile {
    private let descriptor: Int32
    private let directoryDescriptor: Int32
    private let directory: URL
    private let name: String
    private let original: stat
    private let originalDirectory: stat
    private let expectedHash: String

    init(request: TransferRequest, mediaDirectory: URL) throws {
        let url = request.fileURL.standardizedFileURL
        guard mediaDirectory.isFileURL, url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.deletingLastPathComponent().path == mediaDirectory.path, url.lastPathComponent == request.asset.fileName,
              !request.asset.fileName.isEmpty, request.asset.fileName != ".", request.asset.fileName != "..",
              !request.asset.fileName.contains("/"), request.asset.byteCount > 0,
              request.asset.byteCount <= 16 * 1024 * 1024 else { throw NativeMacAXError.invalidPrivateFile }
        let dirFD = open(mediaDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw NativeMacAXError.invalidPrivateFile }
        var directoryStat = stat()
        guard fstat(dirFD, &directoryStat) == 0 else { close(dirFD); throw NativeMacAXError.invalidPrivateFile }
        let fd = openat(dirFD, request.asset.fileName, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { close(dirFD); throw NativeMacAXError.invalidPrivateFile }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_size == request.asset.byteCount else {
            close(fd); close(dirFD); throw NativeMacAXError.invalidPrivateFile
        }
        descriptor = fd; directoryDescriptor = dirFD; directory = mediaDirectory; name = request.asset.fileName
        original = info; originalDirectory = directoryStat; expectedHash = request.asset.sha256
    }

    deinit { close(descriptor); close(directoryDescriptor) }

    func verifyBytes() throws {
        var hasher = SHA256()
        var total: Int64 = 0
        var buffer = Data(count: 64 * 1024)
        while true {
            let count: Int = buffer.withUnsafeMutableBytes { bytes in
                var result: Int
                repeat { result = read(descriptor, bytes.baseAddress, bytes.count) } while result < 0 && errno == EINTR
                return result
            }
            guard count >= 0 else { throw NativeMacAXError.invalidPrivateFile }
            if count == 0 { break }
            total += Int64(count)
            guard total <= original.st_size else { throw NativeMacAXError.invalidPrivateFile }
            hasher.update(data: buffer.prefix(count))
        }
        guard total == original.st_size,
              hasher.finalize().map({ String(format: "%02x", $0) }).joined() == expectedHash else {
            throw NativeMacAXError.invalidPrivateFile
        }
        try verifyPathAndMetadata()
    }

    func verifyPathAndMetadata() throws {
        var now = stat(); var path = stat(); var dirPath = stat()
        guard fstat(descriptor, &now) == 0,
              fstatat(directoryDescriptor, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
              lstat(directory.path, &dirPath) == 0,
              dirPath.st_dev == originalDirectory.st_dev, dirPath.st_ino == originalDirectory.st_ino,
              Self.sameFile(original, now), Self.sameFile(original, path) else {
            throw NativeMacAXError.invalidPrivateFile
        }
    }

    private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
        (rhs.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) && lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}
