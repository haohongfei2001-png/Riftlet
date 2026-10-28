import Foundation
#if canImport(Security)
import Security
#endif

public protocol FeedbackSecretStorage: Sendable {
    func secret(for id: String, create: Bool) throws -> String
}

/// Per-report random capability; no installation ID and no GitHub credentials.
public final class KeychainFeedbackSecrets: FeedbackSecretStorage, @unchecked Sendable {
    private let service: String
    public init(namespace: String) { service = "com.riftlet.feedback.v1." + namespace }
    public func secret(for id: String, create: Bool) throws -> String {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: id,
            kSecUseDataProtectionKeychain as String: true]
        var read = query; read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        // A background retry must not open a Keychain authorization dialog.
        // A missing/locked capability is retained as blocked, never replaced.
        if !create { read[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let text = String(data: data, encoding: .utf8),
           text.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil { return text }
        guard status == errSecItemNotFound, create else { throw FeedbackFailure.secretUnavailable }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw FeedbackFailure.secretUnavailable }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        var add = query; add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        if added == errSecDuplicateItem { return try secret(for: id, create: false) }
        guard added == errSecSuccess else { throw FeedbackFailure.secretUnavailable }
        return token
        #else
        throw FeedbackFailure.secretUnavailable
        #endif
    }
}

/// Used only by tests; the shipping host always selects KeychainFeedbackSecrets.
public final class MemoryFeedbackSecrets: FeedbackSecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func secret(for id: String, create: Bool) throws -> String {
        lock.lock(); defer { lock.unlock() }
        if let value = values[id] { return value }
        guard create else { throw FeedbackFailure.secretUnavailable }
        let value = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        values[id] = value; return value
    }
}
