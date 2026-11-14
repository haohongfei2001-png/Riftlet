import AppKit
import DiskArbitration

enum InstallerDiskImage {
    private static let continuedBuildKey = "Riftlet.installerDiskImage.continuedBuild"

    static func matches(app: URL, volumeRoot: URL?, volumeName: String?, readOnly: Bool?, diskModel: (URL) -> String? = deviceModel) -> Bool {
        guard readOnly == true, volumeName == "Riftlet", let volumeRoot,
              app.lastPathComponent == "Riftlet.app",
              app.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path ==
                volumeRoot.resolvingSymlinksInPath().standardizedFileURL.path else { return false }
        // This is the Applications link shipped alongside the app on the release DMG.
        let link = volumeRoot.appendingPathComponent("Applications")
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == "/Applications"
            && diskModel(volumeRoot) == "Disk Image"
    }

    private static func deviceModel(for volume: URL) -> String? {
        guard let session = DASessionCreate(nil),
              let disk = DADiskCreateFromVolumePath(nil, session, volume as CFURL),
              let description = DADiskCopyDescription(disk) as NSDictionary? else { return nil }
        return description[kDADiskDescriptionDeviceModelKey] as? String
    }

    /// Called once, after winning the instance lock and before starting any product services.
    @MainActor static func revealForInstallationIfRequested(mode: ApplicationMode) -> Bool {
        let bundle = Bundle.main
        let app = bundle.bundleURL
        guard mode == .capture, !OrdinaryCaptureConfiguration.isInternalAcceptance,
              !CommandLine.arguments.contains("--acceptance-trace"),
              bundle.bundleIdentifier == "com.riftlet.app",
              let channel = bundle.object(forInfoDictionaryKey: "RiftletBuildChannel") as? String,
              ["release", "release-candidate"].contains(channel),
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              UserDefaults.standard.string(forKey: continuedBuildKey) != build,
              let volume = try? app.resourceValues(forKeys: [.volumeURLKey, .volumeNameKey, .volumeIsReadOnlyKey]),
              matches(app: app, volumeRoot: volume.allValues[.volumeURLKey] as? URL,
                      volumeName: volume.volumeName, readOnly: volume.volumeIsReadOnly) else { return false }

        let alert = NSAlert()
        alert.messageText = "安装 Riftlet"
        alert.informativeText = "你正在从安装盘运行 Riftlet。在访达中将 Riftlet 拖到旁边的「应用程序」文件夹，再从那里打开，即可在 App 内安装后续更新。"
        alert.addButton(withTitle: "在访达中显示并退出")
        alert.addButton(withTitle: "继续使用").keyEquivalent = "\u{1B}"
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "")
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(build, forKey: continuedBuildKey)
            return false
        default:
            return false
        }
    }
}
