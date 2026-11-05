import Foundation

final class HueSettingsStore {
    private let keychain = KeychainStore()
    private let keychainService = KeychainStore.Item.hue.service
    private let keychainAccount = KeychainStore.Item.hue.account

    func load() throws -> HueSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return HueSettings()
        }

        let data = try Data(contentsOf: settingsURL)
        var settings = try JSONDecoder().decode(HueSettings.self, from: data)
        settings.username = try keychain.readSecret(service: keychainService, account: keychainAccount)
        return settings
    }

    func save(_ input: HueSettings) throws -> HueSettings {
        let username = input.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty {
            try keychain.saveSecret(username, service: keychainService, account: keychainAccount)
        }

        let stored = HueSettings(
            bridgeID: input.bridgeID.trimmingCharacters(in: .whitespacesAndNewlines),
            bridgeIP: input.bridgeIP.trimmingCharacters(in: .whitespacesAndNewlines),
            username: ""
        )
        let data = try JSONEncoder().encode(stored)
        try data.write(to: settingsURL, options: .atomic)

        return try load()
    }

    private var settingsURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LampControl", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("hue-settings.json")
    }
}
