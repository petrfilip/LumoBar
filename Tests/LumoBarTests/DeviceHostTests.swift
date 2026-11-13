import XCTest
@testable import LumoBar

final class DeviceHostTests: XCTestCase {
    func testSameHostIsDuplicate() {
        XCTAssertTrue(DeviceHost.isDuplicate("192.168.1.55", among: ["192.168.1.10", "192.168.1.55"]))
    }

    func testWhitespaceAndCaseAreIgnored() {
        XCTAssertTrue(DeviceHost.isDuplicate("  Bulb.local ", among: ["bulb.LOCAL"]))
    }

    func testDifferentHostIsNotDuplicate() {
        XCTAssertFalse(DeviceHost.isDuplicate("192.168.1.56", among: ["192.168.1.5", "192.168.1.55"]))
    }

    func testEmptyListHasNoDuplicate() {
        XCTAssertFalse(DeviceHost.isDuplicate("192.168.1.55", among: []))
    }
}
