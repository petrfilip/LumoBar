import XCTest
@testable import LumoBar

final class YeelightAddressTests: XCTestCase {
    func testHostWithoutPortUsesDefault() throws {
        let result = try YeelightAddress.parse("192.168.1.20")
        XCTAssertEqual(result.host, "192.168.1.20")
        XCTAssertEqual(result.port, 55443)
    }

    func testHostWithPort() throws {
        let result = try YeelightAddress.parse(" 192.168.1.20:12345 ")
        XCTAssertEqual(result.host, "192.168.1.20")
        XCTAssertEqual(result.port, 12345)
    }

    func testBoundaryPorts() throws {
        XCTAssertEqual(try YeelightAddress.parse("h:1").port, 1)
        XCTAssertEqual(try YeelightAddress.parse("h:65535").port, 65535)
    }

    func testOutOfRangePortsAreRejected() {
        for raw in ["h:0", "h:65536", "h:70000", "h:-5"] {
            XCTAssertThrowsError(try YeelightAddress.parse(raw), raw)
        }
    }

    func testNonNumericSuffixKeepsWholeStringAsHost() throws {
        let result = try YeelightAddress.parse("bulb.local:abc")
        XCTAssertEqual(result.host, "bulb.local:abc")
        XCTAssertEqual(result.port, 55443)
    }

    func testBareIPv6IsNotSplit() throws {
        let result = try YeelightAddress.parse("fe80::1")
        XCTAssertEqual(result.host, "fe80::1")
        XCTAssertEqual(result.port, 55443)
    }

    func testClientRejectsOutOfRangePortWithoutTrapping() async {
        let client = YeelightClient(timeout: 0.2)
        for port in [70000, -1, 65536, Int.max] {
            do {
                _ = try await client.sendCommand(host: "127.0.0.1", port: port, method: "get_prop", params: [])
                XCTFail("expected error for port \(port)")
            } catch {
                XCTAssertTrue(error is LampControlError)
            }
        }
    }
}
