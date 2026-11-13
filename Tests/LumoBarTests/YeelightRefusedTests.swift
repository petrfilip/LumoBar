import Network
import XCTest
@testable import LumoBar

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
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.hasPrefix("Yeelight: "), "the provider name is added by the sync banner")
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

final class YeelightLivePollSkipTests: XCTestCase {
    /// Port 1 on loopback refuses: a bulb that was actually asked would come back offline.
    private let bulb = YeelightBulb(id: "live-1", host: "127.0.0.1", port: 1, name: "Live")
    private let other = YeelightBulb(id: "quiet-2", host: "127.0.0.1", port: 1, name: "Quiet")

    func testBulbsWithLiveStateAreNotPolled() async throws {
        let live: [String: String] = ["power": "on", "bright": "40", "color_mode": "2", "ct": "3000"]
        let provider = YeelightLightProvider(
            client: YeelightClient(timeout: 2),
            settings: YeelightSettings(bulbs: [bulb, other]),
            liveState: { id in id == "live-1" ? live : nil })

        let lamps = try await provider.syncLights()

        let liveLamp = try XCTUnwrap(lamps.first { $0.nativeID == "live-1" })
        XCTAssertTrue(liveLamp.online, "state came from the listener, no get_prop was needed")
        XCTAssertTrue(liveLamp.power)
        XCTAssertEqual(liveLamp.brightness, 40)
        let quietLamp = try XCTUnwrap(lamps.first { $0.nativeID == "quiet-2" })
        XCTAssertFalse(quietLamp.online, "no live state: the bulb is polled (and refuses here)")
    }
}
