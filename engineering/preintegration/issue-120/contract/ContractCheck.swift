import Foundation
import RiftletCore

private struct FixtureProvider: ConversationProvider {
    let profile: ProviderProfile
    let httpsHosts: Set<String> = ["fixture.invalid"]
    func classify(_ url: URL) -> DraftRoute? {
        guard url.path == "/draft", url.query == nil, url.fragment == nil else { return nil }
        return DraftRoute(identity: url.path, surface: "ordinary-chat", mode: "fixture")
    }
}

@main enum ContractCheck {
    static func main() throws {
        let profile = try ProviderProfile(id: "fixture", revision: 1, program: Data("fixture-v1".utf8))
        let provider = FixtureProvider(profile: profile)
        let url = URL(string: "https://fixture.invalid/draft")!
        let matched = try resolveProvider(url, among: [provider])
        precondition(matched.profile == profile)
        for text in ["http://fixture.invalid/draft", "https://user@fixture.invalid/draft",
                     "https://fixture.invalid:444/draft", "https://fixture.invalid.example/draft",
                     "https://fixture.invalid/library", "https://fixture.invalid/draft?mode=other",
                     "https://fixture.invalid/draft#workspace"] {
            precondition((try? resolveProvider(URL(string: text)!, among: [provider])) == nil)
        }
        precondition((try? resolveProvider(url, among: [provider, provider])) == nil)
        let other = try ProviderProfile(id: "fixture", revision: 1, program: Data("changed".utf8))
        precondition(profile != other)
        print("PASS isolated Swift contract: exact route, source digest, ambiguous receiver and unsupported surfaces")
    }
}
