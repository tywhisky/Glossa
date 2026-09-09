import Foundation
import LocalAuthentication
import Security

struct APIConfiguration: Codable, Equatable, Sendable {
    var baseURL: String
    var model: String

    static let deepSeek = Self(baseURL: "https://api.deepseek.com", model: "deepseek-v4-flash")
    static let storageKey = "chatCompletionsConfiguration"

    func validated() throws -> Self {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URLComponents(string: base), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw APIError.invalidConfiguration }
        url.scheme = "https"
        url.host = host.lowercased()
        if url.port == 443 { url.port = nil }
        while url.path.hasSuffix("/") { url.path.removeLast() }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = url.url?.absoluteString, !model.isEmpty, model.utf8.count <= 200 else {
            throw APIError.invalidConfiguration
        }
        return Self(baseURL: normalized, model: model)
    }

    var endpoint: URL {
        get throws {
            let value = try validated()
            guard let url = URL(string: value.baseURL) else { throw APIError.invalidConfiguration }
            return url.appendingPathComponent("chat/completions")
        }
    }
    var isDeepSeek: Bool { URL(string: baseURL)?.host?.lowercased() == "api.deepseek.com" }
}

enum APIKeyStore {
    private static func query(for configuration: APIConfiguration) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.tywhisky.Glossa.api-key",
         kSecAttrAccount as String: try configuration.validated().baseURL,
         kSecAttrSynchronizable as String: false]
    }

    static func containsKey(for configuration: APIConfiguration) throws -> Bool {
        var query = try query(for: configuration)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw APIError.keychain(status) }
        return true
    }

    static func read(for configuration: APIConfiguration) throws -> String {
        var query = try query(for: configuration)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw APIError.missingKey }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw APIError.keychain(status)
        }
        return key
    }

    static func save(_ key: String, for configuration: APIConfiguration) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(key) else {
            throw APIError.invalidKey
        }
        let query = try query(for: configuration)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw APIError.keychain(status) }
    }

    static func isValid(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 4_096 && key.utf8.allSatisfy { (33...126).contains($0) }
    }

    static func delete(for configuration: APIConfiguration) throws {
        let status = SecItemDelete(try query(for: configuration) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.keychain(status) }
    }
}

enum APIError: Error, LocalizedError, Equatable {
    case invalidConfiguration, invalidKey, missingKey, invalidPrompt, invalidResponse, responseTooLarge, incomplete
    case keychain(OSStatus), http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Enter an HTTPS base URL without credentials, query, or fragment, and a model name."
        case .invalidKey: "Enter an API key using printable ASCII characters without whitespace (up to 4 KB)."
        case .missingKey: "Save an API key for this base URL in Settings."
        case .invalidPrompt: "Include {{text}} in your prompt and keep the assembled prompt under 64 KB."
        case .invalidResponse: "The provider returned an unsupported or empty streaming response."
        case .responseTooLarge: "The response exceeded Glossa’s size limit. Try a shorter prompt."
        case .incomplete: "The response was interrupted or truncated. You can retry."
        case .keychain(let status): "Keychain could not complete the operation (\(status))."
        case .http(401), .http(403): "The provider rejected this API key or its permissions. Check Settings."
        case .http(402): "Your provider account has insufficient balance."
        case .http(429): "The provider is rate limiting requests. Please try again later."
        case .http(let status): "The provider returned HTTP \(status). Check the base URL and model, or try again later."
        }
    }
}
