import XCTest
@testable import LampControl

final class FocusAutomationURLTests: XCTestCase {
    private func parse(_ string: String) -> FocusAutomationURL.Event? {
        URL(string: string).flatMap(FocusAutomationURL.parse)
    }

    func testParsesActivate() {
        XCTAssertEqual(parse("lampcontrol://focus?mode=work"), .activate(mode: "work"))
    }

    func testSchemeAndHostAreCaseInsensitive() {
        XCTAssertEqual(parse("LampControl://FOCUS?mode=Sleep"), .activate(mode: "Sleep"))
    }

    func testModeValueKeepsItsCase() {
        XCTAssertEqual(parse("lampcontrol://focus?mode=DeepWork"), .activate(mode: "DeepWork"))
    }

    func testOffIsCaseInsensitive() {
        XCTAssertEqual(parse("lampcontrol://focus?mode=off"), .off)
        XCTAssertEqual(parse("lampcontrol://focus?mode=OFF"), .off)
        XCTAssertEqual(parse("lampcontrol://focus?mode=Off"), .off)
    }

    func testPercentEncodedModeIsDecoded() {
        XCTAssertEqual(parse("lampcontrol://focus?mode=Deep%20Work"), .activate(mode: "Deep Work"))
        XCTAssertEqual(parse("lampcontrol://focus?mode=Sp%C3%A9cial"), .activate(mode: "Spécial"))
    }

    func testModeIsTrimmed() {
        XCTAssertEqual(parse("lampcontrol://focus?mode=%20work%20"), .activate(mode: "work"))
        XCTAssertEqual(parse("lampcontrol://focus?mode=%20off%20"), .off)
    }

    func testExtraQueryItemsAreIgnored() {
        XCTAssertEqual(parse("lampcontrol://focus?foo=1&mode=work&bar=2"), .activate(mode: "work"))
    }

    func testRejectsWrongScheme() {
        XCTAssertNil(parse("https://focus?mode=work"))
        XCTAssertNil(parse("other://focus?mode=work"))
    }

    func testRejectsWrongHost() {
        XCTAssertNil(parse("lampcontrol://scene?mode=work"))
        XCTAssertNil(parse("lampcontrol:///?mode=work"))
    }

    func testRejectsMissingOrEmptyMode() {
        XCTAssertNil(parse("lampcontrol://focus"))
        XCTAssertNil(parse("lampcontrol://focus?mode="))
        XCTAssertNil(parse("lampcontrol://focus?mode=%20%20"))
        XCTAssertNil(parse("lampcontrol://focus?other=work"))
    }

    func testURLStringBuildsExpectedURL() {
        XCTAssertEqual(FocusAutomationURL.urlString(forMode: "work"), "lampcontrol://focus?mode=work")
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
