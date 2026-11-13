import Foundation

/// Removes everything LumoBar persists (LampControl's own data is never touched).
///
/// Persisted data (read from the stores):
/// - Files in `~/Library/Application Support/LumoBar/`: settings.json (Tuya),
///   lampOrder.json, hue-settings.json, yeelight-settings.json, nanoleaf-settings.json,
///   wiz-settings.json, scenes.json, rooms.json, focusMappings.json, automations.json,
///   circadian-settings.json, shortcut-settings.json (legacy), widgetSnapshot.json,
///   license.json (legacy).
///   Every file in the folder is removed, so files written by older versions are
///   covered too.
/// - Keychain (generic passwords): see `KeychainStore.Item.all`
///   (Tuya access secret, Hue username, LIFX token, Govee API key), plus every item of the
///   Nanoleaf token service (one per device).
/// - Backups the stores keep of unreadable files (`<name>.corrupt-<timestamp>.json`) live in the
///   same folder and are removed with it.
/// - UserDefaults of the app's bundle id: onboarding flag, the presets-seeded flag,
///   Sparkle's update preferences, system-managed UI keys. Afterwards the "LampControl import
///   done" marker is set again, so the next launch does not re-import.
struct AppResetService {
    var supportDirectory: URL = AppDirectories.support
    var defaults: UserDefaults = .standard
    /// nil when running outside an app bundle (e.g. `swift run`): the known keys are removed instead.
    var defaultsDomain: String? = Bundle.main.bundleIdentifier
    var keychainItems: [KeychainStore.Item] = KeychainStore.Item.all
    /// Services whose items are removed wholesale (their accounts are per device).
    var keychainServices: [String] = [KeychainStore.Item.nanoleafService]
    var keychain: SecretStoring = KeychainStore()

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
        for url in items {
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
        for service in keychainServices {
            do { try keychain.deleteAllSecrets(service: service) }
            catch { failures.append(service) }
        }
        return failures
    }

    func wipeDefaults() -> [String] {
        if let domain = defaultsDomain {
            defaults.removePersistentDomain(forName: domain)
        } else {
            AppDefaultsKeys.resettable.forEach { defaults.removeObject(forKey: $0) }
        }
        // The relaunch after a reset is a first launch for the defaults: without the marker it
        // would import LampControl's data again and undo the reset.
        defaults.set(true, forKey: AppDefaultsKeys.legacyImportDone)
        defaults.synchronize()
        return []
    }
}
