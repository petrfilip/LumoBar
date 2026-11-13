import Foundation

final class LifxSettingsStore {
    private let keychain: SecretStoring

    init(keychain: SecretStoring = KeychainStore()) {
        self.keychain = keychain
    }

    private let keychainService = KeychainStore.Item.lifx.service
    private let keychainAccount = KeychainStore.Item.lifx.account

    func load() throws -> LifxSettings {
        LifxSettings(token: try keychain.readSecret(service: keychainService, account: keychainAccount))
    }

    func save(_ input: LifxSettings) throws -> LifxSettings {
        let token = input.token.trimmingCharacters(in: .whitespacesAndNewlines)
        try keychain.writeOrDelete(token, service: keychainService, account: keychainAccount)

        return try load()
    }
}
