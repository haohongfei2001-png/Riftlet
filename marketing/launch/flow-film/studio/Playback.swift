import Foundation
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import QuartzCore

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: watch local-movie.mp4 observation-directory [interval-seconds]\n", stderr)
    exit(64)
}
let file = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = URL(fileURLWithPath: CommandLine.arguments[2])
let interval = CommandLine.arguments.count > 3 ? (Double(CommandLine.arguments[3]) ?? 0.4) : 0.4
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let stream = AVURLAsset(url:file)
let item = AVPlayerItem(asset:stream)
let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
item.add(output)
let player = AVPlayer(playerItem:item)
player.automaticallyWaitsToMinimizeStalling = false
// AVPlayer owns the movie and audio master clock. Mute the local speaker on
// the isolated session. Audio loudness is checked separately on the muxed AAC.
player.isMuted = true
let context = CIContext(options:[.useSoftwareRenderer:true])
let color = CGColorSpace(name:CGColorSpace.sRGB)!
var count = 0
var presented = 0
var startWall: Double?
var prevTime = -1.0
var nextGlimpse = 0.0
var finished = false
var statuses: [String] = []
let observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                       object:item,queue:.main) { _ in finished = true }
let startRequest = CACurrentMediaTime()
let clock = Timer.scheduledTimer(withTimeInterval:1/90,repeats:true) { _ in
    let wall = CACurrentMediaTime()
    let time = output.itemTime(forHostTime:wall)
    if item.status == .failed { print("FAILED ",String(describing:item.error)); finished=true; return }
    let status = "\(item.status.rawValue).\(player.timeControlStatus.rawValue).\(player.rate)"
    if statuses.last != status { statuses.append(status); print("state",status); fflush(stdout) }
    guard output.hasNewPixelBuffer(forItemTime:time) else { return }
    guard let pixels = output.copyPixelBuffer(forItemTime:time,itemTimeForDisplay:nil) else { return }
    let stamp = time.seconds
    if !stamp.isFinite || stamp < prevTime { return }
    presented += 1
    prevTime = stamp
    if startWall == nil { startWall=wall }
    if stamp + 0.01 >= nextGlimpse {
        let raw = CIImage(cvPixelBuffer:pixels)
        let s = min(1.0, 820.0 / max(raw.extent.width,raw.extent.height))
        let frame = raw.transformed(by:CGAffineTransform(scaleX:s,y:s))
        let target = directory.appendingPathComponent(String(format:"v%04d-%06.2f.jpg",count,stamp))
        do { try context.writeJPEGRepresentation(of:frame,to:target,colorSpace:color,
                                                 options:[kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption:0.86]) }
        catch { print("Image error",error) }
        nextGlimpse += interval
        count += 1
        print(String(format:"view %.3f, wall %.3f",stamp,wall-(startWall ?? wall))); fflush(stdout)
    }
}
player.playImmediately(atRate:1)
while !finished && CACurrentMediaTime()-startRequest<70 { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }
clock.invalidate()
NotificationCenter.default.removeObserver(observer)
let elapsed = CACurrentMediaTime() - (startWall ?? startRequest)
print("duration",item.duration.seconds,"time",player.currentTime().seconds,"wall",elapsed,
      "presented",presented,"observations",count,"ended",finished,"error",String(describing:item.error))
if count == 0 || item.error != nil || !finished { exit(2) }
