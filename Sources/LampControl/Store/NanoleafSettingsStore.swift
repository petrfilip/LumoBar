import Foundation

/// `nanoleaf-settings.json`.
final class NanoleafSettingsStore {
    private let file: JSONFileStore<NanoleafSettings>

    init(directory: URL = AppDirectories.support, recovery: RecoveryLog = .shared) {
        file = JSONFileStore(directory: directory, fileName: "nanoleaf-settings.json",
                             defaultValue: NanoleafSettings(), recovery: recovery)
    }

    func load() throws -> NanoleafSettings { try file.load() }

    func save(_ input: NanoleafSettings) throws -> NanoleafSettings {
        try file.save(input)
        return try load()
    }
}
