import Foundation

/// Display copy follows the preferred supported language; identifiers and user content stay untouched.
public enum ProductCopy: Sendable {
    case english, simplifiedChinese

    public static let current = preferred(for: Locale.preferredLanguages)

    public static func preferred(for languages: [String]) -> Self {
        for identifier in languages {
            switch Locale(identifier: identifier).language.languageCode?.identifier {
            case "en": return .english
            case "zh": return .simplifiedChinese
            default: continue
            }
        }
        return .simplifiedChinese
    }

    public func text(_ chinese: String, _ english: String) -> String {
        self == .english ? english : chinese
    }

    public static func text(_ chinese: String, _ english: String) -> String {
        current.text(chinese, english)
    }
}
