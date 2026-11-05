import XCTest
@testable import LampControl

final class YeelightProviderTests: XCTestCase {
    private let bulb = YeelightBulb(id: "bulb-1", host: "192.168.1.77", port: 55443, name: "Desk")

    // MARK: propertyDictionary

    func testPropertyDictionaryZipsValuesWithKeys() {
        let dict = YeelightLightProvider.propertyDictionary(
            fromGetProp: ["on", "80", "4000", "16711680", "359", "100", "2", "Lamp"])
        XCTAssertEqual(dict, [
            "power": "on", "bright": "80", "ct": "4000", "rgb": "16711680",
            "hue": "359", "sat": "100", "color_mode": "2", "name": "Lamp"
        ])
    }

    func testPropertyDictionaryToleratesShortAndEmptyReplies() {
        XCTAssertEqual(YeelightLightProvider.propertyDictionary(fromGetProp: []), [:])
        XCTAssertEqual(YeelightLightProvider.propertyDictionary(fromGetProp: ["off", "5"]),
                       ["power": "off", "bright": "5"])
    }

    func testPropertyDictionaryIgnoresSurplusValues() {
        let values = Array(repeating: "x", count: YeelightLightProvider.propertyKeys.count + 3)
        XCTAssertEqual(YeelightLightProvider.propertyDictionary(fromGetProp: values).count,
                       YeelightLightProvider.propertyKeys.count)
    }

    // MARK: makeLamp

    func testWhiteModeLamp() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb,
            properties: ["power": "on", "bright": "80", "ct": "4000", "color_mode": "2", "hue": "0", "sat": "0"],
            online: true)
        XCTAssertTrue(lamp.online)
        XCTAssertTrue(lamp.power)
        XCTAssertEqual(lamp.brightness, 80)
        XCTAssertEqual(lamp.temperature, 4000)
        XCTAssertEqual(lamp.workMode, "white")
        XCTAssertEqual(lamp.id, "yeelight:bulb-1")
        XCTAssertEqual(lamp.nativeID, "bulb-1")
        XCTAssertEqual(lamp.providerID, .yeelight)
        XCTAssertEqual(lamp.name, "Desk")
    }

    func testRGBModeLampMapsHueSaturationAndBrightness() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb,
            properties: ["power": "on", "bright": "50", "color_mode": "1", "hue": "120", "sat": "85", "ct": "2700"],
            online: true)
        XCTAssertEqual(lamp.workMode, "colour")
        // Yeelight sat 0–100 / bright 0–100 -> app scale 0–1000.
        XCTAssertEqual(lamp.color, HSVColor(h: 120, s: 850, v: 500))
    }

    func testHSVModeLampIsColourMode() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb,
            properties: ["power": "on", "bright": "100", "color_mode": "3", "hue": "200", "sat": "60"],
            online: true)
        XCTAssertEqual(lamp.workMode, "colour")
        XCTAssertEqual(lamp.color, HSVColor(h: 200, s: 600, v: 1000))
    }

    func testPowerOffAndMissingProperties() {
        let lamp = YeelightLightProvider.makeLamp(bulb: bulb, properties: ["power": "off"], online: true)
        XCTAssertFalse(lamp.power)
        XCTAssertNil(lamp.brightness)
        XCTAssertNil(lamp.temperature)
        XCTAssertNil(lamp.color)
        XCTAssertNil(lamp.workMode)
    }

    func testOfflineLampFromEmptyProperties() {
        let lamp = YeelightLightProvider.makeLamp(bulb: bulb, properties: [:], online: false)
        XCTAssertFalse(lamp.online)
        XCTAssertFalse(lamp.power)
        XCTAssertNil(lamp.brightness)
        XCTAssertEqual(lamp.name, "Desk")
    }

    func testColorValuesAreClamped() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb,
            properties: ["bright": "0", "hue": "999", "sat": "500", "color_mode": "1"],
            online: true)
        XCTAssertEqual(lamp.color, HSVColor(h: 360, s: 1000, v: 10))
    }

    func testBrightnessDefaultsToFullInColorWhenUnknown() {
        let lamp = YeelightLightProvider.makeLamp(
            bulb: bulb, properties: ["hue": "10", "sat": "20", "color_mode": "1"], online: true)
        XCTAssertEqual(lamp.color?.v, 1000)
    }

    func testNameResolutionPrefersBulbReportedName() {
        let reported = YeelightLightProvider.makeLamp(bulb: bulb, properties: ["name": "  Kitchen \n"], online: true)
        XCTAssertEqual(reported.name, "Kitchen")

        let blank = YeelightLightProvider.makeLamp(bulb: bulb, properties: ["name": "  "], online: true)
        XCTAssertEqual(blank.name, "Desk")

        // YeelightBulb.init falls back to the host for an empty name.
        let unnamed = YeelightBulb(id: "b2", host: "10.0.0.5")
        XCTAssertEqual(YeelightLightProvider.makeLamp(bulb: unnamed, properties: [:], online: true).name, "10.0.0.5")
    }

    func testCapabilities() {
        let caps = YeelightLightProvider.makeLamp(bulb: bulb, properties: [:], online: true).capabilities
        XCTAssertEqual(caps.brightness, NumericCapability(code: "set_bright", min: 1, max: 100, step: 1))
        XCTAssertEqual(caps.temperature, NumericCapability(code: "set_ct_abx", min: 1700, max: 6500, step: 50))
        XCTAssertEqual(caps.colorValueScale, 1000)
        XCTAssertNotNil(caps.colorCode)
    }

    func testFullGetPropRoundTripToLamp() {
        let dict = YeelightLightProvider.propertyDictionary(
            fromGetProp: ["on", "30", "2700", "16711680", "0", "100", "1", ""])
        let lamp = YeelightLightProvider.makeLamp(bulb: bulb, properties: dict, online: true)
        XCTAssertTrue(lamp.power)
        XCTAssertEqual(lamp.workMode, "colour")
        XCTAssertEqual(lamp.color, HSVColor(h: 0, s: 1000, v: 300))
        XCTAssertEqual(lamp.name, "Desk")
    }
}

