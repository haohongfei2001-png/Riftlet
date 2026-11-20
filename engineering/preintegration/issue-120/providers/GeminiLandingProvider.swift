import Foundation

/// A URL can nominate only the inspected /app landing surface. This isolated
/// provider has a read-only page program and no IndependentFileInputAdapter.
struct GeminiLandingProvider: ConversationProvider {
    let profile: ProviderProfile
    let httpsHosts: Set<String> = ["gemini.google.com"]

    init(inspector: Data) throws {
        profile = try ProviderProfile(id: "gemini", revision: 1, program: inspector)
    }

    func classify(_ url: URL) -> DraftRoute? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.percentEncodedHost?.lowercased() == "gemini.google.com",
              parts.port == nil, parts.user == nil, parts.password == nil, parts.percentEncodedPath == "/app",
              parts.percentEncodedQuery == nil, parts.percentEncodedFragment == nil else { return nil }
        return DraftRoute(identity: "/app", surface: "public-landing", mode: "unverified")
    }
}
