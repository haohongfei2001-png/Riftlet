import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// WindowServer produces immutable CGImages. This handoff contains only those
/// already captured self-owned pixels, never an NSWindow or a mutable UI object.
private struct NativePNGImages: @unchecked Sendable {
    let image: CGImage
    let background: CGImage?
}

private struct NativePNGResult: Sendable {
    let bytes: Int
    let sha256: String
    let productDifferencePixels: Int?
    let processedOnMainThread: Bool
}

/// Immutable pixels and the original capture clock cross to the movie actor.
/// No AppKit view/window, mutable layer, or writer object crosses this boundary.
private struct NativeMovieFrame: @unchecked Sendable {
    let image: CGImage
    let captureUptime: TimeInterval
}

/// A helper-only recorder. It captures only the WindowServer IDs of windows
/// owned by this process. It never captures a display, another process, an
/// existing screenshot, or a production data directory, and never asks for TCC.
/// Capturing a synthetic native projection is not real input/upload acceptance.
@MainActor
final class NativeVisualEvidence {
    enum Failure: Error { case unsafeRequest, existingOutput, missingWindow, missingProductPixels, encoding }

    static var requested: Bool { CommandLine.arguments.contains("--export-native-evidence") }

    /// Read the actual AppKit policy. This never writes system preferences or
    /// changes how product controllers honor accessibility settings.
    static func systemAccessibilitySnapshot() -> [String: Bool] {
        let workspace = NSWorkspace.shared
        return ["reduceMotion": workspace.accessibilityDisplayShouldReduceMotion,
                "increaseContrast": workspace.accessibilityDisplayShouldIncreaseContrast,
                "reduceTransparency": workspace.accessibilityDisplayShouldReduceTransparency]
    }

    private let directory: URL
    private let source: String
    private let checkout: String
    private let singleWindow: Bool
    private let accessibilityAtStart: [String: Bool]
    private weak var backdrop: NSWindow?
    private var frames: [[String: Any]] = []
    private var events: [[String: Any]] = []
    private var captureUnavailable = false
    private var movieReport: [String: Any]?
    private let start = ProcessInfo.processInfo.systemUptime

    private struct NativeFrame {
        let image: CGImage
        let rect: CGRect
        let quartzRect: CGRect
        let backingScale: CGFloat
        let windowCount: Int
        let windowNumbers: [Int]
        let started: TimeInterval
        let ended: TimeInterval
    }

