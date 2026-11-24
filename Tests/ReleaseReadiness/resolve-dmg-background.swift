// Resolve Finder's raw Alias record with macOS, with user interaction and new mounts disabled.
import AppKit
import CoreFoundation

let volume = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let alias = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
guard let data = CFURLCreateBookmarkDataFromAliasRecord(nil, alias as CFData)?.takeRetainedValue() else {
    exit(2)
}
var stale = false
let resolved = try URL(resolvingBookmarkData: data as Data, options: [.withoutUI, .withoutMounting],
                       relativeTo: volume, bookmarkDataIsStale: &stale)
let actual = resolved.resolvingSymlinksInPath().standardizedFileURL
let expected = volume.appendingPathComponent(".background/Install.tiff").resolvingSymlinksInPath().standardizedFileURL
guard actual == expected else { exit(3) }
guard let image = NSImage(contentsOf: actual), image.size == NSSize(width: 620, height: 328),
      image.representations.count == 2,
      image.representations.allSatisfy({ $0.size == image.size }),
      Set(image.representations.map { "\($0.pixelsWide)x\($0.pixelsHigh)" }) == ["620x328", "1240x656"]
else { exit(4) }
