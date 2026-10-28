// Standalone macOS measurement probe; never linked into Riftlet.
// Build: swiftc -parse-as-library -O scripts/benchmark-builtin-capture.swift -o /tmp/riftlet-capture-benchmark
// Run:   /tmp/riftlet-capture-benchmark --self-check
//        /tmp/riftlet-capture-benchmark [--iterations 5] [--display-index 1] [--output report.json]
// Full desktop capture additionally requires --allow-desktop-capture. CI must omit it.
// Optional --retain-synthetic-images NEW_DIR keeps sanitized previews only after
// complete synthetic-pixel validation; full-display images are never retained.
// No TCC prompt, permission bypass, private window enumeration output, private image artifact,
// application launch, system setting change, upload or message is performed.
import AppKit
import CoreGraphics
import CoreVideo
import CryptoKit
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

private enum ProbeError: Error { case arguments, unsafeOutput, process, invalidPNG, resourceBound, noImage, fixtureChanged }

private struct Options {
    var iterations = 5
    var displayIndex = 1
    var desktopOptIn = false
    var selfCheck = false
    var output: URL?
    var retainSyntheticImages: URL?

    init(_ arguments: [String]) throws {
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "--self-check": selfCheck = true
            case "--allow-desktop-capture": desktopOptIn = true
            case "--iterations", "--display-index", "--output", "--retain-synthetic-images":
                let key = arguments[i]; i += 1
                guard i < arguments.count else { throw ProbeError.arguments }
                if key == "--output" { output = URL(fileURLWithPath: arguments[i]) }
                else if key == "--retain-synthetic-images" { retainSyntheticImages = URL(fileURLWithPath: arguments[i], isDirectory: true) }
                else {
                    guard let n = Int(arguments[i]) else { throw ProbeError.arguments }
                    if key == "--iterations" { guard (1...30).contains(n) else { throw ProbeError.arguments }; iterations = n }
                    else { guard (1...32).contains(n) else { throw ProbeError.arguments }; displayIndex = n }
                }
            default: throw ProbeError.arguments
            }
            i += 1
        }
    }
}

private func milliseconds(_ start: TimeInterval) -> Double { (ProcessInfo.processInfo.systemUptime - start) * 1_000 }
private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func rectValues(_ rect: CGRect) -> [Double] { [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)] }
private func number(_ value: CGFloat) -> String {
    var result = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    while result.hasSuffix("0") { result.removeLast() }
    if result.hasSuffix(".") { result.removeLast() }
    return result
}
private func rectangleArgument(_ rect: CGRect) -> String { [rect.minX, rect.minY, rect.width, rect.height].map(number).joined(separator: ",") }
private func median(_ values: [Double]) -> Any {
    guard !values.isEmpty else { return NSNull() }
    let sorted = values.sorted(), center = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[center - 1] + sorted[center]) / 2 : sorted[center]
}

private func memory() -> [String: Any] {
    var usage = rusage(), children = rusage()
    _ = getrusage(RUSAGE_SELF, &usage)
    _ = getrusage(RUSAGE_CHILDREN, &children)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    var result: [String: Any] = ["processPeakResidentBytes": usage.ru_maxrss,
        "childrenPeakResidentBytesCumulative": children.ru_maxrss,
        "scope": "Darwin bytes; process lifetime peaks, NOT per-backend isolated peaks; children cumulative"]
    if status == KERN_SUCCESS { result["residentBytes"] = UInt64(info.resident_size) }
    else { result["residentBytes"] = NSNull() }
    return result
}

private func encodePNG(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ProbeError.invalidPNG }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ProbeError.invalidPNG }
    return data as Data
}