    init(backdrop: NSWindow) throws {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard args.contains("--visual-clean"),
              !args.contains(where: { $0.hasPrefix("--software-") || $0 == "--press-acceptance-asset" }),
              let path = value("--export-native-evidence"), path.hasPrefix("/"),
              let source = value("--evidence-source"), let checkout = value("--evidence-checkout"),
              [source, checkout].allSatisfy({ $0.count == 40 && $0.allSatisfy { "0123456789abcdef".contains($0) } }) else {
            throw Failure.unsafeRequest
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw Failure.unsafeRequest }
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw Failure.existingOutput }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        self.directory = directory; self.source = source; self.checkout = checkout
        self.singleWindow = args.contains("--visual-window")
        self.accessibilityAtStart = Self.systemAccessibilitySnapshot()
        self.backdrop = backdrop
    }

    func note(_ name: String, fields: [String: Any]) {
        let allowedNames: Set<String> = ["native_arrival_boundary", "native_presentation_boundary",
            "visual_synthetic_start_projection", "visual_synthetic_final_projection",
            "visual_timeline_started", "visual_timeline_finished", "synthetic_asset_ready",
            "synthetic_decoration_cancel", "native_evidence_preview_action", "native_evidence_history_selection",
            "native_evidence_feedback_records"]
        guard allowedNames.contains(name), events.count < 64 else { return }
        let allowedFields: Set<String> = ["phase", "boundaryUptime", "duration", "mode", "reason",
            "readyUptime", "sourceProvided", "physical", "accepted", "fixtureState", "fixtureSequence", "softwareSelection",
            "fixtureRecordCount", "fixtureStates", "bodyAndStateMatched", "expanded", "networkEnabled", "receiptEvidence"]
        var event = fields.filter { allowedFields.contains($0.key) }
        event["event"] = name; event["uptime"] = ProcessInfo.processInfo.systemUptime
        events.append(event)
    }

    /// Produces original WindowServer pixels. No resampling, cacheDisplay,
    /// layer.render, synthetic frame painting, or screenshot permission change.
    @discardableResult
    func capture(_ name: String) async throws -> Bool {
        guard let frame = try captureOwnedWindows() else {
            recordUnavailableFrame(name)
            return false
        }
        try await writePNG(frame, name: name)
        return true
    }

    private func captureOwnedWindows() throws -> NativeFrame? {
        guard let backdrop else { throw Failure.missingWindow }
        // orderedWindows is an AppleScript collection that excludes NSPanel.
        // Start with every visible self-owned window, then ask AppKit for its
        // real onscreen order. No other process's metadata or pixels are read.
        let allowed = Set(NSApp.windows.filter { $0.isVisible && $0.windowNumber > 0 }.map(\.windowNumber))
        var owned: [NSWindow] = []
        NSApp.enumerateWindows(options: .orderedFrontToBack) { window, _ in
            if allowed.contains(window.windowNumber) { owned.append(window) }
        }
        guard owned.count == allowed.count, Set(owned.map(\.windowNumber)) == allowed else { throw Failure.missingWindow }
        let selected = singleWindow ? owned.filter { $0 !== backdrop && $0.styleMask.contains(.titled) } : owned
        guard !selected.isEmpty, !singleWindow || selected.count == 1,
              singleWindow || (selected.contains(where: { $0 === backdrop }) && selected.count > 1) else { throw Failure.missingWindow }
        let appKitRect = singleWindow ? selected[0].frame : backdrop.frame
        guard appKitRect.width > 0, appKitRect.height > 0,
              let firstScreen = NSScreen.screens.first else { throw Failure.missingWindow }
        let windowIDs = try windowArray(selected)
        let quartzRect = CGRect(x: appKitRect.minX, y: firstScreen.frame.maxY - appKitRect.maxY,
                                width: appKitRect.width, height: appKitRect.height)
        let before = ProcessInfo.processInfo.systemUptime
        guard let image = CGImage(windowListFromArrayScreenBounds: quartzRect, windowArray: windowIDs,
                    imageOption: [.boundsIgnoreFraming, .bestResolution]), image.width > 0, image.height > 0 else {
            captureUnavailable = true
            return nil
        }
        return NativeFrame(image: image, rect: appKitRect, quartzRect: quartzRect,
            backingScale: (singleWindow ? selected[0] : backdrop).backingScaleFactor,
            windowCount: selected.count, windowNumbers: selected.map(\.windowNumber),
            started: before, ended: ProcessInfo.processInfo.systemUptime)
    }

    private func windowArray(_ windows: [NSWindow]) throws -> CFArray {
        guard let windowIDs = CFArrayCreateMutable(kCFAllocatorDefault, 0, nil) else { throw Failure.missingWindow }
        // Quartz expects scalar CGWindowID values in a CFArray with nil
        // callbacks, not CFNumber objects. These encoded values are never
        // dereferenced; every ID comes from this process's selected NSWindow.
        for window in windows {
            guard let windowID = CGWindowID(exactly: window.windowNumber),
                  windowID != kCGNullWindowID,
                  let scalar = UnsafeRawPointer(bitPattern: UInt(windowID)) else { throw Failure.missingWindow }
            CFArrayAppendValue(windowIDs, scalar)
        }
        return windowIDs
    }

    private func captureBackdrop(for frame: NativeFrame) throws -> CGImage {
        guard let backdrop,
              let background = CGImage(windowListFromArrayScreenBounds: frame.quartzRect,
                windowArray: try windowArray([backdrop]), imageOption: [.boundsIgnoreFraming, .bestResolution]) else {
            throw Failure.encoding
        }
        return background
    }

    nonisolated private static func productDifferencePixels(_ image: CGImage, background: CGImage) throws -> Int {
        guard background.width == image.width, background.height == image.height,
              background.bitsPerPixel == 32, image.bitsPerPixel == 32,
              background.bitsPerComponent == 8, image.bitsPerComponent == 8,
              background.bitmapInfo == image.bitmapInfo,
              let actualData = image.dataProvider?.data, let backgroundData = background.dataProvider?.data,
              CFDataGetLength(actualData) >= image.bytesPerRow * image.height,
              CFDataGetLength(backgroundData) >= background.bytesPerRow * background.height,
              let actual = CFDataGetBytePtr(actualData), let baseline = CFDataGetBytePtr(backgroundData) else {
            throw Failure.encoding
        }
        var difference = 0
        // Compare original pixels, without resizing or modifying either image.
        // A little capture dithering cannot turn an empty backdrop into a pass.
        for y in 0..<image.height {
            for x in 0..<image.width {
                let a = y * image.bytesPerRow + x * 4
                let b = y * background.bytesPerRow + x * 4
                if (0..<4).contains(where: { abs(Int(actual[a + $0]) - Int(baseline[b + $0])) > 8 }) {
                    difference += 1
                }
            }
        }
        guard difference >= 64 else { throw Failure.missingProductPixels }
        return difference
    }

    private func recordUnavailableFrame(_ name: String) {
        frames.append(["name": name, "status": "NOT_RUN", "reason": "ownWindowServerCaptureUnavailable",
                       "uptime": ProcessInfo.processInfo.systemUptime, "physicalInput": "NOT_RUN"])
    }

    nonisolated private static func encodePNG(_ images: NativePNGImages, file: URL) throws -> NativePNGResult {
        let onMainThread = Thread.isMainThread
        guard !onMainThread else { throw Failure.unsafeRequest }
        let difference = try images.background.map { try productDifferencePixels(images.image, background: $0) }
        guard !FileManager.default.fileExists(atPath: file.path),
              let target = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encoding
        }
        CGImageDestinationAddImage(target, images.image, nil)
        guard CGImageDestinationFinalize(target) else { throw Failure.encoding }
        let bytes = try Data(contentsOf: file)
        return NativePNGResult(bytes: bytes.count,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            productDifferencePixels: difference, processedOnMainThread: onMainThread)
    }

    private func writePNG(_ frame: NativeFrame, name: String) async throws {
        let image = frame.image
        let background: CGImage?
        if singleWindow { background = nil } else { background = try captureBackdrop(for: frame) }
        let images = NativePNGImages(image: image, background: background)
        let file = directory.appendingPathComponent(name + ".png")
        // Await exactly one background job before capturing the next frame.
        // Heavy original-pixel comparison/PNG encoding/hash work must not block
        // AppKit's run loop or compete with Core Animation completion delivery.
        let encoded = try await Task.detached(priority: .utility) {
            try Self.encodePNG(images, file: file)
        }.value
        try Task.checkCancellation()
        var result: [String: Any] = [
            "name": name, "file": file.lastPathComponent, "status": "CAPTURED_NATIVE_WINDOWSERVER",
            "method": "CGImage(windowListFromArrayScreenBounds:windowArray:imageOption:); only NSApp-owned windows",
            "captureStartedUptime": frame.started, "captureEndedUptime": frame.ended,
            "elapsedSeconds": frame.started - start, "pixels": [image.width, image.height],
            "points": [frame.rect.width, frame.rect.height],
            "pixelScaleX": CGFloat(image.width) / frame.rect.width,
            "pixelScaleY": CGFloat(image.height) / frame.rect.height,
            "backingScaleFactor": frame.backingScale,
            "resized": false, "source": source, "checkout": checkout,
            "bytes": encoded.bytes, "sha256": encoded.sha256,
            "pngProcessingOnMainThread": encoded.processedOnMainThread,
            "pngProcessing": "One awaited background task; immutable original self-window image pair",
            "selectedOwnWindowCount": frame.windowCount,
            "ownWindowNumbersFrontToBack": frame.windowNumbers,
            "windowOrdering": "NSApplication.enumerateWindows(orderedFrontToBack)",
            "productWindowCount": frame.windowCount - (singleWindow ? 0 : 1),
            "syntheticOnly": true, "receiptEvidence": false, "physicalInput": "NOT_RUN"
        ]
        if let difference = encoded.productDifferencePixels {
            result["productDifferencePixelCount"] = difference
            result["minimumProductDifferencePixels"] = 64
            result["productPixelComparison"] = "original own-window composite versus original opaque own backdrop; channel delta > 8"
        }
        frames.append(result)
    }

    func recordTimeline() async throws {
        let zero = ProcessInfo.processInfo.systemUptime
        // Real captured frames at measured times. Capture/PNG overhead is part
        // of this observation and is not a frame-rate or latency benchmark.
        let hasArrival = CommandLine.arguments.contains("--visual-magnet")
            || CommandLine.arguments.contains("--visual-missing-source")
        let swallow: Double = hasArrival ? 4.5 : 3.5
        let times = [0.7, 1.9, 2.04, 2.14, 2.24, 2.34, 2.46, 2.60, 2.85]
            + [swallow - 0.04, swallow + 0.03, swallow + 0.07, swallow + 0.12,
               swallow + 0.22, swallow + 0.45, swallow + 1.82]
        let deadline = zero + min(6.45, (times.last ?? 6.2) + 0.12)
        var nextCapture = zero
        var keyframe = 0
        var captureCount = 0
        var recorder: NativeMovieRecorder?
        // One current CGImage plus a maximum of three pooled encoder buffers.
        // A late deadline is skipped, never filled with an interpolated frame.
        while ProcessInfo.processInfo.systemUptime < deadline && captureCount < 200 {
            let remaining = nextCapture - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            try Task.checkCancellation()
            if ProcessInfo.processInfo.systemUptime >= deadline { break }
            guard let native = try captureOwnedWindows() else {
                recordUnavailableFrame("timeline")
                break
            }
            captureCount += 1
            if recorder == nil && movieReport == nil {
                do {
                    let candidate = NativeMovieRecorder(directory: directory,
                        contentWidth: native.image.width, contentHeight: native.image.height,
                        firstCaptureUptime: native.started)
                    try await candidate.prepare()
                    recorder = candidate
                } catch NativeMovieRecorder.Failure.processingOnMainThread {
                    movieReport = ["status": "NOT_RUN", "reason": "nativeMovieProcessingOnMainThread",
                                   "movieProcessingOnMainThread": true]
                } catch {
                    movieReport = ["status": "NOT_RUN", "reason": "nativeMovieEncoderUnavailable"]
                }
            }
            // One awaited actor call per captured frame: no encoder backlog,
            // interpolation, or extra UI-thread pixel copies.
            await recorder?.append(NativeMovieFrame(image: native.image, captureUptime: native.started))
            let elapsed = native.started - zero
            if keyframe < times.count && elapsed >= times[keyframe] {
                // Do not duplicate one late capture under multiple timestamps.
                while keyframe + 1 < times.count && elapsed >= times[keyframe + 1] { keyframe += 1 }
                try await writePNG(native, name: String(format: "frame-%02d", keyframe))
                keyframe += 1
            }
            let after = ProcessInfo.processInfo.systemUptime - zero
            nextCapture = zero + (floor(after * 30) + 1) / 30
        }
        if let recorder {
            // Serialized immutable data is Sendable; mutable AV objects and
            // untyped dictionaries stay confined to the movie actor.
            let movieData = await recorder.finish()
            movieReport = (try? JSONSerialization.jsonObject(with: movieData)) as? [String: Any]
                ?? ["status": "NOT_RUN", "reason": "nativeMovieReportUnavailable"]
            if captureUnavailable {
                movieReport = ["status": "NOT_RUN", "reason": "nativeCaptureIntervalIncomplete",
                               "encodedFrameCount": movieReport?["encodedFrameCount"] ?? 0]
            }
            movieReport?["nativeCaptureCount"] = captureCount
            movieReport?["completeCaptureInterval"] = !captureUnavailable
            movieReport?["source"] = source; movieReport?["checkout"] = checkout
        } else if movieReport == nil {
            movieReport = ["status": "NOT_RUN", "reason": "ownWindowServerCaptureUnavailable"]
        }
        try finish()
    }

    func finish(failure: String? = nil) throws {
        var report: [String: Any] = [
            "schemaVersion": 1, "status": failure != nil ? "FAIL" : (captureUnavailable ? "NOT_RUN" : "CAPTURED_NATIVE_WINDOWSERVER"),
            "source": source, "checkout": checkout,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "appearance": NSApp.effectiveAppearance.name.rawValue,
            "captureKind": singleWindow ? "single-product-window" : "owned-product-composite",
            "systemAccessibilityAtStart": accessibilityAtStart,
            "systemAccessibilityAtEnd": Self.systemAccessibilitySnapshot(),
            "helperReducedMotionOverride": CommandLine.arguments.contains("--visual-reduced-motion"),
            "syntheticOnly": true, "fixtureLayerIsolation": true,
            "otherApplicationPixelsCaptured": false, "screenCapturePermissionRequested": false,
            "physicalInput": "NOT_RUN", "realScreenshot": "NOT_RUN", "realUpload": "NOT_RUN",
            "crossApplicationFocus": "NOT_RUN", "productionWindowOrder": "NOT_RUN",
            "performanceBenchmark": false, "frameTiming": "Measured capture timestamps; variable cadence; capture overhead included",
            "visualVerdict": "REQUIRES_INDEPENDENT_REVIEW", "frames": frames, "events": events
        ]
        if let movieReport { report["movie"] = movieReport }
        if let failure { report["failure"] = failure }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("capture.json"), options: .atomic)
    }
}

