import Foundation

/// Owned capture files stay outside directory-watcher admission, including
/// while a markup editor is open. Both active and retired source scans skip
/// hidden files; the host explicitly imports the one completed selection.
/// This changes only new names, never existing files or their origin metadata.
public enum InteractiveScreenshotOutput {
    public static func originalURL(in directory: URL, captureID: UUID) -> URL {
        directory.appendingPathComponent("." + captureID.uuidString.lowercased() + ".png")
    }

    public static func editedURL(in directory: URL, id: UUID = UUID()) -> URL {
        directory.appendingPathComponent("." + id.uuidString.lowercased() + "-edited.png")
    }
}
