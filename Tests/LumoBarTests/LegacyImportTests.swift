import XCTest
@testable import LumoBar

final class LegacyImportTests: XCTestCase {
    private var root: URL!
    private var legacyDir: URL!
    private var newDir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var secrets: MemorySecrets!
    private var legacyDefaults: [String: Any]?

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("LumoBarImportTests-\(UUID().uuidString)")
        legacyDir = root.appendingPathComponent("LampControl")
        newDir = root.appendingPathComponent("LumoBar")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "LumoBarImportTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        secrets = MemorySecrets()
        legacyDefaults = nil
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeImport() -> LegacyImport {
        LegacyImport(legacyDirectory: legacyDir, directory: newDir, defaults: defaults,
                     legacyDefaults: { [legacyDefaults] in legacyDefaults }, secrets: secrets)
    }

    private func write(_ name: String, _ text: String, in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: dir.appendingPathComponent(name))
    }

    private func read(_ name: String, in dir: URL) -> String? {
        try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    private func names(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private func seedLegacySetup() throws {
        try write("settings.json", "tuya", in: legacyDir)
        try write("rooms.json", "rooms", in: legacyDir)
        try write("hue-settings.json", "hue", in: legacyDir)
        try secrets.saveSecret("tuya-secret", service: "LampControl.Tuya", account: "tuya-access-secret")
        try secrets.saveSecret("hue-user", service: "LampControl.Hue", account: "hue-username")
        try secrets.saveSecret("lifx", service: "LampControl.LIFX", account: "lifx-token")
        try secrets.saveSecret("govee", service: "LampControl.Govee", account: "govee-api-key")
        try secrets.saveSecret("tok-a", service: "LampControl.Nanoleaf", account: "nanoleaf-token-A")
        try secrets.saveSecret("tok-b", service: "LampControl.Nanoleaf", account: "nanoleaf-token-B")
        legacyDefaults = [
            "LampControl.onboarding.dismissed": true,
            "LampControl.rooms.collapsed": ["r1", "r2"],
            "LampControl.rooms.migrated": true,
            "LampControl.scenes.presetsSeeded.v1": true,
            "SUEnableAutomaticChecks": false,
            "SUAutomaticallyUpdate": true,
            "SULastCheckTime": Date(),
            "SUHasLaunchedBefore": true,
            "NSWindow Frame Foo": "1 2 3 4",
            "AppleLanguages": ["cs"],
            "com.apple.something": 1
        ]
    }

    // MARK: Fresh install

    func testFreshInstallImportsNothingAndSetsTheMarker() throws {
        let report = try XCTUnwrap(makeImport().runIfNeeded())
        XCTAssertFalse(report.copiedAnything)
        XCTAssertEqual(report.failures, 0)
        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.legacyImportDone))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newDir.path))
        XCTAssertTrue(secrets.items.isEmpty)
    }

    // MARK: Full import

    func testFullImportCopiesFilesSecretsAndDefaults() throws {
        try seedLegacySetup()
        let report = try XCTUnwrap(makeImport().runIfNeeded())

        XCTAssertTrue(report.copiedAnything)
        XCTAssertEqual(report.failures, 0)
        XCTAssertEqual(names(in: newDir), ["hue-settings.json", "rooms.json", "settings.json"])
        XCTAssertEqual(read("rooms.json", in: newDir), "rooms")

        XCTAssertEqual(secrets.items["LumoBar.Tuya/tuya-access-secret"], "tuya-secret")
        XCTAssertEqual(secrets.items["LumoBar.Hue/hue-username"], "hue-user")
        XCTAssertEqual(secrets.items["LumoBar.LIFX/lifx-token"], "lifx")
        XCTAssertEqual(secrets.items["LumoBar.Govee/govee-api-key"], "govee")
        XCTAssertEqual(secrets.items["LumoBar.Nanoleaf/nanoleaf-token-A"], "tok-a")
        XCTAssertEqual(secrets.items["LumoBar.Nanoleaf/nanoleaf-token-B"], "tok-b")
        XCTAssertEqual(report.secrets, 6)

        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.onboardingDismissed))
        XCTAssertEqual(defaults.stringArray(forKey: AppDefaultsKeys.roomsCollapsed), ["r1", "r2"])
        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.roomsMigrated))
        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.scenePresetsSeeded))
        XCTAssertEqual(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "SUAutomaticallyUpdate") as? Bool, true)
        XCTAssertEqual(report.defaultsKeys, 6)
        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.legacyImportDone))
    }

    func testLegacyDataIsNeverModified() throws {
        try seedLegacySetup()
        _ = makeImport().runIfNeeded()

        XCTAssertEqual(names(in: legacyDir), ["hue-settings.json", "rooms.json", "settings.json"])
        XCTAssertEqual(secrets.items["LampControl.Tuya/tuya-access-secret"], "tuya-secret")
        XCTAssertEqual(secrets.items["LampControl.Nanoleaf/nanoleaf-token-A"], "tok-a")
        XCTAssertEqual(secrets.items.keys.filter { $0.hasPrefix("LampControl.") }.count, 6)
    }

    func testBookkeepingAndSystemKeysAreNotCopied() throws {
        try seedLegacySetup()
        _ = makeImport().runIfNeeded()
        let own = defaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertEqual(Set(own.keys), [
            AppDefaultsKeys.onboardingDismissed, AppDefaultsKeys.roomsCollapsed, AppDefaultsKeys.roomsMigrated,
            AppDefaultsKeys.scenePresetsSeeded, "SUEnableAutomaticChecks", "SUAutomaticallyUpdate",
            AppDefaultsKeys.legacyImportDone
        ])
    }

    func testEachLegacySecretIsReadOnlyOnce() throws {
        try seedLegacySetup()
        _ = makeImport().runIfNeeded()
        let legacyReads = secrets.reads.filter { $0.hasPrefix("LampControl.") }
        XCTAssertEqual(legacyReads.count, Set(legacyReads).count)
        XCTAssertEqual(legacyReads.count, 6)
    }

    // MARK: Existing data

    func testExistingLumoBarFilesBlockTheFileImport() throws {
        try seedLegacySetup()
        try write("rooms.json", "mine", in: newDir)
        let report = try XCTUnwrap(makeImport().runIfNeeded())

        XCTAssertEqual(report.files, [])
        XCTAssertEqual(names(in: newDir), ["rooms.json"])
        XCTAssertEqual(read("rooms.json", in: newDir), "mine")
        // The other parts still run.
        XCTAssertEqual(report.secrets, 6)
        XCTAssertEqual(report.defaultsKeys, 6)
    }

    func testAFolderWithoutJSONFilesDoesNotBlockAndNothingIsOverwritten() throws {
        try seedLegacySetup()
        try write("notes.txt", "keep", in: newDir)
        let report = try XCTUnwrap(makeImport().runIfNeeded())
        XCTAssertEqual(report.files.sorted(), ["hue-settings.json", "rooms.json", "settings.json"])
        XCTAssertEqual(read("notes.txt", in: newDir), "keep")
    }

    func testExistingSecretsAndDefaultsAreNotOverwritten() throws {
        try seedLegacySetup()
        try secrets.saveSecret("new-tuya", service: "LumoBar.Tuya", account: "tuya-access-secret")
        try secrets.saveSecret("new-tok", service: "LumoBar.Nanoleaf", account: "nanoleaf-token-A")
        defaults.set(false, forKey: AppDefaultsKeys.onboardingDismissed)
        defaults.set(true, forKey: "SUEnableAutomaticChecks")

        let report = try XCTUnwrap(makeImport().runIfNeeded())

        XCTAssertEqual(secrets.items["LumoBar.Tuya/tuya-access-secret"], "new-tuya")
        XCTAssertEqual(secrets.items["LumoBar.Nanoleaf/nanoleaf-token-A"], "new-tok")
        XCTAssertEqual(secrets.items["LumoBar.Nanoleaf/nanoleaf-token-B"], "tok-b")
        XCTAssertEqual(report.secrets, 4)
        XCTAssertFalse(defaults.bool(forKey: AppDefaultsKeys.onboardingDismissed))
        XCTAssertEqual(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, true)
        XCTAssertEqual(report.defaultsKeys, 4)
        // The old secrets were not even read for the items that already exist.
        XCTAssertFalse(secrets.reads.contains("LampControl.Tuya/tuya-access-secret"))
    }

    // MARK: Second launch

    func testSecondLaunchIsANoOp() throws {
        try seedLegacySetup()
        XCTAssertNotNil(makeImport().runIfNeeded())
        try FileManager.default.removeItem(at: newDir.appendingPathComponent("rooms.json"))
        try secrets.deleteSecret(service: "LumoBar.Hue", account: "hue-username")
        defaults.removeObject(forKey: AppDefaultsKeys.roomsMigrated)

        XCTAssertNil(makeImport().runIfNeeded())
        XCTAssertEqual(names(in: newDir), ["hue-settings.json", "settings.json"])
        XCTAssertEqual(secrets.items["LumoBar.Hue/hue-username"], nil)
        XCTAssertNil(defaults.object(forKey: AppDefaultsKeys.roomsMigrated))
    }

    func testSecondLaunchAfterAFreshInstallStaysANoOpEvenIfLampControlAppearsLater() throws {
        XCTAssertNotNil(makeImport().runIfNeeded())
        try seedLegacySetup()
        XCTAssertNil(makeImport().runIfNeeded())
        XCTAssertFalse(FileManager.default.fileExists(atPath: newDir.path))
        XCTAssertNil(secrets.items["LumoBar.Tuya/tuya-access-secret"])
    }

    // MARK: Skipped files

    func testSkippedFilesAreNotCopied() throws {
        try write("rooms.json", "rooms", in: legacyDir)
        try write("rooms.corrupt-20260101-120000.json", "bad", in: legacyDir)
        try write("settings.corrupt-1.json", "bad", in: legacyDir)
        try write("license.json", "lic", in: legacyDir)
        try write("shortcut-settings.json", "sc", in: legacyDir)
        try write("widgetSnapshot.json", "w", in: legacyDir)
        try write("leftover.dat", "x", in: legacyDir)
        try FileManager.default.createDirectory(at: legacyDir.appendingPathComponent("sub.json"), withIntermediateDirectories: true)

        let report = try XCTUnwrap(makeImport().runIfNeeded())

        XCTAssertEqual(report.files, ["rooms.json"])
        XCTAssertEqual(names(in: newDir), ["rooms.json"])
    }

    // MARK: Robustness

    func testAFailingKeychainDoesNotStopFilesAndDefaults() throws {
        try seedLegacySetup()
        secrets.failReads = true
        let report = try XCTUnwrap(makeImport().runIfNeeded())

        XCTAssertGreaterThan(report.failures, 0)
        XCTAssertEqual(report.secrets, 0)
        XCTAssertEqual(report.files.count, 3)
        XCTAssertEqual(report.defaultsKeys, 6)
        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.legacyImportDone))
    }

    func testAnUncopyableFileDoesNotStopTheOthers() throws {
        try seedLegacySetup()
        let locked = legacyDir.appendingPathComponent("rooms.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        let report = try XCTUnwrap(makeImport().runIfNeeded())

        XCTAssertEqual(report.failures, 1)
        XCTAssertEqual(report.files.sorted(), ["hue-settings.json", "settings.json"])
        XCTAssertEqual(report.secrets, 6)
        XCTAssertEqual(report.defaultsKeys, 6)
    }

    func testBannerOnlyWhenSomethingWasCopied() {
        XCTAssertFalse(LegacyImportReport().copiedAnything)
        XCTAssertFalse(LegacyImportReport(failures: 3).copiedAnything)
        XCTAssertTrue(LegacyImportReport(secrets: 1).copiedAnything)
        XCTAssertFalse(L10n.legacyImported.isEmpty)
    }

    func testKeyMapping() {
        XCTAssertEqual(LegacyImport.mappedKey(for: "LampControl.rooms.collapsed"), "LumoBar.rooms.collapsed")
        XCTAssertEqual(LegacyImport.mappedKey(for: "SUEnableAutomaticChecks"), "SUEnableAutomaticChecks")
        XCTAssertNil(LegacyImport.mappedKey(for: "SULastCheckTime"))
        XCTAssertNil(LegacyImport.mappedKey(for: "NSWindow Frame"))
        XCTAssertNil(LegacyImport.mappedKey(for: "AppleLanguages"))
    }
}