/// A real-time, bounded native-frame encoder. Presentation timestamps come
/// from actual WindowServer capture calls; missed or backpressured frames are
/// omitted. This records observation overhead, not physical/performance proof.
/// All mutable AV state is confined to this one serial actor. Its initializer
/// stores only values; preparation, pixel copies, append, finish and hashing
/// execute in awaited actor calls, never in the UI capture operation.
private actor NativeMovieRecorder {
    enum Failure: Error { case unsupportedEncoder, processingOnMainThread }
    private let url: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let width: Int
    private let height: Int
    private let contentWidth: Int
    private let contentHeight: Int
    private let origin: TimeInterval
    private var times: [Double] = []
    private var dropped = 0
    private var failure: String?
    private var processingOnMainThread = false

    init(directory: URL, contentWidth: Int, contentHeight: Int, firstCaptureUptime: TimeInterval) {
        self.contentWidth = contentWidth; self.contentHeight = contentHeight
        // H.264 encoders require even dimensions. At most one black edge pixel
        // is added; the original image is drawn 1:1 and never resized/cropped.
        width = contentWidth + contentWidth % 2; height = contentHeight + contentHeight % 2
        origin = firstCaptureUptime
        url = directory.appendingPathComponent("native-motion.mov")
    }

    private func observeBackgroundProcessing() -> Bool {
        let onMainThread = Thread.isMainThread
        processingOnMainThread = processingOnMainThread || onMainThread
        return !onMainThread
    }

    func prepare() throws {
        guard observeBackgroundProcessing() else { throw Failure.processingOnMainThread }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.unsupportedEncoder }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(12_000_000, max(2_000_000, width * height * 2)),
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        guard writer.canAdd(input) else { throw Failure.unsupportedEncoder }
        writer.add(input)
        guard writer.startWriting() else { throw Failure.unsupportedEncoder }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer; self.input = input; self.adaptor = adaptor
    }

    func append(_ frame: NativeMovieFrame) {
        guard observeBackgroundProcessing() else { failure = "nativeMovieProcessingOnMainThread"; return }
        guard failure == nil, times.count < 200 else { return }
        guard let writer, let input, let adaptor else { failure = "nativeMovieNotPrepared"; return }
        let image = frame.image
        guard image.width == contentWidth, image.height == contentHeight else {
            failure = "nativeWindowGeometryChanged"; writer.cancelWriting(); return
        }
        guard writer.status == .writing else { failure = "nativeMovieWriterStopped"; return }
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { dropped += 1; return }
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 3] as CFDictionary
        let allocation = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, attributes, &buffer)
        guard allocation == kCVReturnSuccess, let buffer else { dropped += 1; return }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { dropped += 1; return }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            dropped += 1; return
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        let elapsed = max(0, frame.captureUptime - origin)
        guard times.last.map({ elapsed > $0 }) ?? true else { dropped += 1; return }
        if adaptor.append(buffer, withPresentationTime: CMTime(seconds: elapsed, preferredTimescale: 1_000_000)) {
            times.append(elapsed)
        } else {
            failure = "nativeMovieAppendFailed"; writer.cancelWriting()
        }
    }

    private func reportData(_ fields: [String: Any]) -> Data {
        var report = fields
        report["movieProcessingOnMainThread"] = processingOnMainThread
        report["movieProcessing"] = "One serial actor; every immutable native frame append awaited"
        return (try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]))
            ?? Data(#"{"status":"NOT_RUN","reason":"nativeMovieReportUnavailable"}"#.utf8)
    }

    func finish() async -> Data {
        guard observeBackgroundProcessing() else {
            return reportData(["status": "NOT_RUN", "reason": "nativeMovieProcessingOnMainThread"])
        }
        guard let writer, let input else {
            return reportData(["status": "NOT_RUN", "reason": "nativeMovieNotPrepared"])
        }
        if failure == nil && !times.isEmpty && writer.status == .writing {
            input.markAsFinished()
            writer.finishWriting { }
            // Encoder completion is bounded separately from the <=6.45s scene.
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while writer.status == .writing && ProcessInfo.processInfo.systemUptime < deadline {
                try? await Task.sleep(nanoseconds: 25_000_000)
                guard observeBackgroundProcessing() else {
                    return reportData(["status": "NOT_RUN", "reason": "nativeMovieProcessingOnMainThread"])
                }
            }
        }
        guard failure == nil, times.count >= 2, writer.status == .completed else {
            if writer.status == .writing { writer.cancelWriting() }
            return reportData(["status": "NOT_RUN", "reason": failure ?? "nativeMovieDidNotComplete",
                    "encodedFrameCount": times.count, "backpressureOrAllocationDrops": dropped])
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            var size = 0
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                hash.update(data: chunk); size += chunk.count
            }
            return reportData(["status": "RECORDED_NATIVE_WINDOWSERVER", "file": url.lastPathComponent,
                "bytes": size, "sha256": hash.finalize().map { String(format: "%02x", $0) }.joined(),
                "codec": "H.264 in QuickTime MOV; lossy video encoding, original PNGs retained",
                "contentPixels": [contentWidth, contentHeight], "encodedPixels": [width, height],
                "paddingPixels": [width - contentWidth, height - contentHeight], "contentResized": false,
                "targetFrameRate": 30, "encodedFrameCount": times.count,
                "presentationSeconds": times, "firstCaptureUptime": origin,
                "backpressureOrAllocationDrops": dropped, "maximumPoolBuffers": 3,
                "timestamps": "Actual capture monotonic time relative to first capture; no interpolated/duplicate frames",
                "syntheticOnly": true, "receiptEvidence": false, "physicalInput": "NOT_RUN",
                "performanceBenchmark": false])
        } catch {
            return reportData(["status": "NOT_RUN", "reason": "nativeMovieDigestUnavailable"])
        }
    }
}
