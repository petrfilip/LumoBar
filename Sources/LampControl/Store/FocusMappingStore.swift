import Foundation

/// `focusMappings.json`.
final class FocusMappingStore {
    private let file: JSONListStore<FocusMapping>

    init(directory: URL = AppDirectories.support, recovery: RecoveryLog = .shared) {
        file = JSONListStore(directory: directory, fileName: "focusMappings.json", recovery: recovery)
    }

    func saveMappings(_ mappings: [FocusMapping]) throws { try file.save(mappings) }
    func loadMappings() throws -> [FocusMapping] { try file.load() }
}
