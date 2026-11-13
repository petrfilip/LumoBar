import XCTest
@testable import LumoBar

final class OnboardingPolicyTests: XCTestCase {
    func testShownOnlyWithoutProviderAndNotDismissed() {
        XCTAssertTrue(OnboardingPolicy.shouldPresent(hasConfiguredProvider: false, dismissed: false))
        XCTAssertFalse(OnboardingPolicy.shouldPresent(hasConfiguredProvider: true, dismissed: false))
        XCTAssertFalse(OnboardingPolicy.shouldPresent(hasConfiguredProvider: false, dismissed: true))
        XCTAssertFalse(OnboardingPolicy.shouldPresent(hasConfiguredProvider: true, dismissed: true))
    }

    func testStepsAreProviderAgnosticWithDistinctKeys() {
        XCTAssertEqual(OnboardingPolicy.steps.count, 3)
        let keys = OnboardingPolicy.steps.flatMap { [$0.titleKey, $0.detailKey] }
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertFalse(OnboardingPolicy.steps.contains { $0.icon == "keyboard" })
    }

    func testStepTextExistsInEveryLanguageAndMentionsNoSingleProviderOnlyCopy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for lang in ["en", "fr", "es", "cs"] {
            let url = root.appendingPathComponent("Sources/LumoBar/Resources/\(lang).lproj/Localizable.strings")
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil)
            let table = try XCTUnwrap(plist as? [String: String])
            for step in OnboardingPolicy.steps {
                XCTAssertNotNil(table[step.titleKey], "\(lang) \(step.titleKey)")
                XCTAssertNotNil(table[step.detailKey], "\(lang) \(step.detailKey)")
            }
            XCTAssertFalse(try XCTUnwrap(table["onboarding.subtitle"]).contains("Tuya"), lang)
        }
    }
}