private func rawPNGMetadata(_ data: Data) throws -> [String: Any] {
    guard data.count >= 33, data.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) else { throw ProbeError.invalidPNG }
    func uint32(_ offset: Int) -> Int {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }
    guard String(data: data[12..<16], encoding: .ascii) == "IHDR", uint32(8) == 13 else { throw ProbeError.invalidPNG }
    var record: [String: Any] = ["width": uint32(16), "height": uint32(20), "bitDepth": Int(data[24]),
        "colorType": Int(data[25]), "interlace": Int(data[28]), "rawPNGBytes": data.count, "rawPNGSHA256": sha256(data)]
    var offset = 8, chunks: [String] = []
    while offset <= data.count - 12 {
        let length = uint32(offset)
        guard length >= 0, length <= data.count - offset - 12 else { throw ProbeError.invalidPNG }
        let typeData = data[(offset + 4)..<(offset + 8)]
        guard typeData.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
              let type = String(data: typeData, encoding: .ascii) else { throw ProbeError.invalidPNG }
        chunks.append(type)
        if type == "iCCP" { record["embeddedICCChunkSHA256"] = sha256(data.subdata(in: (offset + 8)..<(offset + 8 + length))) }
        offset += length + 12
        if type == "IEND" { break }
    }
    guard chunks.last == "IEND", offset == data.count else { throw ProbeError.invalidPNG }
    record["chunkTypes"] = chunks
    record["embeddedICC"] = chunks.contains("iCCP")
    record["embeddedSRGBChunk"] = chunks.contains("sRGB")
    return record
}

private func colorSpaceLabel(_ space: CGColorSpace?) -> String {
    guard let space, let name = space.name else { return "UNNAMED_OR_MISSING" }
    let known: [(CFString, String)] = [(CGColorSpace.sRGB, "sRGB"), (CGColorSpace.displayP3, "DisplayP3"),
        (CGColorSpace.extendedSRGB, "extendedSRGB"), (CGColorSpace.linearSRGB, "linearSRGB"),
        (CGColorSpace.genericRGBLinear, "genericRGBLinear")]
    return known.first(where: { CFEqual(name, $0.0) })?.1 ?? "OTHER_PROFILE_NAME_REDACTED"
}

private let fixtureColors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]]

private struct Inspection { var record: [String: Any]; let safePreview: Data? }

private func inspectPNG(_ data: Data, fixtureSize: CGSize?, fixtureScale: CGFloat = 1,
                        localRect: CGRect?, retainSynthetic: Bool = false) throws -> Inspection {
    var record = try rawPNGMetadata(data)
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(source) == 1,
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ProbeError.invalidPNG }
    let w = image.width, h = image.height
    guard w > 0, h > 0, w <= 16_384, h <= 16_384, Int64(w) * Int64(h) <= 64_000_000 else { throw ProbeError.resourceBound }
    record["decodedWidth"] = w; record["decodedHeight"] = h
    record["decodedBitsPerComponent"] = image.bitsPerComponent
    record["decodedBitsPerPixel"] = image.bitsPerPixel
    record["colorSpace"] = colorSpaceLabel(image.colorSpace)
    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
        if let value = properties[kCGImagePropertyDPIWidth] as? NSNumber { record["dpiWidth"] = value }
        if let value = properties[kCGImagePropertyDPIHeight] as? NSNumber { record["dpiHeight"] = value }
    }
    // A separate bounded sRGB decode is for comparison only. Original PNG bytes
    // are never changed or retained as an artifact; this is not HDR fidelity proof.
    var rgba = Data(count: w * h * 4)
    try rgba.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw ProbeError.noImage }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    record["comparisonSRGBA8SHA256"] = sha256(rgba)
    record["comparisonSpace"] = "sRGB RGBA8; diagnostic conversion only, not product output"
    var preview: Data?
    if let fixtureSize, let localRect {
        let fixtureWidth = fixtureSize.width
        var matches = 0
        for fraction in [CGFloat(0.125), 0.375, 0.625, 0.875] {
            let x = min(w - 1, Int(CGFloat(w) * fraction)), y = h / 2
            let band = min(3, max(0, Int((localRect.minX + localRect.width * fraction) / fixtureWidth * 4)))
            let expected = fixtureColors[band], start = (y * w + x) * 4
            if (0..<3).allSatisfy({ abs(Int(rgba[start + $0]) - Int(expected[$0])) <= 12 }) && rgba[start + 3] >= 250 { matches += 1 }
        }
        record["fixtureColorCanary"] = matches == 4 ? "MATCH" : "MISMATCH"
        record["fixtureCanaryMatches"] = matches
        record["fixtureCanaryMeaning"] = "Four interior synthetic color samples; not full pixel/DPI/occlusion acceptance"
        func syntheticPixelsMatch(flipY: Bool) -> Bool {
            for row in 0..<h {
                let y = flipY ? h - 1 - row : row
                let pointY = localRect.minY + (CGFloat(y) + 0.5) * localRect.height / CGFloat(h)
                for column in 0..<w {
                    let pointX = localRect.minX + (CGFloat(column) + 0.5) * localRect.width / CGFloat(w)
                    let expected: [UInt8]
                    if pointY < 16 || (32..<48).contains(pointY) {
                        expected = Int(floor(pointX * fixtureScale)).isMultiple(of: 2) ? [0, 0, 0] : [255, 255, 255]
                    } else {
                        let band = min(3, max(0, Int(pointX / fixtureWidth * 4)))
                        expected = fixtureColors[band]
                    }
                    let offset = (row * w + column) * 4
                    if rgba[offset + 3] != 255 || !(0..<3).allSatisfy({ rgba[offset + $0] == expected[$0] }) { return false }
                }
            }
            return true
        }
        // Exact color equality is required for retained previews; even a faint
        // foreign overlay must fail. Canary tolerance above is diagnostic only.
        // Both bitmap row conventions are accepted for privacy validation, not
        // as evidence that a backend's orientation/geometry is correct.
        let synthetic = syntheticPixelsMatch(flipY: false) || syntheticPixelsMatch(flipY: true)
        record["syntheticPixelValidation"] = synthetic ? "MATCH" : "MISMATCH_NO_IMAGE_RETAINED"
        if synthetic && retainSynthetic {
            preview = try rgba.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                    let image = context.makeImage() else { throw ProbeError.noImage }
                return try encodePNG(image)
            }
            record["previewMeaning"] = "Actual captured pixels, sanitized sRGB RGBA8 re-encode; NOT the original PNG or raw color-profile evidence"
            if let preview { record["previewSHA256"] = sha256(preview) }
        }
    } else {
        record["fixtureColorCanary"] = "NOT_APPLICABLE_DESKTOP"
        record["syntheticPixelValidation"] = "NOT_APPLICABLE_DESKTOP_NEVER_RETAINED"
    }
    return Inspection(record: record, safePreview: preview)
}

