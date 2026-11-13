import Foundation

/// `scenes.json`.
final class LightSceneStore {
    private let file: JSONListStore<UserLightScene>

    init(directory: URL = AppDirectories.support, recovery: RecoveryLog = .shared) {
        file = JSONListStore(directory: directory, fileName: "scenes.json", recovery: recovery)
    }

    func load() throws -> [UserLightScene] { try file.load() }
    func save(_ scenes: [UserLightScene]) throws { try file.save(scenes) }
}
