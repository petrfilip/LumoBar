import Foundation

/// `wiz-settings.json`.
final class WizSettingsStore {
    private let file: JSONFileStore<WizSettings>

    init(directory: URL = AppDirectories.support, recovery: RecoveryLog = .shared) {
        file = JSONFileStore(directory: directory, fileName: "wiz-settings.json",
                             defaultValue: WizSettings(), recovery: recovery)
    }

    func load() throws -> WizSettings { try file.load() }

    func save(_ input: WizSettings) throws -> WizSettings {
        try file.save(input)
        return try load()
    }
}