@MainActor private final class FixtureView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false
        for (index, color) in fixtureColors.enumerated() {
            NSColor(srgbRed: CGFloat(color[0]) / 255, green: CGFloat(color[1]) / 255,
                    blue: CGFloat(color[2]) / 255, alpha: 1).setFill()
            NSBezierPath(rect: CGRect(x: CGFloat(index) * bounds.width / 4, y: 0, width: bounds.width / 4, height: bounds.height)).fill()
        }
        // Device-pixel strips at top 0...16 and 32...48 points let the
        // interior fractional region reveal a one-pixel horizontal shift.
        let pixel = 1 / max(1, window?.backingScaleFactor ?? 1)
        for column in 0..<Int(bounds.width / pixel) {
            (column.isMultiple(of: 2) ? NSColor.black : .white).setFill()
            for top in [CGFloat(0), 32] {
                NSBezierPath(rect: CGRect(x: CGFloat(column) * pixel, y: bounds.height - top - 16, width: pixel, height: 16)).fill()
            }
        }
    }
}

private struct Payload {
    let data: Data
    let captureMS: Double
    let pngMS: Double
    let boundary: String
    let memoryAfterCapture: [String: Any]
}

private final class ProbeResources: @unchecked Sendable {
    private let lock = NSLock()
    private var child: Process?
    private var stage: URL?
    private var completed = false
    func setStage(_ url: URL) { lock.lock(); stage = url; lock.unlock() }
    func setChild(_ process: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return false }; child = process; return true
    }
    func releaseChild(_ process: Process) { lock.lock(); if child === process { child = nil }; lock.unlock() }
    func claimCompletion() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return false }; completed = true; return true
    }
    func cleanup() {
        lock.lock(); let process = child, directory = stage; child = nil; stage = nil; lock.unlock()
        if let process, process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}

