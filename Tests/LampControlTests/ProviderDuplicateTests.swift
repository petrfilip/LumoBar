import XCTest
@testable import LampControl

/// Duplicate keys from settings or the network used to trap in `Dictionary(uniqueKeysWithValues:)`.
final class ProviderDuplicateTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    func testNanoleafDuplicateHostsSyncOnceWithoutCrashing() async throws {
        StubURLProtocol.handler = { _ in
            .init(body: #"{"name":"Shapes","state":{"on":{"value":true},"brightness":{"value":50},"colorMode":"ct","ct":{"value":4000}}}"#)
        }
        let client = NanoleafClient(session: StubURLProtocol.session())
        let device = NanoleafDevice(name: "A", host: "192.168.1.9", authToken: "tok")
        var dup = device
        dup.name = "B"
        let provider = NanoleafLightProvider(client: client, settings: NanoleafSettings(devices: [device, dup]))
        let lamps = try await provider.syncLights()
        XCTAssertEqual(lamps.count, 1)
        XCTAssertEqual(lamps.first?.name, "A")
        XCTAssertEqual(lamps.first?.power, true)
    }

    func testLifxDuplicateIdsSyncOnceWithoutCrashing() async throws {
        let light = #"{"id":"d1","label":"Desk","connected":true,"power":"on","brightness":0.5}"#
        StubURLProtocol.handler = { _ in .init(body: "[\(light),\(light)]") }
        let provider = LifxLightProvider(client: LifxClient(session: StubURLProtocol.session()),
                                         settings: LifxSettings(token: "t"))
        let lamps = try await provider.syncLights()
        XCTAssertEqual(lamps.count, 1)
    }

    func testLifxCommandsSucceedAgainstEmptyAcceptedReply() async throws {
        let light = #"{"id":"d1","label":"Desk","connected":true,"power":"off","brightness":0.5}"#
        StubURLProtocol.handler = { request in
            request.httpMethod == "PUT" ? .init(status: 202) : .init(body: "[\(light)]")
        }
        let provider = LifxLightProvider(client: LifxClient(session: StubURLProtocol.session()),
                                         settings: LifxSettings(token: "t"))
        _ = try await provider.syncLights()
        let lamp = try await provider.setPower(deviceId: "d1", value: true)
        XCTAssertTrue(lamp.power)
    }

    func testYeelightDuplicateBulbIdsSyncOnceWithoutCrashing() async throws {
        // Port 1 on loopback refuses immediately; the bulb is simply reported offline.
        let bulb = YeelightBulb(id: "same", host: "127.0.0.1", port: 1, name: "A")
        let provider = YeelightLightProvider(client: YeelightClient(timeout: 1),
                                             settings: YeelightSettings(bulbs: [bulb, bulb]))
        let lamps = try await provider.syncLights()
        XCTAssertEqual(lamps.count, 1)
        XCTAssertFalse(lamps[0].online)
    }
}
