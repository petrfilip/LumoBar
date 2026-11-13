import XCTest
import AppKit
@testable import LumoBar

final class ColorTests: XCTestCase {
    // MARK: HSVColor

    func testScaledForTuyaColourDataV2UsesByte255Scale() {
        let c = HSVColor(h: 400, s: 1000, v: 1000).scaled(for: "colour_data", valueScale: 255)
        XCTAssertEqual(c, HSVColor(h: 360, s: 255, v: 255))
        XCTAssertEqual(HSVColor(h: 0, s: 500, v: 0).scaled(for: "colour_data", valueScale: 255),
                       HSVColor(h: 0, s: 128, v: 1))
    }

    func testScaledForOtherCodesClampsTo1000() {
        XCTAssertEqual(HSVColor(h: -5, s: 2000, v: -1).scaled(for: "colour_data_v2"),
                       HSVColor(h: 0, s: 1000, v: 0))
        XCTAssertEqual(HSVColor(h: 120, s: 500, v: 500).scaled(for: "colour_data", valueScale: 1000),
                       HSVColor(h: 120, s: 500, v: 500))
    }

    func testNormalizedFromByteScale() {
        XCTAssertEqual(HSVColor(h: 120, s: 255, v: 255).normalized(from: "colour_data", valueScale: 255),
                       HSVColor(h: 120, s: 1000, v: 1000))
        // Value is floored at 10 so a normalized color is never fully black.
        XCTAssertEqual(HSVColor(h: 0, s: 0, v: 0).normalized(from: "colour_data", valueScale: 255).v, 10)
    }

    func testScaledNormalizedRoundTripOnByteScale() {
        let original = HSVColor(h: 200, s: 600, v: 800)
        let back = original.scaled(for: "colour_data", valueScale: 255).normalized(from: "colour_data", valueScale: 255)
        XCTAssertEqual(back.h, original.h)
        XCTAssertLessThanOrEqual(abs(back.s - original.s), 4)
        XCTAssertLessThanOrEqual(abs(back.v - original.v), 4)
    }

    func testWithValueClamps() {
        let c = HSVColor(h: 10, s: 20, v: 500)
        XCTAssertEqual(c.withValue(0).v, 10)
        XCTAssertEqual(c.withValue(5000).v, 1000)
        XCTAssertEqual(c.withValue(300), HSVColor(h: 10, s: 20, v: 300))
    }

    func testVividKeepsHueAndSaturationAndMaximisesValue() {
        XCTAssertEqual(HSVColor(h: 90, s: 300, v: 100).vivid(), HSVColor(h: 90, s: 300, v: 1000))
    }

    func testIsNearWhite() {
        XCTAssertTrue(HSVColor.white.isNearWhite)
        XCTAssertTrue(HSVColor(h: 100, s: 59, v: 1000).isNearWhite)
        XCTAssertFalse(HSVColor(h: 100, s: 60, v: 1000).isNearWhite)
    }

    // MARK: Quick colors

    func testQuickColorsAreValidAndDistinct() {
        let colors = HSVColor.quickColors
        XCTAssertEqual(colors.count, 6)
        XCTAssertEqual(Set(colors).count, colors.count)
        XCTAssertEqual(colors.first, .white)
        for c in colors {
            XCTAssertTrue((0...360).contains(c.h))
            XCTAssertTrue((0...1000).contains(c.s))
            XCTAssertTrue((10...1000).contains(c.v))
        }
    }

    func testQuickColorNamesAlignWithColors() {
        // L10n.quickColorName maps by index; every quick color must resolve to a name.
        XCTAssertEqual(HSVColor.quickColors.count, 6, "L10n.quickColorName has 6 keys")
        for c in HSVColor.quickColors {
            XCTAssertFalse(L10n.quickColorName(c).isEmpty)
        }
        XCTAssertEqual(L10n.quickColorName(HSVColor(h: 1, s: 2, v: 3)), "")
    }

    // MARK: kelvinColor

