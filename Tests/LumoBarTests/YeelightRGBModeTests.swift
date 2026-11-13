import XCTest
@testable import LumoBar

/// color_mode 1 (RGB) bulbs report the colour in `rgb`; hue/sat are stale.
final class YeelightRGBModeTests: XCTestCase {
    private let bulb = YeelightBulb(id: "bulb-1", host: "192.168.1.77", port: 55443, name: "Desk")

    func testRGBDecoding() {
        XCTAssertEqual(HSVColor.fromYeelightRGB(16711680, value: 500), HSVColor(h: 0, s: 1000, v: 500))
        XCTAssertEqual(HSVColor.fromYeelightRGB(0x00FF00, value: 1000), HSVColor(h: 120, s: 1000, v: 1000))
        XCTAssertEqual(HSVColor.fromYeelightRGB(0x0000FF, value: 1000), HSVColor(h: 240, s: 1000, v: 1000))
        XCTAssertEqual(HSVColor.fromYeelightRGB(0xFFFFFF, value: 1000).s, 0)
        XCTAssertEqual(HSVColor.fromYeelightRGB(0xFF00FF, value: 1000).h, 300)
        XCTAssertEqual(HSVColor.fromYeelightRGB(0xFF0080, value: 1000).h, 330)
    }

    func testMode1UsesRGBNotStaleHueSat() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb,
            properties: ["power": "on", "bright": "40", "ct": "4000", "rgb": "255", "hue": "10", "sat": "90", "color_mode": "1"],
            online: true)
        XCTAssertEqual(lamp.color, HSVColor(h: 240, s: 1000, v: 400))
        XCTAssertEqual(lamp.workMode, "colour")
    }

    func testMode3KeepsHueSat() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb,
            properties: ["power": "on", "bright": "40", "rgb": "255", "hue": "10", "sat": "90", "color_mode": "3"],
            online: true)
        XCTAssertEqual(lamp.color, HSVColor(h: 10, s: 900, v: 400))
    }

    /// A push delta with only rgb + color_mode, merged like YeelightLiveSync does.
    func testRGBDeltaOverStaleHSV() {
        var props = ["power": "on", "bright": "40", "ct": "4000", "rgb": "16711680", "hue": "10", "sat": "90", "color_mode": "3"]
        props["rgb"] = "65280"
        props["color_mode"] = "1"
        let lamp = YeelightLightProvider.makeLamp(bulb: bulb, properties: props, online: true)
        XCTAssertEqual(lamp.color?.h, 120)
        XCTAssertEqual(lamp.color?.s, 1000)
    }
}
