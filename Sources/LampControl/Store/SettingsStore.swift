import Foundation

final class SettingsStore {
    private let keychain = KeychainStore()

    func load() throws -> SettingsSnapshot {
        let settings = try readStoredSettings().toSettings()
        let secret = try keychain.readSecret()
        return SettingsSnapshot(settings: settings, hasSecret: !secret.isEmpty)
    }

    /// An empty `accessSecret` means "keep the stored one" (the secret is never read back into
    /// the form); only `clearSecret` removes it from the Keychain.
    func save(_ input: TuyaSettings, clearSecret: Bool = false) throws -> SettingsSnapshot {
        let stored = StoredSettings(settings: input)

        if clearSecret {
            try keychain.deleteSecret(service: KeychainStore.Item.tuya.service, account: KeychainStore.Item.tuya.account)
        } else if !input.accessSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try keychain.saveSecret(input.accessSecret.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let data = try JSONEncoder().encode(stored)
        try data.write(to: settingsURL, options: .atomic)

        return try load()
    }

    func accessSecret() throws -> String {
        try keychain.readSecret()
    }

    func saveLampOrder(_ order: [String]) {
        if let data = try? JSONEncoder().encode(order) {
            try? data.write(to: lampOrderURL, options: .atomic)
        }
    }

    func loadLampOrder() -> [String] {
        guard FileManager.default.fileExists(atPath: lampOrderURL.path) else {
            return []
        }
        let data = try? Data(contentsOf: lampOrderURL)
          if let data,
              let order = try? JSONDecoder().decode([String].self, from: data) {
            return order
        }
        return []
    }

    private var lampOrderURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LampControl", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("lampOrder.json")
    }

    private func readStoredSettings() throws -> StoredSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return StoredSettings(settings: TuyaSettings())
        }

        let data = try Data(contentsOf: settingsURL)
        return try JSONDecoder().decode(StoredSettings.self, from: data)
    }

    private var settingsURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LampControl", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("settings.json")
    }
}
