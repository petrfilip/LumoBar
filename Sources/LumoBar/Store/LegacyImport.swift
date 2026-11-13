import Foundation
import OSLog

/// What the one-time import copied.
struct LegacyImportReport: Equatable {
    var files: [String] = []
    var secrets = 0
    var defaultsKeys = 0
    /// Parts that failed; the import carries on with the others.
    var failures = 0

    var copiedAnything: Bool { !files.isEmpty || secrets > 0 || defaultsKeys > 0 }
}

/// One-time, non-destructive import of a LampControl setup into LumoBar.
///
/// LumoBar has its own bundle ID, folder, Keychain services and defaults domain, and may live
/// next to LampControl. On the first launch this copies what LampControl left behind:
/// - the JSON files of `~/Library/Application Support/LampControl` (not the legacy ones that are
///   no longer used, not the `.corrupt-*` backups) into the LumoBar folder, when that has none yet;
/// - the Keychain items (one per provider, plus one Nanoleaf token per device);
/// - the app's UserDefaults keys (`LampControl.*` become `LumoBar.*`) and Sparkle's two user choices.
///
/// Nothing is moved or deleted, and nothing that already exists on the LumoBar side is
/// overwritten. A failure in one part is logged and does not stop the others. A marker in the
/// new defaults makes it run once, whether or not there was anything to import.
///
/// It must run before anything reads settings: `AppMain` calls it before the `AppState` exists.
struct LegacyImport {
    static let legacyDefaultsDomain = "fr.hugoinformatique.lampcontrol"
    static let legacyKeychainPrefix = "LampControl."
    /// Sparkle's user choices. Its bookkeeping (last check time, "has launched before") is not copied.
    static let sparkleKeys = ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate"]
    /// Files LampControl wrote that LumoBar does not use any more.
    static let skippedFiles: Set<String> = ["license.json", "shortcut-settings.json", "widgetSnapshot.json"]

    private static let log = Logger(subsystem: "cz.tix.lumobar", category: "LegacyImport")

    var legacyDirectory: URL = AppDirectories.legacySupport
    var directory: URL = AppDirectories.support
    var defaults: UserDefaults = .standard
    /// The old app's defaults, as `persistentDomain(forName:)` gives them (the app is not sandboxed).
    var legacyDefaults: () -> [String: Any]? = {
        UserDefaults.standard.persistentDomain(forName: LegacyImport.legacyDefaultsDomain)
    }
    var secrets: SecretStoring = KeychainStore()

    /// Runs the import unless it already ran. Returns nil on every launch but the first.
    func runIfNeeded() -> LegacyImportReport? {
        guard !defaults.bool(forKey: AppDefaultsKeys.legacyImportDone) else { return nil }
        var report = LegacyImportReport()
        importFiles(into: &report)
        importSecrets(into: &report)
        importDefaults(into: &report)
        // Set last, and unconditionally: with nothing to import there is nothing to retry.
        defaults.set(true, forKey: AppDefaultsKeys.legacyImportDone)
        Self.log.info("""
            Legacy import: \(report.files.count) files, \(report.secrets) secrets, \
            \(report.defaultsKeys) defaults keys, \(report.failures) failures
            """)
        return report
    }

    // MARK: Files

    static func isImportable(fileName: String) -> Bool {
        fileName.hasSuffix(".json")
            && !fileName.contains(".corrupt-")
            && !skippedFiles.contains(fileName)
    }

    private func importFiles(into report: inout LegacyImportReport) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: legacyDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        do {
            // Anything already in the new folder (even a half-set-up LumoBar) is the user's data.
            let existing = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
            guard !existing.contains(where: { $0.hasSuffix(".json") }) else { return }

            let names = try fm.contentsOfDirectory(atPath: legacyDirectory.path).sorted()
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in names where Self.isImportable(fileName: name) {
                let source = legacyDirectory.appendingPathComponent(name)
                let target = directory.appendingPathComponent(name)
                var sourceIsDirectory: ObjCBool = false
                guard fm.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory), !sourceIsDirectory.boolValue,
                      !fm.fileExists(atPath: target.path) else { continue }
                do {
                    try fm.copyItem(at: source, to: target)
                    report.files.append(name)
                } catch {
                    report.failures += 1
                    Self.log.error("Could not copy \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            report.failures += 1
            Self.log.error("Could not import the LampControl folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Keychain

    private static func legacyService(of service: String) -> String {
        legacyKeychainPrefix + service.dropFirst("LumoBar.".count)
    }

    private func importSecrets(into report: inout LegacyImportReport) {
        for item in KeychainStore.Item.all {
            copySecret(from: Self.legacyService(of: item.service), to: item.service, account: item.account, into: &report)
        }
        let nanoleaf = KeychainStore.Item.nanoleafService
        let legacyNanoleaf = Self.legacyService(of: nanoleaf)
        do {
            for account in try secrets.accounts(service: legacyNanoleaf) {
                copySecret(from: legacyNanoleaf, to: nanoleaf, account: account, into: &report)
            }
        } catch {
            report.failures += 1
            Self.log.error("Could not list the Nanoleaf Keychain items: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The new item is checked first (it is ours, so no prompt), and the old one is read only when
    /// it is needed: reading another app's item may make macOS ask the user, once per item.
    private func copySecret(from legacyService: String, to service: String, account: String,
                            into report: inout LegacyImportReport) {
        do {
            guard try secrets.readSecret(service: service, account: account).isEmpty else { return }
            let secret = try secrets.readSecret(service: legacyService, account: account)
            guard !secret.isEmpty else { return }
            try secrets.saveSecret(secret, service: service, account: account)
            report.secrets += 1
        } catch {
            report.failures += 1
            Self.log.error("Could not copy the Keychain item \(legacyService, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Defaults

    /// The new key for an old one, or nil when the key is not LampControl's own or Sparkle's choice.
    static func mappedKey(for legacyKey: String) -> String? {
        if legacyKey.hasPrefix("LampControl.") { return "LumoBar." + legacyKey.dropFirst("LampControl.".count) }
        return sparkleKeys.contains(legacyKey) ? legacyKey : nil
    }

    private func importDefaults(into report: inout LegacyImportReport) {
        guard let legacy = legacyDefaults() else { return }
        for (legacyKey, value) in legacy.sorted(by: { $0.key < $1.key }) {
            guard let key = Self.mappedKey(for: legacyKey), defaults.object(forKey: key) == nil else { continue }
            defaults.set(value, forKey: key)
            report.defaultsKeys += 1
        }
    }
}
