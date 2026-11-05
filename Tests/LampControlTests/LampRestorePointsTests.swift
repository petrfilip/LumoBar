import XCTest
@testable import LampControl

final class LampRestorePointsTests: XCTestCase {
    private func lamp(power: Bool, brightness: Int) -> LampDevice {
        LampDevice(id: "yeelight:1", providerID: .yeelight, nativeID: "1", name: "L", online: true,
                   power: power, brightness: brightness, temperature: 3000, color: nil, workMode: "white",
                   capabilities: LightCapabilities())
    }

    func testFirstRememberedStateWins() {
        var points = LampRestorePoints()
        points.remember(lamp(power: false, brightness: 10))
        points.remember(lamp(power: true, brightness: 80))   // an optimistic preview
        XCTAssertEqual(points.take("yeelight:1"), lamp(power: false, brightness: 10))
        XCTAssertNil(points.take("yeelight:1"))
    }

    func testConfirmAdvancesTheRestorePoint() {
        var points = LampRestorePoints()
        points.remember(lamp(power: false, brightness: 10))
        points.confirm(lamp(power: true, brightness: 40))
        XCTAssertEqual(points.take("yeelight:1"), lamp(power: true, brightness: 40))
    }

    func testConfirmWithoutAdjustmentStoresNothing() {
        var points = LampRestorePoints()
        points.confirm(lamp(power: true, brightness: 40))
        XCTAssertNil(points.take("yeelight:1"))
    }

    func testDiscardAfterSuccess() {
        var points = LampRestorePoints()
        points.remember(lamp(power: true, brightness: 10))
        points.discard("yeelight:1")
        XCTAssertNil(points.take("yeelight:1"))
    }

    func testLiveStateBeatsRestorePoint() {
        let live = lamp(power: false, brightness: 5)
        let before = lamp(power: true, brightness: 70)
        XCTAssertEqual(LampRestorePoints.restoredState(live: live, restorePoint: before), live)
        XCTAssertEqual(LampRestorePoints.restoredState(live: nil, restorePoint: before), before)
        XCTAssertNil(LampRestorePoints.restoredState(live: nil, restorePoint: nil))
    }
}
