import Foundation

/// `yeelight-settings.json`.
final class YeelightSettingsStore {
    private let file: JSONFileStore<YeelightSettings>

    init(directory: URL = AppDirectories.support, recovery: RecoveryLog = .shared) {
        file = JSONFileStore(directory: directory, fileName: "yeelight-settings.json",
                             defaultValue: YeelightSettings(), recovery: recovery)
    }

    func load() throws -> YeelightSettings { try file.load() }

    func save(_ input: YeelightSettings) throws -> YeelightSettings {
        try file.save(input)
        return try load()
    }
}
