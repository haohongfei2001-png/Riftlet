import Foundation
import RiftletCore

/// Select immutable packaged code for the provider identified by the native
/// host. The script and the host both check the original route.
public enum ConversationPagePrograms {
    public static let sourceID = "conversation-provider-20261125-v1"

    private static let programs: [ConversationProvider: WebPageProgram] = {
        guard let bundle = try? ChatGPTWebPageProgram.resourceBundle(),
              let url = bundle.url(forResource: "conversation-providers", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        let parts = source.components(separatedBy: "\n  // RIFTLET_CLICK_PIN_END\n")
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return [:] }
        struct Route: Encodable {
            let id: String
            let adapterID: String
            let origins: [String]
            let routes: [String]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var result: [ConversationProvider: WebPageProgram] = [:]
        for provider in ConversationProvider.allCases where provider != .chatgpt {
            let route = Route(id: provider.rawValue, adapterID: provider.adapterID, origins: provider.origins, routes: provider.routes)
            guard let data = try? encoder.encode(route), let json = String(data: data, encoding: .utf8) else { continue }
            func wrap(_ body: String) -> String {
                "function(command,native){return (\(body)\n)(command,native,\(json));}"
            }
            let pin = wrap(parts[0] + "\n  return 'refused';\n}")
            let full = wrap(source)
            guard pin.utf8.count < 20 * 1024, full.utf8.count <= ChatGPTWebPageProgram.maximumSourceBytes else { continue }
            result[provider] = WebPageProgram(sourceID: sourceID, functionSource: full, maximumChunkBytes: 256 * 1024,
                inputDiscoveryTimeout: 3, pinSource: pin, provider: provider, includesConversationProviders: true)
        }
        return result
    }()

    static func program(for provider: ConversationProvider) throws -> WebPageProgram {
        guard let program = programs[provider] else { throw WebAdapterError.programUnavailable }
        return program
    }

    public static func observationProfile(for provider: ConversationProvider) -> ObservationProfile {
        ObservationProfile(adapterID: provider.adapterID, surface: .webChat,
            profileID: provider.adapterID + "-draft-v1", uploadStartProfileID: provider.adapterID + "-file-accepted-v1")
    }
}
