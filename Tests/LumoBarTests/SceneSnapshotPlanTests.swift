import XCTest
@testable import LumoBar

final class SceneSnapshotPlanTests: XCTestCase {
    private let caps = LightCapabilities(
        switchCode: "set_power",
        brightness: NumericCapability(code: "set_bright", min: 1, max: 100, step: 1),
        temperature: NumericCapability(code: "set_ct_abx", min: 1700, max: 6500, step: 50),
        colorCode: "set_hsv", colorValueScale: 1000, workModeCode: nil)

    private func lamp(power: Bool, caps: LightCapabilities? = nil) -> LampDevice {
        LampDevice(id: "yeelight:1", providerID: .yeelight, nativeID: "1", name: "L", online: true,
                   power: power, brightness: 50, temperature: 3000, color: .warm, workMode: "white",
                   capabilities: caps ?? self.caps)
    }

    private func snap(power: Bool, workMode: String?, color: HSVColor? = HSVColor(h: 200, s: 800, v: 700)) -> LampSnapshot {
        LampSnapshot(lampId: "yeelight:1", nativeID: "1", providerID: .yeelight, name: "L",
                     power: power, brightness: 60, temperature: 2700, color: color, workMode: workMode)
    }

    func testCapturedOffOnOffLampSendsNothing() {
        XCTAssertEqual(snap(power: false, workMode: "colour").steps(for: lamp(power: false)), [])
    }

    func testCapturedOffOnOnLampOnlyPowersOff() {
        XCTAssertEqual(snap(power: false, workMode: "white").steps(for: lamp(power: true)), [.power(false)])
    }

    func testCapturedOnOnOffLampPowersOnFirst() {
        XCTAssertEqual(snap(power: true, workMode: "colour").steps(for: lamp(power: false)),
                       [.power(true), .color(HSVColor(h: 200, s: 800, v: 700))])
    }

    func testWhiteSnapshotUsesTemperatureNotStaleColor() {
        XCTAssertEqual(snap(power: true, workMode: "white").steps(for: lamp(power: true)),
                       [.temperature(2700), .brightness(60)])
        XCTAssertEqual(snap(power: true, workMode: "ct").steps(for: lamp(power: true)),
                       [.temperature(2700), .brightness(60)])
    }

    func testLegacySnapshotWithoutModeFallsBackToColor() {
        XCTAssertEqual(snap(power: true, workMode: nil).steps(for: lamp(power: true)),
                       [.color(HSVColor(h: 200, s: 800, v: 700))])
    }

    func testWhiteOnlyLampIgnoresColor() {
        var white = caps
        white.colorCode = nil
        XCTAssertEqual(snap(power: true, workMode: "colour").steps(for: lamp(power: true, caps: white)),
                       [.brightness(60)])
    }
}
