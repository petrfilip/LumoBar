import XCTest
@testable import LumoBar

final class FocusAutomationURLTests: XCTestCase {
    private func parse(_ string: String) -> FocusAutomationURL.Event? {
        URL(string: string).flatMap(FocusAutomationURL.parse)
    }

    func testParsesActivate() {
        XCTAssertEqual(parse("lumobar://focus?mode=work"), .activate(mode: "work"))
    }

    func testLegacyLampControlSchemeIsStillAccepted() {
        XCTAssertEqual(parse("lampcontrol://focus?mode=work"), .activate(mode: "work"))
        XCTAssertEqual(parse("LampControl://focus?mode=off"), .off)
    }

    func testOtherSchemesAreRejected() {
        XCTAssertNil(parse("lumobars://focus?mode=work"))
        XCTAssertNil(parse("https://focus?mode=work"))
    }

    func testShownURLsUseTheNewScheme() {
        XCTAssertTrue(FocusAutomationURL.urlString(forMode: "off").hasPrefix("lumobar://"))
    }

    func testSchemeAndHostAreCaseInsensitive() {
        XCTAssertEqual(parse("LumoBar://FOCUS?mode=Sleep"), .activate(mode: "Sleep"))
    }

    func testModeValueKeepsItsCase() {
        XCTAssertEqual(parse("lumobar://focus?mode=DeepWork"), .activate(mode: "DeepWork"))
    }

    func testOffIsCaseInsensitive() {
        XCTAssertEqual(parse("lumobar://focus?mode=off"), .off)
        XCTAssertEqual(parse("lumobar://focus?mode=OFF"), .off)
        XCTAssertEqual(parse("lumobar://focus?mode=Off"), .off)
    }

    func testPercentEncodedModeIsDecoded() {
        XCTAssertEqual(parse("lumobar://focus?mode=Deep%20Work"), .activate(mode: "Deep Work"))
        XCTAssertEqual(parse("lumobar://focus?mode=Sp%C3%A9cial"), .activate(mode: "Spécial"))
    }

    func testModeIsTrimmed() {
        XCTAssertEqual(parse("lumobar://focus?mode=%20work%20"), .activate(mode: "work"))
        XCTAssertEqual(parse("lumobar://focus?mode=%20off%20"), .off)
    }

    func testExtraQueryItemsAreIgnored() {
        XCTAssertEqual(parse("lumobar://focus?foo=1&mode=work&bar=2"), .activate(mode: "work"))
    }

    func testRejectsWrongScheme() {
        XCTAssertNil(parse("https://focus?mode=work"))
        XCTAssertNil(parse("other://focus?mode=work"))
    }

    func testRejectsWrongHost() {
        XCTAssertNil(parse("lumobar://scene?mode=work"))
        XCTAssertNil(parse("lumobar:///?mode=work"))
    }

    func testRejectsMissingOrEmptyMode() {
        XCTAssertNil(parse("lumobar://focus"))
        XCTAssertNil(parse("lumobar://focus?mode="))
        XCTAssertNil(parse("lumobar://focus?mode=%20%20"))
        XCTAssertNil(parse("lumobar://focus?other=work"))
    }

    func testURLStringBuildsExpectedURL() {
        XCTAssertEqual(FocusAutomationURL.urlString(forMode: "work"), "lumobar://focus?mode=work")
    }

    func testURLStringRoundTrips() {
        for mode in ["work", "Deep Work", "Spécial", "a&b=c", "off", "日本語"] {
            let string = FocusAutomationURL.urlString(forMode: mode)
            guard let url = URL(string: string) else {
                XCTFail("urlString produced an invalid URL for \(mode): \(string)")
                continue
            }
            let expected: FocusAutomationURL.Event =
                mode.caseInsensitiveCompare(FocusAutomationURL.offMode) == .orderedSame ? .off : .activate(mode: mode)
            XCTAssertEqual(FocusAutomationURL.parse(url), expected, "round-trip failed for \(mode)")
        }
    }
}
