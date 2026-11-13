import XCTest
@testable import LumoBar

final class HSVConversionTests: XCTestCase {
    private func assertRGB(_ c: HSVColor, _ expected: (Int, Int, Int), file: StaticString = #filePath, line: UInt = #line) {
        let rgb = c.rgb
        XCTAssertEqual([rgb.r, rgb.g, rgb.b], [expected.0, expected.1, expected.2], "\(c)", file: file, line: line)
    }

    func testPrimaryAndSecondaryColours() {
        assertRGB(HSVColor(h: 0, s: 1000, v: 1000), (255, 0, 0))
        assertRGB(HSVColor(h: 120, s: 1000, v: 1000), (0, 255, 0))
        assertRGB(HSVColor(h: 240, s: 1000, v: 1000), (0, 0, 255))
        assertRGB(HSVColor(h: 60, s: 1000, v: 1000), (255, 255, 0))
        assertRGB(HSVColor(h: 180, s: 1000, v: 1000), (0, 255, 255))
        assertRGB(HSVColor(h: 300, s: 1000, v: 1000), (255, 0, 255))
    }

    func testWhiteBlackAndGrey() {
        assertRGB(HSVColor(h: 200, s: 0, v: 1000), (255, 255, 255))
        assertRGB(HSVColor(h: 200, s: 500, v: 0), (0, 0, 0))
        assertRGB(HSVColor(h: 0, s: 0, v: 500), (128, 128, 128))
    }

    func testHue360WrapsToRed() {
        assertRGB(HSVColor(h: 360, s: 1000, v: 1000), (255, 0, 0))
    }

    func testOutOfRangeInputIsClamped() {
        assertRGB(HSVColor(h: 0, s: 5000, v: 5000), (255, 0, 0))
        assertRGB(HSVColor(h: -60, s: 1000, v: 1000), (255, 0, 255))
    }

    /// The old WiZ code truncated (127), the Govee code rounded (128): one rule now.
    func testChannelsRoundToNearestInsteadOfTruncating() {
        let rgb = HSVColor(h: 0, s: 0, v: 500).rgb
        XCTAssertEqual(rgb.r, 128)
        let dim = HSVColor(h: 0, s: 1000, v: 998).rgb
        XCTAssertEqual(dim.r, 254)
    }

    func testFromRGBPrimaries() {
        XCTAssertEqual(HSVColor.fromRGB(r: 255, g: 0, b: 0), HSVColor(h: 0, s: 1000, v: 1000))
        XCTAssertEqual(HSVColor.fromRGB(r: 0, g: 255, b: 0), HSVColor(h: 120, s: 1000, v: 1000))
        XCTAssertEqual(HSVColor.fromRGB(r: 0, g: 0, b: 255), HSVColor(h: 240, s: 1000, v: 1000))
        XCTAssertEqual(HSVColor.fromRGB(r: 255, g: 0, b: 255), HSVColor(h: 300, s: 1000, v: 1000))
    }

    func testFromRGBBlackAndGreyHaveNoHueOrSaturation() {
        XCTAssertEqual(HSVColor.fromRGB(r: 0, g: 0, b: 0), HSVColor(h: 0, s: 0, v: 0))
        XCTAssertEqual(HSVColor.fromRGB(r: 128, g: 128, b: 128), HSVColor(h: 0, s: 0, v: 502))
    }

    func testFromRGBUsesSuppliedValueWhenGiven() {
        let c = HSVColor.fromRGB(r: 255, g: 0, b: 0, value: 400)
        XCTAssertEqual(c, HSVColor(h: 0, s: 1000, v: 400))
    }

    func testFromRGBClampsChannels() {
        XCTAssertEqual(HSVColor.fromRGB(r: 999, g: -5, b: 0), HSVColor(h: 0, s: 1000, v: 1000))
    }

    func testYeelightPackedRGBAgreesWithSharedConversion() {
        XCTAssertEqual(HSVColor.fromYeelightRGB(0xFF8000, value: 700),
                       HSVColor.fromRGB(r: 255, g: 128, b: 0, value: 700))
        XCTAssertEqual(HSVColor.fromYeelightRGB(0xFF0000, value: 1), HSVColor(h: 0, s: 1000, v: 10))
    }

    func testRoundTripStaysWithinRoundingError() {
        for h in stride(from: 0, through: 359, by: 7) {
            for s in [200, 500, 1000] {
                let original = HSVColor(h: h, s: s, v: 1000)
                let rgb = original.rgb
                let back = HSVColor.fromRGB(r: rgb.r, g: rgb.g, b: rgb.b)
                XCTAssertEqual(back.v, 1000, "h\(h) s\(s)")
                XCTAssertLessThanOrEqual(abs(back.s - s), 6, "h\(h) s\(s)")
                let dh = min(abs(back.h - h), 360 - abs(back.h - h))
                XCTAssertLessThanOrEqual(dh, 2, "h\(h) s\(s) -> \(back)")
            }
        }
    }
}
