#!/usr/bin/env swift
// Read-only local Mac probe. No screenshot is taken, no shortcut is intercepted,
// no system preference is changed, no image/path/title is written to stdout.
// This standalone observer does NOT substitute for the product collector or its
// source-geometry validator. The requested poll interval is not a latency bound.
import AppKit
import Foundation
import ImageIO
import CoreFoundation
import Darwin

func output(_ record: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(record),
          let bytes = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
          let text = String(data: bytes, encoding: .utf8) else { return }
    print(text)
    fflush(stdout)
}

func rectangle(_ rect: CGRect) -> [Double] {
    [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
}

func usage() -> Never {
    fputs("Usage: swift scripts/arrival-source-probe.swift --file <new screenshot>\n" +
          "       swift scripts/arrival-source-probe.swift --watch <screenshot directory> [--seconds 30]\n" +
          "Output is local JSONL; it contains no image or source path.\n" +
          "Watch uses bounded 20 ms polling; it does not measure the product watcher or capture T0.\n", stderr)
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2, ["--file", "--watch"].contains(arguments[0]) else { usage() }
var duration: Double = 30
if arguments.count > 2 {
    guard arguments.count == 4, arguments[0] == "--watch", arguments[2] == "--seconds",
          let supplied = Double(arguments[3]), supplied >= 1, supplied <= 120, supplied.isFinite else { usage() }
    duration = supplied
}
let mode = arguments[0]
let sourceURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

let displays: [[String: Any]] = NSScreen.screens.compactMap { screen in
    guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
    return ["displayID": id, "quartzBounds": rectangle(CGDisplayBounds(id)),
            "appKitFrame": rectangle(screen.frame), "backingScale": Double(screen.backingScaleFactor),
            "isMirrored": CGDisplayIsInMirrorSet(id) != 0]
}
let preferenceObject = UserDefaults(suiteName: "com.apple.screencapture")?.object(forKey: "show-thumbnail")
let thumbnailPreference: Any
if let number = preferenceObject as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
    thumbnailPreference = number.boolValue
} else if preferenceObject == nil {
    thumbnailPreference = NSNull()
} else {
    thumbnailPreference = "UNRECOGNIZED"
}
output(["event": "probe_start", "schema": 1, "scope": "READ_ONLY_NATIVE_METADATA_PROBE",
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "startedUptime": ProcessInfo.processInfo.systemUptime,
        "captureTime": "NOT_OBSERVED", "productClickableUptime": "NOT_OBSERVED",
        "geometryAcceptance": "NOT_RUN", "mode": mode,
        "showThumbnailPreferenceRaw": thumbnailPreference,
        "preferenceMeaning": "Read-only empirical key; confirm current setting in Screenshot.app Options",
        "displays": displays])

func attribute(_ fd: Int32, _ name: String) -> Any? {
    let count = fgetxattr(fd, name, nil, 0, 0, 0)
    guard count > 0, count <= 4_096 else { return nil }
    var data = Data(count: count)
    guard data.withUnsafeMutableBytes({ fgetxattr(fd, name, $0.baseAddress, count, 0, 0) }) == count else { return nil }
    return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
}

func sameFile(_ a: stat, _ b: stat) -> Bool {
    a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size
    && a.st_birthtimespec.tv_sec == b.st_birthtimespec.tv_sec && a.st_birthtimespec.tv_nsec == b.st_birthtimespec.tv_nsec
    && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
}

func inspect(_ url: URL, index: Int) -> (record: [String: Any], complete: Bool) {
    var record: [String: Any] = ["event": "file_probe", "sample": index,
                               "observedUptime": ProcessInfo.processInfo.systemUptime]
    let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { record["readable"] = false; return (record, false) }
    defer { Darwin.close(fd) }
    var initial = stat()
    guard fstat(fd, &initial) == 0, initial.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
        record["regularFile"] = false; return (record, false)
    }
    record["bytes"] = initial.st_size
    record["fileBirthUnixSeconds"] = Double(initial.st_birthtimespec.tv_sec) + Double(initial.st_birthtimespec.tv_nsec) / 1_000_000_000
    record["birthTimeMeaning"] = "Filesystem birth time, NOT screenshot capture time"
    let marker = attribute(fd, "com.apple.metadata:kMDItemIsScreenCapture") as? NSNumber
    let isScreenshot = marker.map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
    record["isScreenshotMarker"] = isScreenshot
    if let captureKind = attribute(fd, "com.apple.metadata:kMDItemScreenCaptureType") as? String,
       ["selection", "window", "display"].contains(captureKind) {
        record["captureKind"] = captureKind
    } else { record["captureKind"] = "MISSING_OR_UNRECOGNIZED" }
    if let values = attribute(fd, "com.apple.metadata:kMDItemScreenCaptureGlobalRect") as? [Any] {
        record["rectangleElementCount"] = values.count
        let numbers = values.compactMap { value -> Double? in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else { return nil }
            return number.doubleValue
        }
        if values.count == 4, numbers.count == 4 { record["rawRectangle"] = numbers }
        else { record["rawRectangle"] = "MALFORMED_OR_LEGACY" }
    } else { record["rawRectangle"] = "MISSING_OR_UNRECOGNIZED" }

    var complete = false
    if let image = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
        let count = CGImageSourceGetCount(image)
        record["imageCount"] = count
        if let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any] {
            record["pixelWidth"] = properties[kCGImagePropertyPixelWidth]
            record["pixelHeight"] = properties[kCGImagePropertyPixelHeight]
        }
        if count == 1, CGImageSourceGetStatus(image) == .statusComplete,
           CGImageSourceGetStatusAtIndex(image, 0) == .statusComplete {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceShouldCacheImmediately: true]
            complete = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary) != nil
        }
    }
    var final = stat()
    var pathFinal = stat()
    let stable = fstat(fd, &final) == 0 && lstat(url.path, &pathFinal) == 0
        && sameFile(initial, final) && sameFile(initial, pathFinal)
    record["signatureStableDuringProbe"] = stable
    record["completeImageWith64pxDecode"] = complete
    record["geometryAcceptance"] = "NOT_RUN_COMPARE_RAW_RECT_WITH_ACTUAL_CAPTURE_REGION"
    return (record, complete && stable && isScreenshot)
}

