import XCTest
@testable import LampControl

final class LampScaleTests: XCTestCase {
    private let hueBri = NumericCapability(code: "bri", min: 1, max: 254, step: 1)
    private let hueCt = NumericCapability(code: "ct", min: 153, max: 500, step: 1)
    private let lifxBri = NumericCapability(code: "brightness", min: 1, max: 1000, step: 1)
    private let lifxK = NumericCapability(code: "kelvin", min: 1500, max: 9000, step: 50)
    private let tuyaBri = NumericCapability(code: "bright_value_v2", min: 10, max: 1000, step: 1)
    private let tuyaTemp = NumericCapability(code: "temp_value_v2", min: 0, max: 1000, step: 1)
    private let yeeBri = NumericCapability(code: "set_bright", min: 1, max: 100, step: 1)
    private let yeeCt = NumericCapability(code: "set_ct_abx", min: 1700, max: 6500, step: 50)
    private let nanoCt = NumericCapability(code: "ct", min: 1200, max: 6500, step: 100)

    func testBrightnessPercentToNative() {
        XCTAssertEqual(LampScale.nativeBrightness(percent: 0, capability: hueBri), 1)
        XCTAssertEqual(LampScale.nativeBrightness(percent: 100, capability: hueBri), 254)
        XCTAssertEqual(LampScale.nativeBrightness(percent: 50, capability: lifxBri), 501)
        XCTAssertEqual(LampScale.nativeBrightness(percent: 100, capability: lifxBri), 1000)
        XCTAssertEqual(LampScale.nativeBrightness(percent: 0, capability: tuyaBri), 10)
        XCTAssertEqual(LampScale.nativeBrightness(percent: 100, capability: tuyaBri), 1000)
        XCTAssertEqual(LampScale.nativeBrightness(percent: 55, capability: yeeBri), 55)
    }

    func testBrightnessClampsOutOfRangePercent() {
        XCTAssertEqual(LampScale.nativeBrightness(percent: -20, capability: hueBri), 1)
        XCTAssertEqual(LampScale.nativeBrightness(percent: 250, capability: hueBri), 254)
    }

    func testBrightnessRoundTrip() {
        for cap in [hueBri, lifxBri, tuyaBri, yeeBri] {
            for percent in stride(from: 0, through: 100, by: 10) {
                let native = LampScale.nativeBrightness(percent: percent, capability: cap)
                XCTAssertEqual(Double(LampScale.brightnessPercent(native: native, capability: cap)),
                               Double(percent), accuracy: 1)
            }
        }
    }

    func testScaleDetection() {
        XCTAssertEqual(LampScale.temperatureScale(of: hueCt), .mirek)
        XCTAssertEqual(LampScale.temperatureScale(of: nanoCt), .kelvin)
        XCTAssertEqual(LampScale.temperatureScale(of: lifxK), .kelvin)
        XCTAssertEqual(LampScale.temperatureScale(of: yeeCt), .kelvin)
        XCTAssertEqual(LampScale.temperatureScale(of: tuyaTemp), .relative)
    }

    func testKelvinCapabilitiesPassThroughClamped() {
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 4000, capability: yeeCt), 4000)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 2400, capability: yeeCt), 2400)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 1000, capability: yeeCt), 1700)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 9000, capability: yeeCt), 6500)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 5000, capability: lifxK), 5000)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 2400, capability: nanoCt), 2400)
    }

    func testHueUsesMirek() {
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 4000, capability: hueCt), 250)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 2500, capability: hueCt), 400)
        // Warmer / colder than Hue can do: clamp.
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 1000, capability: hueCt), 500)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 10000, capability: hueCt), 153)
    }

    func testRelativeScaleNormalisesLinearly() {
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 2700, capability: tuyaTemp), 0)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 6500, capability: tuyaTemp), 1000)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 4600, capability: tuyaTemp), 500)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 2000, capability: tuyaTemp), 0)
        XCTAssertEqual(LampScale.nativeTemperature(kelvin: 9000, capability: tuyaTemp), 1000)
    }

    func testInverseTemperature() {
        XCTAssertEqual(LampScale.kelvin(native: 4000, capability: yeeCt), 4000)
        XCTAssertEqual(LampScale.kelvin(native: 250, capability: hueCt), 4000)
        // Cold Hue (low mirek) must read as cold, warm Hue as warm.
        XCTAssertGreaterThan(LampScale.kelvin(native: 153, capability: hueCt),
                             LampScale.kelvin(native: 500, capability: hueCt))
        XCTAssertEqual(LampScale.kelvin(native: 0, capability: tuyaTemp), 2700)
        XCTAssertEqual(LampScale.kelvin(native: 1000, capability: tuyaTemp), 6500)
        XCTAssertEqual(LampScale.kelvin(native: 500, capability: tuyaTemp), 4600)
    }

    func testTemperatureRoundTrip() {
        for kelvin in [2700, 3000, 4000, 5000, 6000, 6500] {
            for cap in [yeeCt, lifxK, nanoCt] {
                let native = LampScale.nativeTemperature(kelvin: kelvin, capability: cap)
                XCTAssertEqual(LampScale.kelvin(native: native, capability: cap), kelvin)
            }
            let hue = LampScale.kelvin(native: LampScale.nativeTemperature(kelvin: kelvin, capability: hueCt), capability: hueCt)
            XCTAssertEqual(Double(hue), Double(kelvin), accuracy: Double(kelvin) * 0.01)
            let tuya = LampScale.kelvin(native: LampScale.nativeTemperature(kelvin: kelvin, capability: tuyaTemp), capability: tuyaTemp)
            XCTAssertEqual(Double(tuya), Double(kelvin), accuracy: 4)
        }
    }
}
