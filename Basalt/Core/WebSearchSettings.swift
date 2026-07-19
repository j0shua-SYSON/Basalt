import Foundation
import Security

@MainActor
final class WebSearchSettings: ObservableObject {
    @Published var provider: WebSearchProvider {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }
    @Published var searxngEndpoint: String {
        didSet { defaults.set(searxngEndpoint, forKey: Keys.searxngEndpoint) }
    }
    @Published var braveAPIKey: String
    @Published private(set) var credentialMessage: String?

    private let defaults: UserDefaults
    private let credentialStore: CredentialStore

    init(defaults: UserDefaults = .standard, credentialStore: CredentialStore = CredentialStore()) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        provider = WebSearchProvider(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .brave
        searxngEndpoint = defaults.string(forKey: Keys.searxngEndpoint) ?? ""
        braveAPIKey = (try? credentialStore.read(account: Keys.braveAccount)) ?? ""
    }

    var configuration: WebSearchConfiguration {
        WebSearchConfiguration(
            provider: provider,
            braveAPIKey: braveAPIKey,
            searxngEndpoint: searxngEndpoint
        )
    }

    func saveCredential() {
        do {
            try credentialStore.write(braveAPIKey, account: Keys.braveAccount)
            credentialMessage = braveAPIKey.isEmpty ? "API key removed" : "API key saved in Keychain"
        } catch {
            credentialMessage = "Could not update Keychain"
        }
    }

    private enum Keys {
        static let provider = "webSearch.provider"
        static let searxngEndpoint = "webSearch.searxngEndpoint"
        static let braveAccount = "brave-search-api-key"
    }
}

struct CredentialStore: Sendable {
    private let service = "com.joshuasyson.Basalt"

    func read(account: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw CredentialError.status(status)
        }
        return value
    }

    func write(_ value: String, account: String) throws {
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var insert = base
        insert[kSecValueData] = Data(value.utf8)
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialError.status(status) }
    }
}

private enum CredentialError: Error {
    case status(OSStatus)
}
