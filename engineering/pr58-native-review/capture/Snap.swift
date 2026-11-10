import AppKit
import ImageIO
import UniformTypeIdentifiers

let id=CGWindowID(CommandLine.arguments[1])!, pid=Int(CommandLine.arguments[2])!
let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String:Any]] ?? []
guard let v=windows.first, (v[kCGWindowOwnerPID as String] as? NSNumber)?.intValue==pid else {print("Missing owned window", id);exit(2)}
guard let im=CGWindowListCreateImage(.null,.optionIncludingWindow,id,[.boundsIgnoreFraming,.bestResolution]) else {print("No pixels",id, v[kCGWindowIsOnscreen as String] ?? "-",v[kCGWindowBounds as String] ?? "-");exit(3)}
let out=URL(fileURLWithPath:CommandLine.arguments[3])
let dest=CGImageDestinationCreateWithURL(out as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,im,nil);guard CGImageDestinationFinalize(dest) else{exit(4)}
