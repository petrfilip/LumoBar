import Foundation

/// Removes everything LampControl persists, except the license.
///
/// Persisted data (read from the stores):
/// - Files in `~/Library/Application Support/LampControl/`: settings.json (Tuya),
///   lampOrder.json, hue-settings.json, yeelight-settings.json, nanoleaf-settings.json,
///   wiz-settings.json, scenes.json, rooms.json, focusMappings.json, automations.json,
///   circadian-settings.json, shortcut-settings.json (legacy), widgetSnapshot.json,
///   license.json (KEPT).
///   Every file in the folder except the license is removed, so files written by
///   older versions are covered too.
/// - Keychain (generic passwords): see `KeychainStore.Item.all`
///   (Tuya access secret, Hue username, LIFX token, Govee API key).
/// - UserDefaults of the app's bundle id: onboarding flag, the presets-seeded flag,
///   Sparkle's update preferences, system-managed UI keys.
struct AppResetService {
    /// Files that survive a reset (a purchase / early-access state, not a setting).
    static let preservedFileNames: Set<String> = ["license.json"]

    static var defaultSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LampControl", isDirectory: true)
    }

    var supportDirectory: URL = AppResetService.defaultSupportDirectory
    var defaults: UserDefaults = .standard
    /// nil when running outside an app bundle (e.g. `swift run`): the known keys are removed instead.
    var defaultsDomain: String? = Bundle.main.bundleIdentifier
    var keychainItems: [KeychainStore.Item] = KeychainStore.Item.all
    var keychain = KeychainStore()

    /// Wipes files, Keychain items and UserDefaults. Returns human-readable
    /// descriptions of the items that could not be removed (empty on success).
    func resetAll() -> [String] {
        wipeFiles() + wipeKeychain() + wipeDefaults()
    }

    func wipeFiles() -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: supportDirectory.path) else { return [] }
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(at: supportDirectory, includingPropertiesForKeys: nil)
        } catch {
            return [supportDirectory.lastPathComponent]
        }
        var failures: [String] = []
        for url in items where !Self.preservedFileNames.contains(url.lastPathComponent) {
            do { try fm.removeItem(at: url) } catch { failures.append(url.lastPathComponent) }
        }
        return failures
    }

    func wipeKeychain() -> [String] {
        var failures: [String] = []
        for item in keychainItems {
            do { try keychain.deleteSecret(service: item.service, account: item.account) }
            catch { failures.append(item.service) }
        }
        return failures
    }

    func wipeDefaults() -> [String] {
        if let domain = defaultsDomain {
            defaults.removePersistentDomain(forName: domain)
        } else {
            defaults.removeObject(forKey: "LampControl.onboarding.dismissed")
            defaults.removeObject(forKey: PresetScenes.seededDefaultsKey)
        }
        defaults.synchronize()
        return []
    }
}
