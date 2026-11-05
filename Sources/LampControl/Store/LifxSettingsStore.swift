import Foundation

final class LifxSettingsStore {
    private let keychain = KeychainStore()
    private let keychainService = KeychainStore.Item.lifx.service
    private let keychainAccount = KeychainStore.Item.lifx.account

    func load() throws -> LifxSettings {
        LifxSettings(token: try keychain.readSecret(service: keychainService, account: keychainAccount))
    }

    func save(_ input: LifxSettings) throws -> LifxSettings {
        let token = input.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            try keychain.saveSecret(token, service: keychainService, account: keychainAccount)
        }

        return try load()
    }
}
