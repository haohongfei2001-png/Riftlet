import Foundation

/// Route nomination and the page resource share one immutable manifest. The
/// private profile type intentionally has no website write-recipe field.
struct Issue120ProviderCatalog: Sendable {
    private let entries: [Entry]
    var providers: [any ConversationProvider] { entries }

    init() throws {
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let directory = Bundle.main.resourceURL,
                  let embedded = Bundle(url: directory.appendingPathComponent("Riftlet_RiftletAdapters.bundle"))
            else { throw BindingError.invalidProfile }
            resources = embedded
        } else {
            resources = Bundle.module
        }
        guard let definitions = resources.url(forResource: "issue120-provider-profiles", withExtension: "json"),
              let resource = resources.url(forResource: "issue120-provider-runtime", withExtension: "js")
        else { throw BindingError.invalidProfile }
        try self.init(manifest: Data(contentsOf: definitions), runtime: String(contentsOf: resource, encoding: .utf8))
    }

    private init(manifest: Data, runtime: String) throws {
        let specs = try JSONDecoder().decode([Definition].self, from: manifest)
        guard Set(specs.map(\.id)).count == specs.count, !specs.isEmpty, !runtime.isEmpty else {
            throw BindingError.invalidProfile
        }
        entries = try specs.map { spec in
            guard let host = URLComponents(string: spec.origin)?.host,
                  spec.origin == "https://" + host, !spec.paths.isEmpty,
                  spec.paths.allSatisfy({ $0.hasPrefix("/") }), !spec.editor.isEmpty else {
                throw BindingError.invalidProfile
            }
            let program = try Self.bind(runtime: runtime, definition: spec)
            let profile = try ProviderProfile(id: spec.id, revision: spec.revision, program: Data(program.utf8))
            return Entry(profile: profile, httpsHosts: [host], paths: Set(spec.paths), program: program)
        }
    }

    /// Both the bundle loader and isolated host tests bind a program as exact
    /// UTF-8 bytes before hashing. No runtime parameter can replace a profile.
    static func bind<D: Encodable>(runtime: String, definition: D) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let argument = String(decoding: try encoder.encode(definition), as: UTF8.self)
        return "(" + runtime + ")(" + argument + ")"
    }

    /// An expression returning the API for this exact revision and resource digest.
    func program(for profile: ProviderProfile) throws -> String {
        guard let entry = entries.first(where: { $0.profile == profile }) else { throw BindingError.invalidProfile }
        return entry.program
    }

    private struct Definition: Codable {
        let id: String
        let revision: Int
        let origin: String
        let paths: [String]
        let editor: String
        let action: String?
    }

    private struct Entry: ConversationProvider {
        let profile: ProviderProfile
        let httpsHosts: Set<String>
        let paths: Set<String>
        let program: String

        func classify(_ url: URL) -> DraftRoute? {
            guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.scheme?.lowercased() == "https", let host = parts.percentEncodedHost?.lowercased(),
                  httpsHosts.contains(host), parts.port == nil || parts.port == 443,
                  parts.user == nil, parts.password == nil,
                  parts.percentEncodedQuery == nil, parts.percentEncodedFragment == nil else { return nil }
            let path = parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath
            guard paths.contains(path) else { return nil }
            return DraftRoute(identity: path, surface: "unverified-entry", mode: "unverified")
        }
    }
}
