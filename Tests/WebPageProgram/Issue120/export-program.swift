// Linked to the actual built RiftletAdapters and RiftletCore targets. This
// test-only exporter defines the loopback site's event and member contract.
import Foundation
@testable import RiftletAdapters

struct Fixture: Encodable {
    struct Recipe: Encodable {
        let events = "input-change"
        let lane = "section[aria-label=attachments]"
        let card = "article"
        let maxBytes = 65536
        let explicitFailure = "[role=alert][aria-label=\"Attachment failed\"]"
    }
    let origin: String
    let paths = ["/app"]
    let editor = "rich-textarea > .ql-editor[role=textbox][contenteditable=true]"
    let action = "simplified-input-menu gem-icon-button button"
    let recipe: Recipe?
}

let origin = CommandLine.arguments[1]
guard let local = URL(string: origin), local.host == "127.0.0.1", local.scheme == "http",
      let port = local.port, origin == "http://127.0.0.1:\(port)",
      let directory = Bundle.main.resourceURL,
      let resources = Bundle(url: directory.appendingPathComponent("Riftlet_RiftletAdapters.bundle")),
      let runtimeURL = resources.url(forResource: "issue120-provider-runtime", withExtension: "js")
else { fatalError("invalid loopback or missing compiled bundle") }

let catalog = try Issue120ProviderCatalog()
let profile = try resolveProvider(URL(string: "https://gemini.google.com/app")!, among: catalog.providers)
let production = try catalog.program(for: profile.profile)
let runtime = try String(contentsOf: runtimeURL, encoding: .utf8)
let readable = try Issue120ProviderCatalog.bind(runtime: runtime, definition: Fixture(origin: origin, recipe: nil))
let writable = try Issue120ProviderCatalog.bind(runtime: runtime, definition: Fixture(origin: origin, recipe: .init()))
print("const compiledProduction = () => " + production + ";\nconst compiledDiscovery = () => " + readable
      + ";\nconst compiledWriter = () => " + writable + ";")