private func captureCLI(arguments: [String], stage: URL, resources: ProbeResources) async throws -> Payload {
    let url = stage.appendingPathComponent(UUID().uuidString + ".png")
    let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw ProbeError.unsafeOutput }
    Darwin.close(fd)
    defer { try? FileManager.default.removeItem(at: url) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-t", "png"] + arguments + [url.path]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    guard resources.setChild(process) else { throw ProbeError.process }
    defer { resources.releaseChild(process) }
    let timeout = DispatchWorkItem {
        if process.isRunning { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
    defer { timeout.cancel() }
    let start = ProcessInfo.processInfo.systemUptime
    let duration: Double = try await withCheckedThrowingContinuation { continuation in
        process.terminationHandler = { child in
            let duration = milliseconds(start)
            if child.terminationStatus == 0 { continuation.resume(returning: duration) }
            else { continuation.resume(throwing: ProbeError.process) }
        }
        do { try process.run() }
        catch { process.terminationHandler = nil; continuation.resume(throwing: ProbeError.process) }
    }
    let capturedMemory = memory(), readStart = ProcessInfo.processInfo.systemUptime
    var st = stat()
    guard lstat(url.path, &st) == 0, st.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          st.st_uid == geteuid(), st.st_size > 0, st.st_size <= 512 * 1_024 * 1_024,
          chmod(url.path, 0o600) == 0 else { throw ProbeError.invalidPNG }
    let data = try Data(contentsOf: url)
    return Payload(data: data, captureMS: duration, pngMS: milliseconds(readStart),
        boundary: "process launch through exit; includes PNG encoding/disk write; pngStageMS is file read", memoryAfterCapture: capturedMemory)
}

@available(macOS 14.0, *)
private func captureSCK(filter: SCContentFilter, rect: CGRect?, size: CGSize) async throws -> Payload {
    let config = SCStreamConfiguration()
    config.width = max(1, Int((size.width * CGFloat(filter.pointPixelScale)).rounded()))
    config.height = max(1, Int((size.height * CGFloat(filter.pointPixelScale)).rounded()))
    guard Int64(config.width) * Int64(config.height) <= 64_000_000 else { throw ProbeError.resourceBound }
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    if let rect { config.sourceRect = rect }
    let start = ProcessInfo.processInfo.systemUptime
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    let captureMS = milliseconds(start), capturedMemory = memory(), encodingStart = ProcessInfo.processInfo.systemUptime
    let data = try encodePNG(image)
    return Payload(data: data, captureMS: captureMS, pngMS: milliseconds(encodingStart),
        boundary: "SCScreenshotManager call to CGImage; pngStageMS separately encodes PNG", memoryAfterCapture: capturedMemory)
}

// The legacy API is a measurement reference only. It is never substituted via
// a private symbol lookup, and never changes the product's minimum OS version.
@available(macOS, introduced: 13.0, obsoleted: 15.0)
private func captureQuartz(windowID: CGWindowID?, rect: CGRect) throws -> Payload {
    let start = ProcessInfo.processInfo.systemUptime
    let image: CGImage?
    if let windowID {
        image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution])
    } else {
        image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    }
    guard let image else { throw ProbeError.noImage }
    guard image.width <= 16_384, image.height <= 16_384,
          Int64(image.width) * Int64(image.height) <= 64_000_000 else { throw ProbeError.resourceBound }
    let captureMS = milliseconds(start), capturedMemory = memory(), encodingStart = ProcessInfo.processInfo.systemUptime
    let data = try encodePNG(image)
    return Payload(data: data, captureMS: captureMS, pngMS: milliseconds(encodingStart),
        boundary: "CGWindowListCreateImage call to CGImage; pngStageMS separately encodes PNG", memoryAfterCapture: capturedMemory)
}

