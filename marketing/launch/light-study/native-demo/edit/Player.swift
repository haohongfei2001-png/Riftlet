import AVFoundation
import CoreImage
import Foundation
import ImageIO
import QuartzCore

// Plays only the local input URL. No window, display capture or audio output.
struct Receipt: Encodable {
    let completed: Bool
    let endNotification: Bool
    let duration: Double
    let playWallSeconds: Double
    let firstDisplayTime: Double?
    let lastDisplayTime: Double?
    let displaySamples: Int
    let largestDisplayGap: Double
    let sampledSeconds: Int
    let jpegErrors: Int
    let failure: String?
}

func jpeg(_ buffer: CVPixelBuffer, to url: URL, using context: CIContext) -> Bool {
    let input = CIImage(cvPixelBuffer: buffer)
    guard let output = context.createCGImage(input, from: input.extent),
          let writer = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(writer, output, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
    return CGImageDestinationFinalize(writer)
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: Player movie.mp4 frame-directory\n", stderr)
    exit(64)
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let item = AVPlayerItem(url: source)
let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
output.suppressesPlayerRendering = true
item.add(output)
let player = AVPlayer(playerItem: item)
player.isMuted = true
player.volume = 0
player.automaticallyWaitsToMinimizeStalling = false
let context = CIContext(options: [.useSoftwareRenderer: true])
let start = CACurrentMediaTime()
var began: Double?
var duration = 0.0
var ended = false
var failure: String?
var first: Double?
var last: Double?
var samples = 0
var saved = Set<Int>()
var maxGap = 0.0
var jpegErrors = 0
var lastBuffer: CVPixelBuffer?
let endObserver = NotificationCenter.default.addObserver(
    forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: nil
) { _ in ended = true }
let failObserver = NotificationCenter.default.addObserver(
    forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: nil
) { _ in failure = "AVPlayer item failed before end" }

while !ended && failure == nil {
    let now = CACurrentMediaTime()
    if item.status == .failed {
        failure = item.error?.localizedDescription ?? "AVPlayerItemStatusFailed"
        break
    }
    if item.status == .readyToPlay && began == nil {
        duration = item.duration.seconds
        guard duration.isFinite && duration > 0 else {
            failure = "invalid player duration"
            break
        }
        began = now
        player.playImmediately(atRate: 1.0)
    }
    if began == nil && now - start > 12 {
        failure = "player not ready within 12 seconds"
        break
    }
    if let began = began, now - began > duration + 12 {
        failure = "player did not reach end"
        break
    }
    let request = output.itemTime(forHostTime: now)
    if request.isValid && output.hasNewPixelBuffer(forItemTime: request) {
        var display = CMTime.invalid
        if let buffer = output.copyPixelBuffer(forItemTime: request, itemTimeForDisplay: &display) {
            let stamp = display.seconds
            if stamp.isFinite && stamp >= 0 {
                if first == nil { first = stamp }
                if let last = last { maxGap = max(maxGap, stamp - last) }
                last = stamp
                samples += 1
                lastBuffer = buffer
                let second = Int(stamp.rounded(.down))
                if saved.insert(second).inserted {
                    let name = String(format: "%04d.jpg", second)
                    if !jpeg(buffer, to: directory.appendingPathComponent(name), using: context) { jpegErrors += 1 }
                }
            }
        }
    }
    _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.008))
}
let wall = CACurrentMediaTime() - (began ?? start)
if let buffer = lastBuffer {
    if !jpeg(buffer, to: directory.appendingPathComponent("last.jpg"), using: context) { jpegErrors += 1 }
}
player.pause()
NotificationCenter.default.removeObserver(endObserver)
NotificationCenter.default.removeObserver(failObserver)
if errorFromMissingCoverage() { failure = failure ?? "incomplete on-clock display coverage" }
let receipt = Receipt(completed: ended && failure == nil, endNotification: ended,
                      duration: duration, playWallSeconds: wall, firstDisplayTime: first,
                      lastDisplayTime: last, displaySamples: samples, largestDisplayGap: maxGap,
                      sampledSeconds: saved.count, jpegErrors: jpegErrors, failure: failure)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(receipt)
try data.write(to: directory.appendingPathComponent("player.json"), options: .atomic)
exit(receipt.completed ? 0 : 1)

func errorFromMissingCoverage() -> Bool {
    guard let first = first, let last = last, jpegErrors == 0 else { return true }
    return first > 0.5 || duration - last > 0.5 || maxGap > 1.1 || wall + 0.35 < duration
}
