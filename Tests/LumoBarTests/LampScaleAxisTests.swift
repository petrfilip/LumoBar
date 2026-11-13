import XCTest
@testable import LumoBar

/// The lamp-row temperature slider is warm (left) -> cold (right) for every provider.
final class LampScaleAxisTests: XCTestCase {
    private let hueCt = NumericCapability(code: "ct", min: 153, max: 500, step: 1)
    private let tuyaTemp = NumericCapability(code: "temp_value_v2", min: 0, max: 1000, step: 1)
    private let yeeCt = NumericCapability(code: "set_ct_abx", min: 1700, max: 6500, step: 50)

    func testKelvinRangeIsWarmFirstForEveryScale() {
        XCTAssertEqual(LampScale.kelvinRange(of: yeeCt), 1700...6500)
        XCTAssertEqual(LampScale.kelvinRange(of: hueCt), 2000...6536)
        XCTAssertEqual(LampScale.kelvinRange(of: tuyaTemp), 2700...6500)
    }

    func testWarmToColdPercentIsNotInvertedForHue() {
        XCTAssertEqual(LampScale.warmToColdPercent(native: 500, capability: hueCt), 0)    // warmest
        XCTAssertEqual(LampScale.warmToColdPercent(native: 153, capability: hueCt), 100)  // coldest
        XCTAssertEqual(LampScale.warmToColdPercent(native: 1700, capability: yeeCt), 0)
        XCTAssertEqual(LampScale.warmToColdPercent(native: 6500, capability: yeeCt), 100)
        XCTAssertEqual(LampScale.warmToColdPercent(native: 0, capability: tuyaTemp), 0)
        XCTAssertEqual(LampScale.warmToColdPercent(native: 1000, capability: tuyaTemp), 100)
    }

    func testSliderKelvinRoundTripsToNative() {
        // Slider position (Kelvin) -> native -> Kelvin stays on the same point, Hue included.
        for k in stride(from: 2000, through: 6500, by: 500) {
            let native = LampScale.nativeTemperature(kelvin: k, capability: hueCt)
            XCTAssertEqual(Double(LampScale.kelvin(native: native, capability: hueCt)), Double(k), accuracy: Double(k) * 0.01)
        }
        // Moving the slider towards cold lowers Hue's mirek.
        XCTAssertLessThan(LampScale.nativeTemperature(kelvin: 6000, capability: hueCt),
                          LampScale.nativeTemperature(kelvin: 3000, capability: hueCt))
    }

    func testKelvinStep() {
        XCTAssertEqual(LampScale.kelvinStep(of: yeeCt), 50)
        XCTAssertEqual(LampScale.kelvinStep(of: hueCt), 50)
    }

    func testNeutralWhiteIsAbout4000KOnEveryScale() {
        XCTAssertEqual(LampDevice.neutralWhite(for: yeeCt), 4000)
        XCTAssertEqual(LampDevice.neutralWhite(for: hueCt), 250)   // 1e6 / 4000 mirek
        XCTAssertEqual(LampScale.kelvin(native: LampDevice.neutralWhite(for: hueCt), capability: hueCt), 4000)
        let tuyaK = LampScale.kelvin(native: LampDevice.neutralWhite(for: tuyaTemp), capability: tuyaTemp)
        XCTAssertEqual(Double(tuyaK), 4000, accuracy: 10)
    }
}
