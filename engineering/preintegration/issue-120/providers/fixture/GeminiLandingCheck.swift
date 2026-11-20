import Foundation

@main enum GeminiLandingCheck {
    static func main() throws {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let provider = try GeminiLandingProvider(inspector: bytes)
        let normal = try resolveProvider(URL(string: "https://gemini.google.com/app")!, among: [provider])
        precondition(normal.profile == provider.profile && normal.route.mode == "unverified")
        for address in ["http://gemini.google.com/app", "https://gemini.google.com.evil.invalid/app",
                        "https://user@gemini.google.com/app", "https://gemini.google.com:444/app",
                        "https://gemini.google.com/app?mode=canvas", "https://gemini.google.com/app#chat",
                        "https://gemini.google.com/gems/create", "https://gemini.google.com/app/thread"] {
            precondition((try? resolveProvider(URL(string: address)!, among: [provider])) == nil)
        }
        print("PASS: frozen ConversationProvider and public landing read-only resource")
    }
}
