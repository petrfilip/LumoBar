import XCTest
@testable import LampControl

/// In-memory stand-in for the Keychain; never touches the real one.
final class MemorySecrets: SecretStoring {
    struct Failure: Error {}

    var items: [String: String] = [:]
    /// Makes every write fail, like a locked or unavailable Keychain.
    var failWrites = false

    private func key(_ service: String, _ account: String) -> String { service + "/" + account }
    func readSecret(service: String, account: String) throws -> String { items[key(service, account)] ?? "" }
    func saveSecret(_ secret: String, service: String, account: String) throws {
        if failWrites { throw Failure() }
        items[key(service, account)] = secret
    }
    func deleteSecret(service: String, account: String) throws { items[key(service, account)] = nil }
    func deleteAllSecrets(service: String) throws {
        for k in items.keys where k.hasPrefix(service + "/") { items[k] = nil }
    }
}

/// A throwaway support folder per test, removed afterwards.
class StoreTestCase: XCTestCase {
    var dir: URL!
    var recovery: RecoveryLog!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LampControlStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        recovery = RecoveryLog()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ json: String, to name: String) throws {
        try Data(json.utf8).write(to: dir.appendingPathComponent(name))
    }

    func read(_ name: String) throws -> String {
        String(decoding: try Data(contentsOf: dir.appendingPathComponent(name)), as: UTF8.self)
    }

    func filesInDir() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    /// Files that are backups of `base` (e.g. "scenes").
    func backups(of base: String) throws -> [String] {
        try filesInDir().filter { $0.hasPrefix("\(base).corrupt-") }
    }
}
