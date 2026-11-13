import XCTest
@testable import LumoBar

/// Text that is built in code: error wording per provider, locale-aware times and renamed scenes.
final class VisibleTextTests: XCTestCase {
    func testNanoleafAndTuyaHTTPErrorsUseDifferentWording() {
        XCTAssertNotEqual(LampControlError.http(404).localizedDescription,
                          LampControlError.tuyaHTTP(404).localizedDescription)
    }

    func testClockTimeFollowsTheLocale() {
        for id in ["fr_FR", "cs_CZ"] {
            let text = L10n.clockTime(hour: 14, minute: 5, locale: Locale(identifier: id))
            XCTAssertEqual(text, "14:05", id)
        }
        let twelve = L10n.clockTime(hour: 14, minute: 5, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(twelve.hasPrefix("2:05"), twelve)
        XCTAssertTrue(twelve.contains("PM"), twelve)
    }

    func testClockTimeCoversTheWholeDay() {
        for hour in 0..<24 {
            let text = L10n.clockTime(hour: hour, minute: 30, locale: Locale(identifier: "fr_FR"))
            XCTAssertTrue(text.hasSuffix(":30"), text)
            XCTAssertEqual(Int(text.dropLast(3)), hour, text)
        }
    }

    func testAutomationActionShowsTheRenamedBuiltInScene() {
        var scene = LightScenePreset.preset(id: "relax")!.makeScene()
        let original = AutomationAction.presetSceneName(id: "relax", in: [scene])
        XCTAssertEqual(original, LightScenePreset.preset(id: "relax")?.title)
        scene.title = "Evening glow"
        XCTAssertEqual(AutomationAction.presetSceneName(id: "relax", in: [scene]), "Evening glow")
        XCTAssertEqual(AutomationAction.presetSceneName(id: "relax", in: []), original)
    }
}