if mode == "--file" {
    let result = inspect(sourceURL, index: 1)
    output(result.record)
    exit(result.complete ? 0 : 1)
}

let extensions = Set(["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"])
func candidates() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]).filter { extensions.contains($0.pathExtension.lowercased()) }
}
let existing: Set<URL>
var previousPollStarted = ProcessInfo.processInfo.systemUptime
do { existing = Set(try candidates()) }
catch { output(["event": "probe_error", "reason": "DIRECTORY_UNREADABLE"]); exit(1) }
struct Observation { let index: Int; let firstSeen: Double; var complete: Bool }
var observations: [URL: Observation] = [:]
let deadline = ProcessInfo.processInfo.systemUptime + duration
while ProcessInfo.processInfo.systemUptime < deadline {
    let pollStarted = ProcessInfo.processInfo.systemUptime
    guard let paths = try? candidates() else { output(["event": "probe_error", "reason": "DIRECTORY_UNREADABLE"]); exit(1) }
    for url in paths where !existing.contains(url) {
        if observations[url] == nil {
            guard observations.count < 100 else { continue }
            let index = observations.count + 1
            let firstSeen = ProcessInfo.processInfo.systemUptime
            observations[url] = Observation(index: index, firstSeen: firstSeen, complete: false)
            output(["event": "probe_first_seen", "sample": index, "uptime": firstSeen,
                    "requestedPollingIntervalMS": 20, "previousPollStartedUptime": previousPollStarted,
                    "currentPollStartedUptime": pollStarted,
                    "discoveryObservationGapMS": (firstSeen - previousPollStarted) * 1_000,
                    "meaning": "Probe discovery; NOT product watcher/capture time; scheduling and scan/decode work can exceed requested interval"])
        }
        guard var observation = observations[url], !observation.complete else { continue }
        var result = inspect(url, index: observation.index)
        if result.complete {
            result.record["probeFirstSeenToReadableMS"] = (ProcessInfo.processInfo.systemUptime - observation.firstSeen) * 1_000
            result.record["latencyMeaning"] = "Probe only; does not include unknown capture-to-file time or product import/clickability"
            output(result.record)
            observation.complete = true
            observations[url] = observation
        }
    }
    previousPollStarted = pollStarted
    usleep(20_000)
}
output(["event": "probe_end", "samples": observations.count,
        "readableCompleteSamples": observations.values.filter(\.complete).count,
        "captureTime": "NOT_OBSERVED", "productClickableUptime": "NOT_OBSERVED",
        "physicalScreenshotAcceptance": "NOT_RUN_UNTIL_OPERATOR_CORRELATES_ACTUAL_CAPTURES"])
