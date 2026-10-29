import Foundation
import CoreGraphics
import CoreFoundation
import Darwin

/// These are observed Screenshot.app metadata values, not a public Apple API contract.
/// Unknown values never acquire guessed geometry.
public enum ScreenshotCaptureKind: String, Sendable {
    case selection, window, display
}

/// An untrusted geometry candidate read from the ORIGINAL file, never the private copy.
/// The empirical metadata convention is Quartz global coordinates: origin at the
/// primary display's upper-left, y increasing downwards, in logical screen units.
/// Only the resolver may convert it to an AppKit rectangle.
public struct ScreenshotSourceMetadata: Equatable, Sendable {
    public let captureKind: ScreenshotCaptureKind
    public let quartzRect: CGRect

    public init(captureKind: ScreenshotCaptureKind, quartzRect: CGRect) {
        self.captureKind = captureKind
        self.quartzRect = quartzRect
    }
}

public enum ScreenshotSourceFailure: String, Error, Equatable, Sendable {
    case unreadableSource, sourceChanged, notScreenshot
    case missingRectangle, malformedRectangle, missingCaptureKind, unsupportedCaptureKind
    case invalidDisplayGeometry, ambiguousDisplay, outsideDisplay, crossDisplay
    case mirroredDisplay, pixelScaleMismatch, displayCaptureMismatch
}

/// Optional, process-local observations in the host system-uptime clock domain.
/// These are observed upper bounds, not Screenshot.app completion time or the
/// earliest instant the original file could have been read. Never persisted or
/// reconstructed from file dates, an old asset, or a recovery journal.
public struct ScreenshotSourceTiming: Equatable, Sendable {
    /// When this collector first retained the candidate during this process.
    /// Nil for a pending handoff, whose original observation may predate restart.
    public let firstObservedUptime: TimeInterval?
    /// Complete copy/hash, source identity/metadata rechecks and image inspection
    /// have all passed. Includes copying, private-file fsync and decoding work.
    public let validatedCopyUptime: TimeInterval
    /// QueueStore's original import has returned after its durable transaction.
    public let durableCommitUptime: TimeInterval
}

/// Ephemeral decoration input. This value owns no asset, queue, upload or retry state.
/// Created after a durable import; reading it is optional and may happen off the UI actor.
/// Its full source signature rejects replacement OR in-place edits since the import.
public struct ScreenshotSourceObservation: Sendable {
    public let assetID: UUID
    public let readyUptime: TimeInterval
    public let sourceTiming: ScreenshotSourceTiming?
    private let sourceURL: URL
    private let signature: FileSignature

    init(url: URL, signature: FileSignature, assetID: UUID,
         readyUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
         sourceTiming: ScreenshotSourceTiming? = nil) {
        sourceURL = url
        self.signature = signature
        self.assetID = assetID
        self.readyUptime = readyUptime
        self.sourceTiming = sourceTiming
    }

    public func readMetadata() -> Result<ScreenshotSourceMetadata, ScreenshotSourceFailure> {
        ScreenshotSourceMetadataReader.read(at: sourceURL, expectedSignature: signature)
    }
}

public enum ScreenshotSourceMetadataReader {
    public static let rectangleAttribute = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"
    public static let kindAttribute = "com.apple.metadata:kMDItemScreenCaptureType"
    private static let maximumAttributeBytes = 4_096

    static func read(at url: URL, expectedSignature: FileSignature)
        -> Result<ScreenshotSourceMetadata, ScreenshotSourceFailure> {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return .failure(.unreadableSource) }
        defer { Darwin.close(descriptor) }
        guard let before = try? FileSignature.read(descriptor: descriptor), before == expectedSignature else {
            return .failure(.sourceChanged)
        }
        guard (try? CaptureSource.isScreenshot(descriptor: descriptor)) == true else {
            return .failure(.notScreenshot)
        }
        let rectangle = readAttribute(descriptor, name: rectangleAttribute)
        let kind = readAttribute(descriptor, name: kindAttribute)
        guard (try? FileSignature.read(descriptor: descriptor)) == expectedSignature,
              (try? FileSignature.read(at: url)) == expectedSignature,
              (try? CaptureSource.isScreenshot(descriptor: descriptor)) == true else {
            return .failure(.sourceChanged)
        }
        // A second bounded read also rejects metadata-only changes, which do not
        // necessarily alter the file's mtime/size signature.
        guard rectangle == readAttribute(descriptor, name: rectangleAttribute),
              kind == readAttribute(descriptor, name: kindAttribute) else {
            return .failure(.sourceChanged)
        }
        return decode(rectangleData: rectangle, captureKindData: kind)
    }

    /// Strict plist parsing. In particular, a one-number legacy attribute, boolean
    /// array, numeric string, NSRect string or comma-separated text is not a rect.
    static func decode(rectangleData: Data?, captureKindData: Data?)
        -> Result<ScreenshotSourceMetadata, ScreenshotSourceFailure> {
        guard let rectangleData else { return .failure(.missingRectangle) }
        guard !rectangleData.isEmpty, rectangleData.count <= maximumAttributeBytes,
              let object = try? PropertyListSerialization.propertyList(from: rectangleData, options: [], format: nil),
              let array = object as? [Any], array.count == 4 else { return .failure(.malformedRectangle) }
        var values: [Double] = []
        for item in array {
            guard let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else { return .failure(.malformedRectangle) }
            values.append(number.doubleValue)
        }
        guard values[2] > 0, values[3] > 0 else { return .failure(.malformedRectangle) }
        let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        guard finitePositive(rect) else { return .failure(.malformedRectangle) }
        guard let captureKindData else { return .failure(.missingCaptureKind) }
        guard !captureKindData.isEmpty, captureKindData.count <= maximumAttributeBytes,
              let object = try? PropertyListSerialization.propertyList(from: captureKindData, options: [], format: nil),
              let name = object as? String,
              let kind = ScreenshotCaptureKind(rawValue: name) else { return .failure(.unsupportedCaptureKind) }
        return .success(ScreenshotSourceMetadata(captureKind: kind, quartzRect: rect))
    }

    private static func readAttribute(_ descriptor: Int32, name: String) -> Data? {
        let count = fgetxattr(descriptor, name, nil, 0, 0, 0)
        guard count > 0, count <= maximumAttributeBytes else { return nil }
        var bytes = Data(count: count)
        let read = bytes.withUnsafeMutableBytes { fgetxattr(descriptor, name, $0.baseAddress, count, 0, 0) }
        return read == count ? bytes : nil
    }
}

