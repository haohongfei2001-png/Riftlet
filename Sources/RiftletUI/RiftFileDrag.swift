import AppKit
import RiftletCore

/// A local file copy is the entire public drag contract. AppKit and the drop
/// destination own the rest of the interaction, including a refusal or Escape.
@MainActor
final class RiftFileDrag: NSObject, NSDraggingSource {
    let id = UUID()
    private let finished: (UUID, NSDragOperation) -> Void

    init(finished: @escaping (UUID, NSDragOperation) -> Void) { self.finished = finished }

    static func file(for record: AssetRecord, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(record.image.fileName)
        let (_, identity) = try HistoryPreviewDecode.verifiedBytes(asset: record.image, directory: directory, retainingBytes: false)
        guard identity.matches(url) else { throw HistoryPreviewFailure.fileChanged }
        return url
    }

    func start(url: URL, image: CGImage?, from view: NSView, event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let picture = image.map { NSImage(cgImage: $0, size: .zero) } ?? NSWorkspace.shared.icon(forFile: url.path)
        let factor = min(1, 128 / max(1, picture.size.width), 96 / max(1, picture.size.height))
        let size = CGSize(width: max(1, picture.size.width * factor), height: max(1, picture.size.height * factor))
        let cursor = view.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: cursor.x - size.width / 2, y: cursor.y - size.height / 2,
                                     width: size.width, height: size.height), contents: picture)
        view.beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finished(id, operation)
    }
}