final class YeelightSettingsCodingTests: XCTestCase {
    func testBulbWithoutDeviceIdDecodes() throws {
        let json = #"{"id":"abc","host":"192.168.1.5","port":55443,"name":"Old bulb"}"#
        let bulb = try JSONDecoder().decode(YeelightBulb.self, from: Data(json.utf8))
        XCTAssertEqual(bulb.id, "abc")
        XCTAssertEqual(bulb.host, "192.168.1.5")
        XCTAssertEqual(bulb.port, 55443)
        XCTAssertEqual(bulb.name, "Old bulb")
        XCTAssertNil(bulb.deviceId)
    }

    func testSettingsFileWrittenBeforeDeviceIdExistedDecodes() throws {
        let json = #"{"bulbs":[{"id":"a","host":"10.0.0.2","port":55443,"name":"A"},{"id":"b","host":"10.0.0.3","port":55444,"name":"B"}]}"#
        let settings = try JSONDecoder().decode(YeelightSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.bulbs.count, 2)
        XCTAssertTrue(settings.isConfigured)
        XCTAssertEqual(settings.bulbs[1].port, 55444)
        XCTAssertTrue(settings.bulbs.allSatisfy { $0.deviceId == nil })
    }

    func testEmptySettingsIsNotConfigured() throws {
        let settings = try JSONDecoder().decode(YeelightSettings.self, from: Data(#"{"bulbs":[]}"#.utf8))
        XCTAssertFalse(settings.isConfigured)
        XCTAssertFalse(YeelightSettings().isConfigured)
    }

    func testRoundTripPreservesDeviceId() throws {
        let original = YeelightSettings(bulbs: [
            YeelightBulb(id: "x", host: "1.2.3.4", port: 55443, name: "X", deviceId: "0x00000000ABCD1234")
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(YeelightSettings.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.bulbs[0].deviceId, "0x00000000abcd1234")
    }

    func testInitDefaults() {
        let bulb = YeelightBulb(host: "192.168.1.9")
        XCTAssertEqual(bulb.port, 55443)
        XCTAssertEqual(bulb.name, "192.168.1.9")
        XCTAssertNil(bulb.deviceId)
        XCTAssertFalse(bulb.id.isEmpty)
    }
}
