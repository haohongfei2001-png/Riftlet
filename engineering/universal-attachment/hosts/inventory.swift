import AppKit
import CryptoKit
import Foundation

// No app launch, activation, window enumeration, Automation request or AX read.
// Registry and direct bundle observations may refer to the same file via aliases.
let hosts: [(String, String, String)] = [
    ("Google Chrome", "com.google.Chrome", "Google Chrome"),
    ("Safari", "com.apple.Safari", "Safari"),
    ("Microsoft Edge", "com.microsoft.edgemac", "Microsoft Edge"),
    ("Firefox", "org.mozilla.firefox", "Firefox"),
    ("Brave", "com.brave.Browser", "Brave Browser"),
    ("Arc", "company.thebrowser.Browser", "Arc"),
    ("ChatGPT for Mac", "com.openai.chat", "ChatGPT"),
    ("Claude Desktop", "com.anthropic.claudefordesktop", "Claude"),
    ("ChatGPT-labelled Codex bundle", "com.openai.codex", "ChatGPT")
]
let workspace = NSWorkspace.shared
let fm = FileManager.default
let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
             fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]

func dictionary(_ bundle: Bundle) -> [String: Any] {
    guard let file = bundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String,
          file == (file as NSString).lastPathComponent,
          let resource = bundle.resourceURL?.appendingPathComponent(file),
          let bytes = try? Data(contentsOf: resource),
          let xml = try? XMLDocument(data: bytes, options: [.nodeLoadExternalEntitiesNever]) else {
        return ["status": "no-readable-declared-sdef"]
    }
    func has(_ xpath: String) -> Bool { (try? xml.nodes(forXPath: xpath).isEmpty == false) ?? false }
    return [
        "status": "inspected-declared-sdef",
        "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
        "declaresChromiumWindowAndTabIDs": has("//class[@code='cwin']/property[@name='id'][@code='ID  ']")
            && has("//class[@code='CrTb']/property[@name='id'][@code='ID  ']"),
        "declaresChromiumActiveTab": has("//class[@code='cwin']/property[@name='active tab'][@code='acTa']"),
        "declaresChromiumExecuteJavaScript": has("//command[@code='CrSuExJa']/parameter[@code='JvSc']"),
        "declaresSafariCurrentTab": has("//class-extension[@extends='window']/property[@name='current tab'][@code='cTab']"),
        "declaresSafariTabID": has("//class[@code='bTab']/property[@name='id']"),
        "declaresSafariTabIndex": has("//class[@code='bTab']/property[@name='index']"),
        "declaresSafariDoJavaScript": has("//command[@code='sfridojs']/parameter[@code='dcnm']")
    ]
}

let results: [[String: Any]] = hosts.map { name, id, app in
    let registered = workspace.urlsForApplications(withBundleIdentifier: id)
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }
    let direct = roots.map { $0.appendingPathComponent(app + ".app") }
    var copies = [[String: Any]]()
    var seen = Set<URL>()
    for url in registered + running.compactMap(\.bundleURL) + direct {
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier == id,
              seen.insert(url.resolvingSymlinksInPath().standardizedFileURL).inserted else { continue }
        let info = bundle.infoDictionary ?? [:]
        copies.append(["version": info["CFBundleShortVersionString"] as? String ?? "unknown",
                       "build": info["CFBundleVersion"] as? String ?? "unknown",
                       "declaredScripting": dictionary(bundle)])
    }
    return ["name": name, "bundleID": id, "registeredURLCount": registered.count,
            "runningCount": running.count, "bundles": copies]
}
let report: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                             "observedUTC": ISO8601DateFormatter().string(from: Date()),
                             "workspaceHasForegroundIdentity": workspace.frontmostApplication?.bundleIdentifier != nil,
                             "hosts": results]
let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(reportData)
FileHandle.standardOutput.write(Data([10]))
