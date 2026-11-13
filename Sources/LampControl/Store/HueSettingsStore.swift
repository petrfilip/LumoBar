import Foundation

/// `hue-settings.json` (bridge id and address); the bridge user lives in the Keychain.
final class HueSettingsStore {
    private let keychain: SecretStoring
    private let file: JSONFileStore<HueSettings>

    init(directory: URL = AppDirectories.support, keychain: SecretStoring = KeychainStore(),
         recovery: RecoveryLog = .shared) {
        self.keychain = keychain
        file = JSONFileStore(directory: directory, fileName: "hue-settings.json",
                             defaultValue: HueSettings(), recovery: recovery)
    }

    private let keychainService = KeychainStore.Item.hue.service
    private let keychainAccount = KeychainStore.Item.hue.account

    func load() throws -> HueSettings {
        var settings = try file.load()
        settings.username = try keychain.readSecret(service: keychainService, account: keychainAccount)
        return settings
    }

    func save(_ input: HueSettings) throws -> HueSettings {
        let username = input.username.trimmingCharacters(in: .whitespacesAndNewlines)
        try keychain.writeOrDelete(username, service: keychainService, account: keychainAccount)

        try file.save(HueSettings(
            bridgeID: input.bridgeID.trimmingCharacters(in: .whitespacesAndNewlines),
            bridgeIP: input.bridgeIP.trimmingCharacters(in: .whitespacesAndNewlines),
            username: ""
        ))
        return try load()
    }
}