/// Snapshot from a single display-enumeration boundary. Geometry must be refreshed
/// when screens/backing scales change, and an active animation must then be cancelled.
public struct ScreenshotDisplayGeometry: Equatable, Sendable {
    public let id: UInt32
    public let quartzBounds: CGRect
    public let appKitFrame: CGRect
    public let backingScale: Double
    public let isMirrored: Bool

    public init(id: UInt32, quartzBounds: CGRect, appKitFrame: CGRect,
                backingScale: Double, isMirrored: Bool = false) {
        self.id = id
        self.quartzBounds = quartzBounds
        self.appKitFrame = appKitFrame
        self.backingScale = backingScale
        self.isMirrored = isMirrored
    }
}

public struct ScreenshotSourceGeometry: Equatable, Sendable {
    public let appKitRect: CGRect
    public let displayID: UInt32
    public let backingScale: Double
}

public enum ScreenshotSourceGeometryResolver {
    /// Conservative same-display conversion. No image-to-screen inference, cursor
    /// fallback, width-only scale guess, clipping or spanning-display path exists.
    /// A window shadow/padding mismatch safely disables decoration for that file.
    /// These checks establish internal consistency, not validation of an OS release's
    /// undocumented metadata convention; that still requires real capture samples.
    public static func resolve(_ metadata: ScreenshotSourceMetadata,
                               pixelWidth: Int, pixelHeight: Int,
                               displays: [ScreenshotDisplayGeometry], targetDisplayID: UInt32)
        -> Result<ScreenshotSourceGeometry, ScreenshotSourceFailure> {
        let rect = metadata.quartzRect
        guard finitePositive(rect) else { return .failure(.malformedRectangle) }
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth <= 50_000, pixelHeight <= 50_000 else {
            return .failure(.pixelScaleMismatch)
        }
        guard !displays.isEmpty, Set(displays.map(\.id)).count == displays.count,
              displays.allSatisfy({ display in
                  finitePositive(display.quartzBounds) && finitePositive(display.appKitFrame)
                  && display.backingScale.isFinite && display.backingScale >= 1 && display.backingScale <= 4
                  && abs(display.quartzBounds.width - display.appKitFrame.width) <= 0.01
                  && abs(display.quartzBounds.height - display.appKitFrame.height) <= 0.01
              }) else { return .failure(.invalidDisplayGeometry) }
        let containing = displays.filter { $0.quartzBounds.contains(rect) }
        guard !containing.isEmpty else { return .failure(.outsideDisplay) }
        guard containing.count == 1 else { return .failure(.ambiguousDisplay) }
        let display = containing[0]
        guard !display.isMirrored else { return .failure(.mirroredDisplay) }
        // Overlapping desktop rectangles are ambiguous even if only one completely
        // contains the screenshot. Edge contact with a neighbor is harmless.
        guard !displays.contains(where: { candidate in
            guard candidate.id != display.id else { return false }
            let overlap = candidate.quartzBounds.intersection(rect)
            return !overlap.isNull && overlap.width > 0 && overlap.height > 0
        }) else { return .failure(.ambiguousDisplay) }
        guard display.id == targetDisplayID else { return .failure(.crossDisplay) }
        let scale = display.backingScale
        guard abs(rect.width * scale - Double(pixelWidth)) <= 1,
              abs(rect.height * scale - Double(pixelHeight)) <= 1 else {
            return .failure(.pixelScaleMismatch)
        }
        if metadata.captureKind == .display {
            guard abs(rect.minX - display.quartzBounds.minX) <= 0.01,
                  abs(rect.minY - display.quartzBounds.minY) <= 0.01,
                  abs(rect.width - display.quartzBounds.width) <= 0.01,
                  abs(rect.height - display.quartzBounds.height) <= 0.01 else {
                return .failure(.displayCaptureMismatch)
            }
        }
        // Convert through the containing display, not NSScreen.main (which follows
        // keyboard focus). This handles negative X and screens above/below primary.
        let converted = CGRect(
            x: display.appKitFrame.minX + rect.minX - display.quartzBounds.minX,
            y: display.appKitFrame.maxY - (rect.maxY - display.quartzBounds.minY),
            width: rect.width, height: rect.height)
        guard finitePositive(converted), display.appKitFrame.contains(converted) else {
            return .failure(.invalidDisplayGeometry)
        }
        return .success(ScreenshotSourceGeometry(appKitRect: converted, displayID: display.id,
                                                backingScale: display.backingScale))
    }
}

private func finitePositive(_ rect: CGRect) -> Bool {
    rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
    && rect.size.width > 0 && rect.size.height > 0 && rect.minX.isFinite && rect.maxX.isFinite
    && rect.minY.isFinite && rect.maxY.isFinite
}
