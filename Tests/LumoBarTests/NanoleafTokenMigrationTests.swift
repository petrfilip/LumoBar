import XCTest
@testable import LumoBar

final class NanoleafTokenMigrationTests: StoreTestCase {
    private let id1 = "11111111-1111-1111-1111-111111111111"
    private let id2 = "22222222-2222-2222-2222-222222222222"
    private var legacy: String {
        """
        {"devices":[
          {"id":"\(id1)","name":"Shapes","host":"192.168.1.9","port":16021,"authToken":"tok-one","serial":"S1"},
          {"id":"\(id2)","name":"Canvas","host":"192.168.1.10","port":16021,"authToken":"tok-two","serial":""}]}
        """
    }
    private func account(_ id: String) -> String {
        KeychainStore.Item.nanoleafAccount(for: UUID(uuidString: id)!)
    }
    private func item(_ secrets: MemorySecrets, _ id: String) -> String? {
        secrets.items["\(KeychainStore.Item.nanoleafService)/\(account(id))"]
    }

    func testLegacyTokensMoveToTheKeychainAndLeaveTheFile() throws {
        try write(legacy, to: "nanoleaf-settings.json")
        let secrets = MemorySecrets()
        let store = NanoleafSettingsStore(directory: dir, keychain: secrets, recovery: recovery)

        let loaded = try store.load()
        XCTAssertEqual(loaded.devices.map(\.authToken), ["tok-one", "tok-two"], "the app still gets the tokens")
        XCTAssertEqual(item(secrets, id1), "tok-one")
        XCTAssertEqual(item(secrets, id2), "tok-two")

        let file = try read("nanoleaf-settings.json")
        XCTAssertFalse(file.contains("authToken"))
        XCTAssertFalse(file.contains("tok-one"))
        XCTAssertTrue(file.contains("192.168.1.9"))

        // The next launch reads the tokens from the Keychain.
        let again = try NanoleafSettingsStore(directory: dir, keychain: secrets, recovery: recovery).load()
        XCTAssertEqual(again.devices.map(\.authToken), ["tok-one", "tok-two"])
        XCTAssertEqual(again.devices.map(\.name), ["Shapes", "Canvas"])
        XCTAssertEqual(again.devices.first?.serial, "S1")
        XCTAssertTrue(recovery.drain().isEmpty)
    }

    func testAKeychainFailureKeepsTheTokensInTheFile() throws {
        try write(legacy, to: "nanoleaf-settings.json")
        let secrets = MemorySecrets()
        secrets.failWrites = true
        let store = NanoleafSettingsStore(directory: dir, keychain: secrets, recovery: recovery)

        let loaded = try store.load()
        XCTAssertEqual(loaded.devices.map(\.authToken), ["tok-one", "tok-two"], "still usable in memory")
        XCTAssertEqual(try read("nanoleaf-settings.json"), legacy, "the file is untouched")
        XCTAssertTrue(secrets.items.isEmpty)

        // Once the Keychain works again the migration completes.
        secrets.failWrites = false
        _ = try store.load()
        XCTAssertEqual(item(secrets, id1), "tok-one")
        XCTAssertFalse(try read("nanoleaf-settings.json").contains("tok-one"))
    }

    func testSaveWritesTokensToTheKeychainNotTheFile() throws {
        let secrets = MemorySecrets()
        let store = NanoleafSettingsStore(directory: dir, keychain: secrets, recovery: recovery)
        let device = NanoleafDevice(name: "A", host: "10.0.0.1", authToken: "  secret-token ")
        let saved = try store.save(NanoleafSettings(devices: [device]))

        XCTAssertEqual(saved.devices.first?.authToken, "secret-token")
        XCTAssertFalse(try read("nanoleaf-settings.json").contains("secret-token"))
        XCTAssertFalse(try read("nanoleaf-settings.json").contains("authToken"))
    }

    func testSaveDoesNotWriteTheFileWhenTheKeychainFails() throws {
        try write(#"{"devices":[]}"#, to: "nanoleaf-settings.json")
        let secrets = MemorySecrets()
        secrets.failWrites = true
        let store = NanoleafSettingsStore(directory: dir, keychain: secrets, recovery: recovery)
        let device = NanoleafDevice(name: "A", host: "10.0.0.1", authToken: "tok")

        XCTAssertThrowsError(try store.save(NanoleafSettings(devices: [device])))
        XCTAssertEqual(try read("nanoleaf-settings.json"), #"{"devices":[]}"#)
    }

    func testRemovingADeviceForgetsItsToken() throws {
        try write(legacy, to: "nanoleaf-settings.json")
        let secrets = MemorySecrets()
        let store = NanoleafSettingsStore(directory: dir, keychain: secrets, recovery: recovery)
        var settings = try store.load()
        settings.devices.removeAll { $0.id.uuidString == id1 }
        let saved = try store.save(settings)

        XCTAssertEqual(saved.devices.map(\.authToken), ["tok-two"])
        XCTAssertNil(item(secrets, id1))
        XCTAssertEqual(item(secrets, id2), "tok-two")
    }

    func testDeviceWithoutATokenAnywhereLoadsWithAnEmptyToken() throws {
        try write(#"{"devices":[{"name":"Lonely","host":"10.0.0.3"}]}"#, to: "nanoleaf-settings.json")
        let loaded = try NanoleafSettingsStore(directory: dir, keychain: MemorySecrets(), recovery: recovery).load()
        XCTAssertEqual(loaded.devices.count, 1)
        XCTAssertEqual(loaded.devices[0].authToken, "")
        XCTAssertEqual(loaded.devices[0].port, 16021)
    }

    func testResetRemovesEveryNanoleafToken() throws {
        let secrets = MemorySecrets()
        try secrets.saveSecret("a", service: KeychainStore.Item.nanoleafService, account: account(id1))
        try secrets.saveSecret("b", service: KeychainStore.Item.nanoleafService, account: account(id2))
        try secrets.saveSecret("keep", service: "Other", account: "x")
        var reset = AppResetService(supportDirectory: dir, defaults: .standard, defaultsDomain: nil, keychainItems: [])
        reset.keychain = secrets

        XCTAssertEqual(reset.wipeKeychain(), [])
        XCTAssertEqual(secrets.items, ["Other/x": "keep"])
    }
}
