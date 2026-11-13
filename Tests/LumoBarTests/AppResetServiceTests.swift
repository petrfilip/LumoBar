import XCTest
@testable import LumoBar

/// Runs the reset against a temp directory and a throwaway UserDefaults suite.
/// Never touches the real Application Support folder, Keychain or defaults.
final class AppResetServiceTests: XCTestCase {
    private var dir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LumoBarResetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        suiteName = "LumoBarResetTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func service() -> AppResetService {
        AppResetService(supportDirectory: dir, defaults: defaults, defaultsDomain: suiteName, keychainItems: [])
    }

    func testWipesEverything() throws {
        let names = ["scenes.json", "rooms.json", "focusMappings.json", "automations.json", "lampOrder.json",
                     "settings.json", "hue-settings.json", "circadian-settings.json", "shortcut-settings.json",
                     "widgetSnapshot.json", "leftover-from-old-version.dat", "license.json"]
        for n in names { try Data("x".utf8).write(to: dir.appendingPathComponent(n)) }

        XCTAssertEqual(service().wipeFiles(), [])

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining, [])
    }

    func testWipesDefaultsDomain() {
        defaults.set(true, forKey: AppDefaultsKeys.onboardingDismissed)
        defaults.set(true, forKey: PresetScenes.seededDefaultsKey)
        XCTAssertEqual(service().wipeDefaults(), [])
        XCTAssertFalse(defaults.bool(forKey: AppDefaultsKeys.onboardingDismissed))
        XCTAssertFalse(defaults.bool(forKey: PresetScenes.seededDefaultsKey))
    }

    func testResetKeepsTheLegacyImportMarkerSoTheNextLaunchDoesNotReimport() {
        defaults.set(true, forKey: AppDefaultsKeys.legacyImportDone)
        defaults.set(true, forKey: AppDefaultsKeys.onboardingDismissed)
        XCTAssertEqual(service().wipeDefaults(), [])
        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.legacyImportDone))
        XCTAssertFalse(defaults.bool(forKey: AppDefaultsKeys.onboardingDismissed))
    }

    func testWithoutADomainEveryKnownKeyIsRemoved() {
        for key in AppDefaultsKeys.resettable { defaults.set(true, forKey: key) }
        let svc = AppResetService(supportDirectory: dir, defaults: defaults, defaultsDomain: nil, keychainItems: [])
        XCTAssertEqual(svc.wipeDefaults(), [])
        for key in AppDefaultsKeys.resettable { XCTAssertNil(defaults.object(forKey: key), key) }
        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.legacyImportDone))
    }

    func testDefaultSupportDirectoryIsLumoBarNotLampControl() {
        XCTAssertEqual(AppResetService().supportDirectory.lastPathComponent, "LumoBar")
        XCTAssertEqual(AppDirectories.legacySupport.lastPathComponent, "LampControl")
    }

    func testMissingDirectoryIsNotAnError() {
        let svc = AppResetService(supportDirectory: dir.appendingPathComponent("nope"), defaults: defaults,
                                  defaultsDomain: suiteName, keychainItems: [])
        XCTAssertEqual(svc.wipeFiles(), [])
    }

    func testKnownKeychainItemsAreDistinct() {
        XCTAssertEqual(Set(KeychainStore.Item.all.map(\.service)).count, KeychainStore.Item.all.count)
    }
}
