// Read-only standalone diagnostic. No shortcut, pointer, browser, TCC request,
// capture command, importer, database, or product admission is invoked.
// swiftc capture-observer.swift -o /tmp/capture-observer
// /tmp/capture-observer <actual-system-save-directory> <seconds: 1...30>
// Keep stdout private: it contains local process/window geometry and pointer state.
import AppKit
import CryptoKit
import ImageIO

func category(owner: String, title: String, captureUIProcess: Bool) -> String? {
    if owner == "screencapture" {
        return title == "touchshield" ? "selectionInputShield" : "captureEngineWindow"
    }
    return captureUIProcess ? "captureUIWindow" : nil
}

func exactCompletePNG(_ image: CGImageSource, _ data: Data) -> Bool {
    data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        && (CGImageSourceGetType(image) as String?) == "public.png"
        && CGImageSourceGetStatus(image) == .statusComplete
}

let args = CommandLine.arguments
if args.dropFirst() == ["--self-check"] {
    // A floating annotation container is neither a selection shield nor a
    // completion receipt; the original count-only diagnostic confused these.
    precondition(category(owner: "screencapture", title: "touchshield", captureUIProcess: false) == "selectionInputShield")
    precondition(category(owner: "截屏", title: "", captureUIProcess: true) == "captureUIWindow")
    precondition(category(owner: "Preview", title: "touchshield", captureUIProcess: false) == nil)
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let pixel = context.makeImage()!
    for (format, expectedPNG) in [("public.png", true), ("public.jpeg", false)] {
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, format as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, pixel, nil)
        precondition(CGImageDestinationFinalize(destination))
        let source = CGImageSourceCreateWithData(bytes, nil)!
        precondition(exactCompletePNG(source, bytes as Data) == expectedPNG)
    }
    print("PASS_CLASSIFICATION_AND_FORMAT_ONLY")
    exit(0)
}
guard args.count == 3, let duration = Double(args[2]), duration.isFinite,
      (1...30).contains(duration) else { fputs("usage: capture-observer DIRECTORY SECONDS\n", stderr); exit(2) }
let source = URL(fileURLWithPath: args[1], isDirectory: true).standardizedFileURL
let run = UUID().uuidString
func emit(_ kind: String, _ fields: [String: Any] = [:]) {
    var row = fields
    row["event"] = kind; row["runID"] = run
    row["clock"] = "hostSystemUptime"; row["uptime"] = ProcessInfo.processInfo.systemUptime
    row["captureCompletionMeasured"] = false
    print(String(decoding: try! JSONSerialization.data(withJSONObject: row, options: .sortedKeys), as: UTF8.self))
    fflush(stdout)
}
struct Signature: Equatable { let size: Int; let modified: Date }
func signatures() throws -> [URL: Signature] {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: Array(keys))
    var result: [URL: Signature] = [:]
    for file in files {
        let v = try file.resourceValues(forKeys: keys)
        if v.isRegularFile == true, let bytes = v.fileSize, let date = v.contentModificationDate {
            result[file] = Signature(size: bytes, modified: date)
        }
    }
    return result
}
func boundedData(_ file: URL, expectedSize: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 8_388_609), data.count == expectedSize else { return nil }
    return data
}
func opaqueID(_ file: URL) -> String { SHA256.hash(data: Data(file.path.utf8)).map { String(format: "%02x", $0) }.joined() }
var known: [URL: Signature]
do { known = try signatures() } catch { emit("source_unreadable"); exit(3) }
emit("observer_started", ["baselineFiles": known.count, "readOnly": true, "sourceOriginProven": false])
var previousWindowState = Data()
let deadline = ProcessInfo.processInfo.systemUptime + duration
while ProcessInfo.processInfo.systemUptime < deadline {
    let captureUIPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screencaptureui").map(\.processIdentifier))
    let rows = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { w -> [String: Any]? in
        let pid = w[kCGWindowOwnerPID as String] as? Int32 ?? -1
        guard let kind = category(owner: w[kCGWindowOwnerName as String] as? String ?? "", title: w[kCGWindowName as String] as? String ?? "", captureUIProcess: captureUIPIDs.contains(pid)) else { return nil }
        return ["category": kind, "pid": pid, "number": w[kCGWindowNumber as String] ?? -1,
                "bounds": w[kCGWindowBounds as String] ?? [:], "layer": w[kCGWindowLayer as String] ?? -1]
    }
    let state = try! JSONSerialization.data(withJSONObject: rows, options: .sortedKeys)
    if state != previousWindowState {
        let point = CGEvent(source: nil)?.location
        emit("capture_window_observation", ["windows": rows,
             "pointer": point.map { [$0.x, $0.y] } ?? [],
             "modifierFlags": CGEventSource.flagsState(.combinedSessionState).rawValue,
             "leftPressed": CGEventSource.buttonState(.combinedSessionState, button: .left),
             "selectionGeometryMeasured": false])
        previousWindowState = state
    }
    do {
        let current = try signatures()
        for (file, signature) in current where known[file] != signature {
            emit("source_file_change", ["sourceFileID": opaqueID(file), "bytes": signature.size, "firstReadableGloballyMeasured": false])
            if file.pathExtension.lowercased() == "png", signature.size <= 8_388_608,
               let data = boundedData(file, expectedSize: signature.size),
               let image = CGImageSourceCreateWithData(data as CFData, nil), exactCompletePNG(image, data),
               let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
               width > 0, height > 0, height <= 16_777_216, width <= 16_777_216 / height,
               let decoded = CGImageSourceCreateImageAtIndex(image, 0, nil) {
                emit("complete_png_observed", ["sourceFileID": opaqueID(file), "bytes": data.count,
                     "width": decoded.width, "height": decoded.height, "sourceOriginProven": false])
            }
        }
        known = current
    } catch { emit("source_read_failed"); exit(3) }
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
emit("observer_ended", ["readOnly": true])
