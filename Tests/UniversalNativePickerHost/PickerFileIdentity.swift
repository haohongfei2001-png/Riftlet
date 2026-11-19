import CryptoKit
import Darwin
import Foundation

/// Exercise the same physical /private/var path Python Path.resolve passes
/// across the process boundary. All files belong to this temporary directory.
@MainActor
func checkPrivatePickerFile() throws -> [String: Bool] {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("riftlet-picker-file-" + UUID().uuidString,
                                                                 isDirectory: true)
    try manager.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? manager.removeItem(at: root) }
    guard let physical = realpath(root.path, nil) else { throw NativeMacAXError.invalidConfiguration }
    defer { free(physical) }
    let physicalRoot = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNI6ZgJAALZAYa2S+pDAAAAAElFTkSuQmCC")!
    let file = physicalRoot.appendingPathComponent("neutral.png")
    try png.write(to: file, options: .withoutOverwriting)
    let sha = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
    func accepted(_ url: URL) throws -> Bool {
        do {
            let pinned = try EdgeConversationPicker.pinPNG(directory: url.deletingLastPathComponent(), file: url,
                                                           bytes: Int64(png.count), sha256: sha)
            try pinned.verifyPathAndMetadata()
            return true
        } catch NativeMacAXError.invalidPrivateFile { return false }
    }
    let leaf = physicalRoot.appendingPathComponent("link.png")
    try manager.createSymbolicLink(at: leaf, withDestinationURL: file)
    let subfolder = physicalRoot.appendingPathComponent("directory-link")
    try manager.createSymbolicLink(at: subfolder, withDestinationURL: physicalRoot)
    return try ["physicalTemporaryPathPinned": accepted(file), "leafSymlinkRefused": !accepted(leaf),
                "parentSymlinkRefused": !accepted(subfolder.appendingPathComponent("neutral.png"))]
}
