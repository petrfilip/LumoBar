import Foundation

/// `nanoleaf-settings.json` (devices) with the per-device auth tokens in the Keychain
/// (service `KeychainStore.Item.nanoleafService`, one account per device id).
///
/// Files written by older versions carry `authToken` in the JSON. `load()` migrates it once:
/// each token is written to the Keychain and only when *all* of them were stored is the file
/// rewritten without tokens. If a Keychain write fails the file is left as it is, so no token
/// is ever lost, and the migration is retried on the next load. `save()` likewise writes the
/// Keychain first and refuses to write the file when that fails.
final class NanoleafSettingsStore {
    private let keychain: SecretStoring
    private let file: JSONFileStore<NanoleafSettings>
    /// Device ids as last loaded / saved, to forget the tokens of removed devices.
    private var knownDeviceIds = Set<UUID>()

    init(directory: URL = AppDirectories.support, keychain: SecretStoring = KeychainStore(),
         recovery: RecoveryLog = .shared) {
        self.keychain = keychain
        file = JSONFileStore(directory: directory, fileName: "nanoleaf-settings.json",
                             defaultValue: NanoleafSettings(), recovery: recovery)
    }

    private let service = KeychainStore.Item.nanoleafService

    func load() throws -> NanoleafSettings {
        var settings = try file.load()
        var hasLegacyTokens = false
        var allMigrated = true

        for index in settings.devices.indices {
            let device = settings.devices[index]
            let account = KeychainStore.Item.nanoleafAccount(for: device.id)
            if !device.authToken.isEmpty {
                // Legacy file: the token came from the JSON.
                hasLegacyTokens = true
                do {
                    try keychain.saveSecret(device.authToken, service: service, account: account)
                } catch {
                    allMigrated = false
                    NSLog("LampControl: could not move a Nanoleaf token to the Keychain: \(error)")
                }
            } else {
                // A Keychain read failure leaves the token empty (the lamp then reports an error)
                // rather than failing the load: the device list must survive to be saved again.
                settings.devices[index].authToken =
                    (try? keychain.readSecret(service: service, account: account)) ?? ""
            }
        }

        if hasLegacyTokens && allMigrated {
            do { try file.save(settings) } catch {
                NSLog("LampControl: could not rewrite nanoleaf-settings.json without tokens: \(error)")
            }
        }
        knownDeviceIds = Set(settings.devices.map(\.id))
        return settings
    }

    func save(_ input: NanoleafSettings) throws -> NanoleafSettings {
        for device in input.devices {
            let token = device.authToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }   // empty: keep whatever the Keychain has
            try keychain.saveSecret(token, service: service,
                                    account: KeychainStore.Item.nanoleafAccount(for: device.id))
        }
        try file.save(input)

        let remaining = Set(input.devices.map(\.id))
        for id in knownDeviceIds.subtracting(remaining) {
            try? keychain.deleteSecret(service: service, account: KeychainStore.Item.nanoleafAccount(for: id))
        }
        return try load()
    }
}
