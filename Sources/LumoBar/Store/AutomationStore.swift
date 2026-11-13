import Foundation

/// `automations.json`.
final class AutomationStore {
    private let file: JSONListStore<Automation>

    init(directory: URL = AppDirectories.support, recovery: RecoveryLog = .shared) {
        file = JSONListStore(directory: directory, fileName: "automations.json", recovery: recovery)
    }

    func load() throws -> [Automation] { try file.load() }
    func save(_ automations: [Automation]) throws { try file.save(automations) }
}
