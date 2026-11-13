import Foundation

/// `circadian-settings.json`.
final class CircadianSettingsStore {
    private let file: JSONFileStore<CircadianSettings>

    init(directory: URL = AppDirectories.support, recovery: RecoveryLog = .shared) {
        file = JSONFileStore(directory: directory, fileName: "circadian-settings.json",
                             defaultValue: .default, recovery: recovery)
    }

    func load() throws -> CircadianSettings { try file.load() }

    func save(_ settings: CircadianSettings) throws -> CircadianSettings {
        try file.save(settings)
        return try load()
    }
}