    private func rgb(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let c = color.usingColorSpace(.deviceRGB)!
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    func testCandleLightIsReddishWithNoBlue() {
        let c = rgb(StatusItemIcon.kelvinColor(1000))
        XCTAssertEqual(c.r, 1, accuracy: 0.01)
        XCTAssertEqual(c.b, 0, accuracy: 0.01)
        XCTAssertLessThan(c.g, 0.4)
    }

    func testDaylightIsNearlyWhite() {
        let c = rgb(StatusItemIcon.kelvinColor(6500))
        XCTAssertGreaterThan(c.r, 0.95)
        XCTAssertGreaterThan(c.g, 0.95)
        XCTAssertGreaterThan(c.b, 0.95)
    }

    func testWarmToCoolMonotonicInBlue() {
        let blues = stride(from: 1500, through: 7000, by: 500).map { rgb(StatusItemIcon.kelvinColor($0)).b }
        XCTAssertEqual(blues, blues.sorted())
        XCTAssertGreaterThan(blues.last!, blues.first!)
    }

    func testCoolKelvinIsBluish() {
        let c = rgb(StatusItemIcon.kelvinColor(10_000))
        XCTAssertEqual(c.b, 1, accuracy: 0.01)
        XCTAssertLessThan(c.r, c.b)
    }

    func testKelvinInputIsClamped() {
        let low = rgb(StatusItemIcon.kelvinColor(-50)), floor = rgb(StatusItemIcon.kelvinColor(1000))
        XCTAssertEqual(low.r, floor.r, accuracy: 0.001)
        XCTAssertEqual(low.g, floor.g, accuracy: 0.001)
        let high = rgb(StatusItemIcon.kelvinColor(1_000_000)), ceil = rgb(StatusItemIcon.kelvinColor(40_000))
        XCTAssertEqual(high.b, ceil.b, accuracy: 0.001)
        XCTAssertEqual(high.r, ceil.r, accuracy: 0.001)
    }

    // MARK: StatusItemIcon.tint

    private func lamp(workMode: String?, color: HSVColor?, temperature: Int?, colorCode: String? = "set_hsv",
                      tempRange: (Int, Int)? = (1700, 6500)) -> LampDevice {
        LampDevice(
            id: "t:1", providerID: .yeelight, nativeID: "1", name: "L", online: true, power: true,
            brightness: 100, temperature: temperature, color: color, workMode: workMode,
            capabilities: LightCapabilities(
                switchCode: nil, brightness: nil,
                temperature: tempRange.map { NumericCapability(code: "t", min: $0.0, max: $0.1, step: 1) },
                colorCode: colorCode, colorValueScale: 1000, workModeCode: nil))
    }

    func testTintInColorModeUsesHueAndSaturationButIgnoresBrightness() throws {
        let dim = lamp(workMode: "colour", color: HSVColor(h: 120, s: 1000, v: 50), temperature: nil)
        let c = rgb(try XCTUnwrap(StatusItemIcon.tint(for: dim)))
        // Calibrated -> device RGB conversion shifts channels slightly, hence the loose bounds.
        XCTAssertGreaterThan(c.g, 0.9)
        XCTAssertLessThan(c.r, 0.1)
        XCTAssertLessThan(c.b, 0.1)
    }

    func testTintInWhiteModeUsesTemperature() throws {
        let warm = lamp(workMode: "white", color: HSVColor(h: 120, s: 1000, v: 1000), temperature: 2000)
        let cool = lamp(workMode: "white", color: nil, temperature: 6500)
        let w = rgb(try XCTUnwrap(StatusItemIcon.tint(for: warm)))
        let k = rgb(try XCTUnwrap(StatusItemIcon.tint(for: cool)))
        XCTAssertLessThan(w.b, k.b)
    }

    func testTintWithoutAnyColorInformationIsNil() {
        XCTAssertNil(StatusItemIcon.tint(for: lamp(workMode: nil, color: nil, temperature: nil, tempRange: nil)))
        // Temperature value present but no capability to interpret it.
        XCTAssertNil(StatusItemIcon.tint(for: lamp(workMode: nil, color: nil, temperature: 3000, tempRange: nil)))
    }

    func testTintForVendorScaleTemperatureMapsOntoKelvin() throws {
        // Tuya-style 0–1000 scale: 0 -> 2700 K, 1000 -> 6500 K.
        let warm = lamp(workMode: "white", color: nil, temperature: 0, colorCode: nil, tempRange: (0, 1000))
        let cool = lamp(workMode: "white", color: nil, temperature: 1000, colorCode: nil, tempRange: (0, 1000))
        let w = rgb(try XCTUnwrap(StatusItemIcon.tint(for: warm)))
        let k = rgb(try XCTUnwrap(StatusItemIcon.tint(for: cool)))
        let expectedWarm = rgb(StatusItemIcon.kelvinColor(2700))
        XCTAssertEqual(w.b, expectedWarm.b, accuracy: 0.001)
        XCTAssertGreaterThan(k.b, w.b)
    }
}