@MainActor private func fixtureIsVisible(_ window: NSWindow, quartzRect: CGRect) -> Bool {
    guard window.isVisible, window.isOpaque, window.alphaValue == 1,
          let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
    for row in rows {
        guard let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.intersects(quartzRect),
              ((row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0 else { continue }
        // Front-to-back order: any intersecting foreign window before our opaque
        // fixture vetoes a screen-region sample. No names or titles are retained.
        let own = (row[kCGWindowNumber as String] as? NSNumber)?.intValue == window.windowNumber
        return own && rect.contains(quartzRect)
    }
    return false
}

@MainActor private func run(_ options: Options, resources: ProbeResources) async -> [String: Any] {
    var report = baseReport(scope: "ACTUAL_API_CAPTURE_OF_CONTROLLED_SYNTHETIC_WINDOW")
    guard CGPreflightScreenCaptureAccess() else {
        report["status"] = "NOT_RUN"; report["reason"] = "SCREEN_CAPTURE_PERMISSION_NOT_ALREADY_GRANTED"
        report["permissionRequested"] = false; return report
    }
    let screens = NSScreen.screens
    guard options.displayIndex <= screens.count else {
        report["status"] = "NOT_RUN"; report["reason"] = "SELECTED_DISPLAY_NOT_AVAILABLE"; return report
    }
    let screen = screens[options.displayIndex - 1]
    guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
          screen.visibleFrame.width >= 256, screen.visibleFrame.height >= 224 else {
        report["status"] = "NOT_RUN"; report["reason"] = "DISPLAY_TOO_SMALL_OR_NO_ID"; return report
    }
    let size = CGSize(width: min(480, screen.visibleFrame.width - 64), height: min(320, screen.visibleFrame.height - 64))
    let frame = CGRect(x: floor(screen.visibleFrame.midX - size.width / 2), y: floor(screen.visibleFrame.midY - size.height / 2), width: size.width, height: size.height)
    let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = true; window.backgroundColor = .white; window.hasShadow = false
    window.level = .screenSaver; window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.contentView = FixtureView(frame: CGRect(origin: .zero, size: size))
    window.orderFrontRegardless(); window.displayIfNeeded()
    defer { window.close() }
    try? await Task.sleep(nanoseconds: 150_000_000)
    let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
    let windowQuartz = CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    let integral = CGRect(x: windowQuartz.minX + 32, y: windowQuartz.minY + 32, width: 128, height: 96)
    let fractional = CGRect(x: integral.minX + 0.5, y: integral.minY + 0.5, width: integral.width - 0.5, height: integral.height - 0.5)
    let displayQuartz = CGDisplayBounds(displayID)
    guard windowQuartz.insetBy(dx: 16, dy: 16).contains(integral), windowQuartz.insetBy(dx: 16, dy: 16).contains(fractional) else {
        report["status"] = "NOT_RUN"; report["reason"] = "REGION_NOT_STRICTLY_INSIDE_FIXTURE"; return report
    }
    report["display"] = ["ordinal": options.displayIndex, "connectedScreenCount": screens.count,
        "backingScale": Double(screen.backingScaleFactor), "quartzBounds": rectValues(displayQuartz),
        "isMirrored": CGDisplayIsInMirrorSet(displayID) != 0]
    report["fixturePointSize"] = [Double(size.width), Double(size.height)]
    report["desktopCaptureOptIn"] = options.desktopOptIn
    let stage = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-capture-benchmark-" + UUID().uuidString, isDirectory: true)
    do { try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
    catch { report["status"] = "ERROR"; report["reason"] = "PRIVATE_STAGING_UNAVAILABLE"; return report }
    resources.setStage(stage)
    defer { resources.cleanup() }
    if let directory = options.retainSyntheticImages {
        // A new directory avoids mixing this run with previous artifacts. No
        // full-display PNG is written here, even under desktop opt-in.
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            report["status"] = "ERROR"; report["reason"] = "SYNTHETIC_PREVIEW_DIRECTORY_MUST_BE_NEW"; return report
        }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { report["status"] = "ERROR"; report["reason"] = "SYNTHETIC_PREVIEW_DIRECTORY_UNAVAILABLE"; return report }
    }

    var content: SCShareableContent?
    if #available(macOS 14.0, *) {
        let start = ProcessInfo.processInfo.systemUptime
        content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        report["sckEnumerationMS"] = milliseconds(start)
        report["sckEnumerationStatus"] = content == nil ? "ERROR" : "COMPLETED"
    }
    let scWindow = content?.windows.first { $0.windowID == CGWindowID(window.windowNumber) && $0.owningApplication?.processID == getpid() }
    let scDisplay = content?.displays.first { $0.displayID == displayID }
    let variants: [(String, CGRect, CGRect?)] = [
        ("window-no-shadow", windowQuartz, CGRect(origin: .zero, size: size)),
        ("region-integral", integral, integral.offsetBy(dx: -windowQuartz.minX, dy: -windowQuartz.minY)),
        ("region-half-point", fractional, fractional.offsetBy(dx: -windowQuartz.minX, dy: -windowQuartz.minY)),
        ("full-selected-display", displayQuartz, nil)]
    var records: [[String: Any]] = [], summaries: [[String: Any]] = []
    for (kind, rect, localRect) in variants {
        for backend in ["screencapture", "SCScreenshotManager", "CoreGraphics-legacy"] {
            var skip: String?
            if kind == "full-selected-display" && !options.desktopOptIn { skip = "DESKTOP_CAPTURE_REQUIRES_EXPLICIT_OPT_IN" }
            if backend == "SCScreenshotManager" {
                if #available(macOS 14.0, *) {
                    if scWindow == nil || scDisplay == nil { skip = "OWN_FIXTURE_OR_DISPLAY_NOT_ENUMERATED" }
                } else { skip = "API_REQUIRES_MACOS_14" }
            }
            if backend == "CoreGraphics-legacy" {
                if #available(macOS 15.0, *) { skip = "LEGACY_API_REFERENCE_NOT_RUN_ON_MACOS_15_OR_LATER" }
            }
            if let skip {
                records.append(["backend": backend, "variant": kind, "status": "NOT_RUN", "reason": skip]); continue
            }
            var totals: [Double] = [], warmTotals: [Double] = []
            var firstTotal: Double?
            for sample in 0..<options.iterations {
                var entry: [String: Any] = ["backend": backend, "variant": kind, "sample": sample + 1,
                    "phase": sample == 0 ? "FIRST_VARIANT_CALL_IN_EXISTING_PROCESS" : "WARM_VARIANT_CALL",
                    "requestedQuartzPoints": rectValues(rect), "memoryBefore": memory()]
                let start = ProcessInfo.processInfo.systemUptime
                do {
                    guard CGPreflightScreenCaptureAccess() else { throw ProbeError.fixtureChanged }
                    if localRect != nil && !fixtureIsVisible(window, quartzRect: rect) { throw ProbeError.fixtureChanged }
                    let payload: Payload
                    switch backend {
                    case "screencapture":
                        let args = kind == "window-no-shadow" ? ["-o", "-l", String(window.windowNumber)] : ["-R", rectangleArgument(rect)]
                        payload = try await captureCLI(arguments: args, stage: stage, resources: resources)
                    case "SCScreenshotManager":
                        if #available(macOS 14.0, *), let scWindow, let scDisplay {
                            if kind == "window-no-shadow" {
                                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                                payload = try await captureSCK(filter: filter, rect: nil, size: filter.contentRect.size)
                            } else {
                                let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
                                // Display filters honor sourceRect; single-window filters do not.
                                let source = rect.offsetBy(dx: -displayQuartz.minX, dy: -displayQuartz.minY)
                                payload = try await captureSCK(filter: filter, rect: source, size: rect.size)
                            }
                        } else { throw ProbeError.noImage }
                    default:
                        if #available(macOS 15.0, *) { throw ProbeError.noImage }
                        else { payload = try captureQuartz(windowID: kind == "window-no-shadow" ? CGWindowID(window.windowNumber) : nil, rect: rect) }
                    }
                    let readyMS = milliseconds(start)
                    if localRect != nil && !fixtureIsVisible(window, quartzRect: rect) { throw ProbeError.fixtureChanged }
                    let inspection = try autoreleasepool { try inspectPNG(payload.data,
                        fixtureSize: localRect == nil ? nil : size, fixtureScale: screen.backingScaleFactor,
                        localRect: localRect, retainSynthetic: options.retainSyntheticImages != nil) }
                    if let directory = options.retainSyntheticImages, let preview = inspection.safePreview, localRect != nil {
                        let name = "\(backend)-\(kind)-\(sample + 1)-sanitized.png"
                        let destination = directory.appendingPathComponent(name)
                        let descriptor = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                        guard descriptor >= 0 else { throw ProbeError.unsafeOutput }
                        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                        try file.write(contentsOf: preview); try file.close()
                        entry["sanitizedSyntheticPreview"] = name
                    }
                    entry["status"] = "CAPTURED"
                    entry["captureMS"] = payload.captureMS; entry["pngStageMS"] = payload.pngMS
                    entry["captureBoundary"] = payload.boundary
                    entry["readyToInspectPNGMS"] = readyMS; entry["metadata"] = inspection.record
                    entry["memoryAfterCapture"] = payload.memoryAfterCapture
                    entry["memoryAfterInspection"] = memory()
                    totals.append(readyMS)
                    if sample == 0 { firstTotal = readyMS } else { warmTotals.append(readyMS) }
                } catch {
                    entry["status"] = "ERROR"
                    entry["reason"] = error is ProbeError ? String(describing: error).uppercased() : "CAPTURE_OR_ENCODE_REJECTED"
                    entry["elapsedMS"] = milliseconds(start)
                }
                records.append(entry)
            }
            summaries.append(["backend": backend, "variant": kind, "capturedSamples": totals.count,
                "firstReadyToInspectPNGMS": firstTotal.map { $0 as Any } ?? NSNull(),
                "warmMedianReadyToInspectPNGMS": median(warmTotals),
                "allMedianReadyToInspectPNGMS": median(totals)])
        }
    }
    report["status"] = "COMPLETED_MEASUREMENT_PROBE"
    report["samples"] = records; report["summaries"] = summaries
    report["sanitizedSyntheticImagesRetained"] = records.filter { $0["sanitizedSyntheticPreview"] != nil }.count
    report["memoryAfterAllSamples"] = memory()
    return report
}

