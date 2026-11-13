import XCTest
@testable import LumoBar

final class FocusMappingTests: XCTestCase {
    func testMappingMatchesIdentifierCaseInsensitively() {
        let mapping = FocusMapping(focusIdentifier: "Sleep", focusDisplayName: "Sleep")
        XCTAssertTrue(mapping.matches(focusIdentifier: "sleep"))
        XCTAssertTrue(mapping.matches(focusIdentifier: "SLEEP"))
        XCTAssertTrue(mapping.matches(focusIdentifier: " Sleep "))
        XCTAssertFalse(mapping.matches(focusIdentifier: "work"))
    }

    func testEnabledMappingResolvesMixedCaseAndSkipsDisabled() {
        let disabled = FocusMapping(focusIdentifier: "sleep", focusDisplayName: "x", isEnabled: false)
        let typed = FocusMapping(focusIdentifier: "Sleep", focusDisplayName: "Sleep")
        let other = FocusMapping(focusIdentifier: "work", focusDisplayName: "Work")
        let found = FocusMapping.enabledMapping(for: "sleep", in: [other, disabled, typed])
        XCTAssertEqual(found?.id, typed.id)
        XCTAssertNil(FocusMapping.enabledMapping(for: "gaming", in: [other, disabled, typed]))
    }
}
