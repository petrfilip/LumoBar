import XCTest
@testable import LampControl

private final class MemorySecrets: SecretStoring {
    var items: [String: String] = [:]
    private func key(_ service: String, _ account: String) -> String { service + "/" + account }
    func readSecret(service: String, account: String) throws -> String { items[key(service, account)] ?? "" }
    func saveSecret(_ secret: String, service: String, account: String) throws { items[key(service, account)] = secret }
    func deleteSecret(service: String, account: String) throws { items[key(service, account)] = nil }
}

final class CredentialStoreTests: XCTestCase {
    func testLifxSavesTrimmedTokenAndReloadsIt() throws {
        let secrets = MemorySecrets()
        let store = LifxSettingsStore(keychain: secrets)
        let saved = try store.save(LifxSettings(token: "  abc123 \n"))
        XCTAssertEqual(saved.token, "abc123")
        XCTAssertTrue(saved.isConfigured)
    }

    func testLifxEmptyTokenDeletesTheKeychainItem() throws {
        let secrets = MemorySecrets()
        let store = LifxSettingsStore(keychain: secrets)
        _ = try store.save(LifxSettings(token: "abc123"))
        XCTAssertEqual(secrets.items.count, 1)

        let cleared = try store.save(LifxSettings(token: ""))
        XCTAssertEqual(cleared.token, "")
        XCTAssertFalse(cleared.isConfigured)
        XCTAssertTrue(secrets.items.isEmpty)
        XCTAssertEqual(try store.load().token, "")
    }

    func testWhitespaceOnlyGoveeKeyCountsAsCleared() throws {
        let secrets = MemorySecrets()
        let store = GoveeSettingsStore(keychain: secrets)
        _ = try store.save(GoveeSettings(apiKey: "key"))
        let cleared = try store.save(GoveeSettings(apiKey: "   "))
        XCTAssertFalse(cleared.isConfigured)
        XCTAssertTrue(secrets.items.isEmpty)
    }

    func testWriteOrDeleteOnMissingItemIsHarmless() throws {
        let secrets = MemorySecrets()
        try secrets.writeOrDelete("", service: "s", account: "a")
        XCTAssertTrue(secrets.items.isEmpty)
        try secrets.writeOrDelete("x", service: "s", account: "a")
        XCTAssertEqual(try secrets.readSecret(service: "s", account: "a"), "x")
    }
}