private func baseReport(scope: String) -> [String: Any] {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return ["schemaVersion": 1, "scope": scope, "osVersion": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
        "permissionRequested": false, "rawImagesPersistedAsArtifacts": false,
        "previewPolicy": "Only optional fully validated synthetic pixels; sanitized sRGB PNG, never full-display bytes",
        "physicalMouseAcceptance": "NOT_RUN", "mixedScaleMultiDisplayAcceptance": "NOT_RUN",
        "HDRWideGamutAcceptance": "NOT_RUN", "realRiftletImportUploadAcceptance": "NOT_RUN",
        "latencyMeaning": "Tool/API + PNG boundary only. Not click-to-thumbnail, upload latency or fully cold system cache.",
        "fidelityMeaning": "Raw PNG metadata and diagnostic sRGB digest. SDR fixture does not prove HDR/wide-gamut correctness."]
}

private func selfCheck() throws -> [String: Any] {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: 16, height: 8, bitsPerComponent: 8, bytesPerRow: 64,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ProbeError.noImage }
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
    guard let image = context.makeImage() else { throw ProbeError.noImage }
    let png = try encodePNG(image), inspection = try inspectPNG(png, fixtureSize: nil, localRect: nil)
    guard inspection.record["width"] as? Int == 16, inspection.record["height"] as? Int == 8,
          rectangleArgument(CGRect(x: -100.5, y: 42.5, width: 128.5, height: 96.5)) == "-100.5,42.5,128.5,96.5",
          median([1, 4, 2, 3]) as? Double == 2.5 else { throw ProbeError.invalidPNG }
    var rejected = false
    do { _ = try rawPNGMetadata(Data(png.dropLast())) } catch { rejected = true }
    guard rejected, inspection.safePreview == nil else { throw ProbeError.invalidPNG }
    guard let fixture = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ProbeError.noImage }
    fixture.setShouldAntialias(false)
    for (band, color) in fixtureColors.enumerated() {
        fixture.setFillColor(red: CGFloat(color[0]) / 255, green: CGFloat(color[1]) / 255, blue: CGFloat(color[2]) / 255, alpha: 1)
        fixture.fill(CGRect(x: band * 16, y: 0, width: 16, height: 64))
    }
    for column in 0..<64 {
        fixture.setFillColor(gray: column.isMultiple(of: 2) ? 0 : 1, alpha: 1)
        for y in [16, 48] { fixture.fill(CGRect(x: column, y: y, width: 1, height: 16)) }
    }
    guard let synthetic = fixture.makeImage() else { throw ProbeError.noImage }
    let safe = try inspectPNG(encodePNG(synthetic), fixtureSize: CGSize(width: 64, height: 64),
        localRect: CGRect(x: 0, y: 0, width: 64, height: 64), retainSynthetic: true)
    guard safe.safePreview != nil, safe.record["syntheticPixelValidation"] as? String == "MATCH" else { throw ProbeError.invalidPNG }
    fixture.setFillColor(red: 1, green: 0, blue: 1, alpha: 1)
    fixture.fill(CGRect(x: 10, y: 2, width: 4, height: 4))
    guard let contaminated = fixture.makeImage() else { throw ProbeError.noImage }
    let unsafe = try inspectPNG(encodePNG(contaminated), fixtureSize: CGSize(width: 64, height: 64),
        localRect: CGRect(x: 0, y: 0, width: 64, height: 64), retainSynthetic: true)
    guard unsafe.safePreview == nil else { throw ProbeError.invalidPNG }
    var report = baseReport(scope: "OFFLINE_SYNTHETIC_SELF_CHECK_NO_APPKIT_NO_TCC")
    report["status"] = "PASS"; report["capture"] = "NOT_RUN"
    report["checks"] = ["PNG_ROUND_TRIP", "TRUNCATED_PNG_REJECTED", "FRACTIONAL_ARGUMENT_SERIALIZATION_ONLY", "MEDIAN", "JSON_SAFE_MEMORY", "SANITIZED_PREVIEW_PIXEL_ALLOWLIST", "OFF_FIXTURE_PIXEL_REJECTED"]
    report["memory"] = memory()
    return report
}

