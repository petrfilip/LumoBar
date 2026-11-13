import Foundation

/// Tuya settings (`settings.json`, secret in the Keychain) and the custom lamp order
/// (`lampOrder.json`).
final class SettingsStore {
    private let keychain: SecretStoring
    private let settingsFile: JSONFileStore<StoredSettings>
    private let orderFile: JSONListStore<String>

    init(directory: URL = AppDirectories.support, keychain: SecretStoring = KeychainStore(),
         recovery: RecoveryLog = .shared) {
        self.keychain = keychain
        settingsFile = JSONFileStore(directory: directory, fileName: "settings.json",
                                     defaultValue: StoredSettings(settings: TuyaSettings()), recovery: recovery)
        orderFile = JSONListStore(directory: directory, fileName: "lampOrder.json", recovery: recovery)
    }

    private var tuya: KeychainStore.Item { .tuya }

    func load() throws -> SettingsSnapshot {
        let settings = try settingsFile.load().toSettings()
        let secret = try keychain.readSecret(service: tuya.service, account: tuya.account)
        return SettingsSnapshot(settings: settings, hasSecret: !secret.isEmpty)
    }

    /// An empty `accessSecret` means "keep the stored one" (the secret is never read back into
    /// the form); only `clearSecret` removes it from the Keychain.
    func save(_ input: TuyaSettings, clearSecret: Bool = false) throws -> SettingsSnapshot {
        let stored = StoredSettings(settings: input)
        let secret = input.accessSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        if clearSecret {
            try keychain.deleteSecret(service: tuya.service, account: tuya.account)
        } else if !secret.isEmpty {
            try keychain.saveSecret(secret, service: tuya.service, account: tuya.account)
        }

        try settingsFile.save(stored)
        return try load()
    }

    func accessSecret() throws -> String {
        try keychain.readSecret(service: tuya.service, account: tuya.account)
    }

    func saveLampOrder(_ order: [String]) {
        try? orderFile.save(order)
    }

    func loadLampOrder() -> [String] {
        (try? orderFile.load()) ?? []
    }
}
