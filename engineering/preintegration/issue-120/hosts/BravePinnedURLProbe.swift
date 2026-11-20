// Link with the debug RiftletAdapters and RiftletCore objects on macOS.
// Both endpoints belong to this windowless process. No browser or profile is opened.
import AppKit
import Carbon
@testable import RiftletAdapters

private func code(_ s: String) -> OSType { s.utf8.reduce(0) { ($0 << 8) | OSType($1) } }

private func object(_ type: String, id: String, parent: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
    let spec = NSAppleEventDescriptor.record()
    spec.setDescriptor(.init(typeCode: code(type)), forKeyword: code("want"))
    spec.setDescriptor(.init(enumCode: code("ID  ")), forKeyword: code("form"))
    spec.setDescriptor(.init(string: id), forKeyword: code("seld"))
    spec.setDescriptor(parent, forKeyword: code("from"))
    guard let absolute = spec.coerce(toDescriptorType: typeObjectSpecifier) else { throw BindingError.targetChanged }
    return absolute
}

@MainActor private final class Fixture: NSObject {
    private(set) var reads = 0

    @objc func getURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        reads += 1
        let property = event.paramDescriptor(forKeyword: keyDirectObject)
        let target = property?.forKeyword(code("from")).flatMap { ChromeActiveTabDescriptor.identity(in: $0) }
        let addressedOriginal = property?.forKeyword(code("want"))?.typeCodeValue == code("prop") &&
            property?.forKeyword(code("seld"))?.typeCodeValue == code("URL ") &&
            target?.window == "11" && target?.tab == "22"
        reply.setParam(.init(string: addressedOriginal ? "https://original.test/22" : "https://other.test/33"),
                       forKeyword: keyDirectObject)
    }
}

@main struct BravePinnedURLProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let receiver = Fixture()
        DispatchQueue.main.async {
            NSAppleEventManager.shared().setEventHandler(receiver, andSelector: #selector(Fixture.getURL(_:reply:)),
                                                         forEventClass: kAECoreSuite, andEventID: kAEGetData)
            DispatchQueue.global().async {
                do {
                    let tab = try object("CrTb", id: "22", parent: object("cwin", id: "11"))
                    let url = try BraveBrowserHost.readOriginalURL(tab, pid: getpid(), deadline: ChromeClickDeadline())
                    let expired = ChromeClickDeadline(start: ProcessInfo.processInfo.systemUptime - 1)
                    do {
                        _ = try BraveBrowserHost.readOriginalURL(tab, pid: getpid(), deadline: expired)
                        exit(3)
                    } catch WebAdapterError.nativeEventFailed(let status) where status == errAETimeout {}
                    DispatchQueue.main.async {
                        guard url == "https://original.test/22", receiver.reads == 1 else { exit(4) }
                        print("originalWindowAndTab=true ownProcessNativeReads=1 expiredReadBlocked=true")
                        exit(0)
                    }
                } catch {
                    print("fixture failed:", error)
                    exit(5)
                }
            }
        }
        withExtendedLifetime(receiver) { app.run() }
    }
}