private func emit(_ report: [String: Any], options: Options) throws {
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    if let url = options.output {
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ProbeError.unsafeOutput }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data); try handle.close()
    }
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
}

@main private struct CaptureBenchmark {
    @MainActor static func main() {
        let options: Options
        do { options = try Options(Array(CommandLine.arguments.dropFirst())) }
        catch {
            fputs("Usage: riftlet-capture-benchmark [--self-check] [--iterations 1...30] [--display-index 1...32] [--output new-report.json] [--retain-synthetic-images NEW_DIR] [--allow-desktop-capture]\n", stderr)
            exit(2)
        }
        if options.selfCheck {
            do { try emit(selfCheck(), options: options); exit(0) }
            catch { fputs("Synthetic capture-probe self-check failed.\n", stderr); exit(1) }
        }
        // Preflight precedes NSApplication and SCShareableContent. A denied CI
        // runner produces an explicit NOT_RUN report without a permission prompt.
        guard CGPreflightScreenCaptureAccess() else {
            var report = baseReport(scope: "ACTUAL_API_CAPTURE_PROBE")
            report["status"] = "NOT_RUN"; report["reason"] = "SCREEN_CAPTURE_PERMISSION_NOT_ALREADY_GRANTED"
            do { try emit(report, options: options); exit(0) }
            catch { fputs("Capture-probe report could not be saved.\n", stderr); exit(1) }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let resources = ProbeResources()
        // An uncancellable framework callback cannot be bounded by a task group
        // (which waits for cancelled children). This process-level watchdog is
        // intentionally outside Swift concurrency and yields an honest timeout.
        let watchdog = DispatchWorkItem {
            guard resources.claimCompletion() else { return }
            resources.cleanup()
            var report = baseReport(scope: "ACTUAL_API_CAPTURE_PROBE")
            report["status"] = "INCOMPLETE_TIMEOUT"; report["reason"] = "PROBE_EXCEEDED_90_SECONDS"
            try? emit(report, options: options)
            exit(3)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)
        Task { @MainActor in
            let report = await run(options, resources: resources)
            guard resources.claimCompletion() else { return }
            watchdog.cancel(); resources.cleanup()
            do { try emit(report, options: options); exit(0) }
            catch { fputs("Capture-probe report could not be saved.\n", stderr); exit(1) }
        }
        app.run()
    }
}
