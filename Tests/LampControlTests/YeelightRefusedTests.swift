import Network
import XCTest
@testable import LampControl

final class YeelightRefusedTests: XCTestCase {
    func testConnectionRefusedIsRecognised() {
        XCTAssertTrue(YeelightClient.isConnectionRefused(.posix(.ECONNREFUSED)))
        XCTAssertFalse(YeelightClient.isConnectionRefused(.posix(.ETIMEDOUT)))
        XCTAssertFalse(YeelightClient.isConnectionRefused(.posix(.EHOSTUNREACH)))
    }

    func testRefusedAndOtherFailuresMapToYeelightErrors() {
        guard case LampControlError.yeelight = YeelightClient.connectionError(.posix(.ECONNREFUSED)) else {
            return XCTFail("refused should be a yeelight error")
        }
        guard case LampControlError.yeelight(let message) = YeelightClient.connectionError(.posix(.ETIMEDOUT)) else {
            return XCTFail("other failures should stay yeelight errors")
        }
        XCTAssertTrue(message.hasPrefix("Yeelight: "))
    }

    /// Loopback port 1 has no listener: the bulb-side equivalent of LAN Control being off.
    func testRefusedPortFailsFastInsteadOfWaitingForTheTimeout() async {
        let client = YeelightClient(timeout: 10)
        let start = Date()
        do {
            _ = try await client.sendCommand(host: "127.0.0.1", port: 1, method: "get_prop", params: ["power"])
            XCTFail("expected an error")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(start), 5, "should not wait for the 10 s timeout")
            guard case LampControlError.yeelight = error else { return XCTFail("\(error)") }
        }
    }
}
