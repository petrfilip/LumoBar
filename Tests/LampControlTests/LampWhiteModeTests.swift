import XCTest
@testable import LampControl

/// Regression tests for "pick white, move the temperature slider, a color gets selected".
/// The bulb keeps reporting its last hue/sat in CT mode and `set_hsv` leaves it in
/// `color_mode` 3, so the mode must come from `color_mode`, never from `color`.
final class LampWhiteModeTests: XCTestCase {
    private let bulb = YeelightBulb(id: "bulb-1", host: "192.168.1.77", port: 55443, name: "Desk")

    func testColorModeMapping() {
        XCTAssertEqual(YeelightLightProvider.workMode(forColorMode: "1"), "colour")
        XCTAssertEqual(YeelightLightProvider.workMode(forColorMode: "2"), "white")
        XCTAssertEqual(YeelightLightProvider.workMode(forColorMode: "3"), "colour")
        XCTAssertNil(YeelightLightProvider.workMode(forColorMode: nil))
        XCTAssertNil(YeelightLightProvider.workMode(forColorMode: ""))
    }

    func testWhiteModeKeepsStaleHueButIsWhite() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb,
            properties: ["power": "on", "bright": "20", "ct": "4000", "hue": "199", "sat": "42", "color_mode": "2"],
            online: true)
        XCTAssertTrue(lamp.isWhiteMode)
        XCTAssertNotNil(lamp.color, "last color stays available for the picker's memory")
    }

    /// Mirrors YeelightLiveSync's delta merge: a `props` push with only `ct`/`bright` must keep the mode.
    func testCtOnlyDeltaKeepsWhiteMode() {
        var props = ["power": "on", "bright": "20", "ct": "4000", "hue": "199", "sat": "42", "color_mode": "2"]
        let before = YeelightLightProvider.makeLamp(bulb: bulb, properties: props, online: true)
        props["ct"] = "3000"
        props["bright"] = "55"
        let after = YeelightLightProvider.makeLamp(bulb: bulb, properties: props, online: true)
        XCTAssertTrue(before.isWhiteMode)
        XCTAssertTrue(after.isWhiteMode)
        XCTAssertEqual(after.temperature, 3000)
    }

    func testHSVDeltaSwitchesToColour() {
        var props = ["power": "on", "bright": "20", "ct": "3000", "hue": "199", "sat": "42", "color_mode": "2"]
        props["color_mode"] = "3"
        props["hue"] = "100"
        XCTAssertFalse(YeelightLightProvider.makeLamp(bulb: bulb, properties: props, online: true).isWhiteMode)
    }

    func testPreviewingWhiteSwatchOnTunableLampIsWhiteMode() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb,
            properties: ["power": "on", "bright": "40", "ct": "2700", "hue": "199", "sat": "42", "color_mode": "3"],
            online: true)
        XCTAssertFalse(lamp.isWhiteMode)

        let previewed = lamp.previewingColor(.white)
        XCTAssertTrue(previewed.isWhiteMode)
        XCTAssertEqual(previewed.temperature, 4000)
        XCTAssertEqual(previewed.brightness, 100)   // white swatch = full value
    }

    func testPreviewingRealColorIsColourMode() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb,
            properties: ["power": "on", "bright": "40", "ct": "2700", "color_mode": "2"],
            online: true)
        let previewed = lamp.previewingColor(HSVColor(h: 120, s: 850, v: 400))
        XCTAssertFalse(previewed.isWhiteMode)
        XCTAssertEqual(previewed.color, HSVColor(h: 120, s: 850, v: 400))
    }

    func testPreviewingWhiteOnColorOnlyLampStaysColour() {
        var lamp = YeelightLightProvider.makeLamp(bulb: bulb, properties: ["power": "on", "color_mode": "3"], online: true)
        lamp.capabilities.temperature = nil
        XCTAssertFalse(lamp.previewingColor(.white).isWhiteMode)
    }

    func testTemperaturePreviewKeepsWhiteMode() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb, properties: ["power": "on", "bright": "40", "ct": "4000", "color_mode": "2"], online: true)
        XCTAssertTrue(lamp.withTemperature(5500).isWhiteMode)
    }

    func testNanoleafCtCountsAsWhite() {
        var lamp = YeelightLightProvider.makeLamp(bulb: bulb, properties: ["power": "on"], online: true)
        lamp.workMode = "ct"
        XCTAssertTrue(lamp.isWhiteMode)
    }

    func testBrightnessForColorValue() {
        let cap = NumericCapability(code: "set_bright", min: 1, max: 100, step: 1)
        XCTAssertEqual(LampDevice.brightness(forColorValue: 1000, capability: cap), 100)
        XCTAssertEqual(LampDevice.brightness(forColorValue: 500, capability: cap), 51)
        XCTAssertEqual(LampDevice.brightness(forColorValue: 0, capability: cap), 2)
    }
}
