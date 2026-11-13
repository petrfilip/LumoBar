import XCTest
@testable import LampControl

final class GoveeProviderTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    private let devicesJSON = #"{"data":{"devices":[{"device":"AA:BB","model":"H6001","deviceName":"Strip","controllable":true,"retrievable":true,"supportCmds":["turn","brightness"]}]}}"#
    private func stateJSON(power: String, brightness: Int) -> String {
        #"{"data":{"device":"AA:BB","model":"H6001","properties":[{"online":true},{"powerState":"\#(power)"},{"brightness":\#(brightness)}]}}"#
    }

    private func provider() -> GoveeLightProvider {
        GoveeLightProvider(client: GoveeClient(session: StubURLProtocol.session()), settings: GoveeSettings(apiKey: "k"))
    }

    private func count(_ pathSuffix: String) -> Int {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix(pathSuffix) == true }.count
    }

    func testStateFailureKeepsThePreviouslyKnownLamp() async throws {
        let failState = Box(false)
        StubURLProtocol.handler = { [devicesJSON, stateJSON] request in
            if request.url?.path.hasSuffix("/devices") == true { return .init(body: devicesJSON) }
            return failState.value ? .init(status: 429, body: #"{"message":"Too many requests"}"#)
                                   : .init(body: stateJSON("on", 70))
        }
        let provider = provider()
        let first = try await provider.syncLights()
        XCTAssertEqual(first.first?.power, true)
        XCTAssertEqual(first.first?.brightness, 70)

        failState.value = true
        let second = try await provider.syncLights()
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.power, true, "a rate-limited state call must not turn the lamp 'off'")
        XCTAssertEqual(second.first?.brightness, 70)
        XCTAssertEqual(second.first?.online, true)
    }

    func testStateFailureWithoutHistoryListsTheLampOffline() async throws {
        StubURLProtocol.handler = { [devicesJSON] request in
            request.url?.path.hasSuffix("/devices") == true ? .init(body: devicesJSON) : .init(status: 429)
        }
        let lamps = try await provider().syncLights()
        XCTAssertEqual(lamps.count, 1)
        XCTAssertEqual(lamps.first?.online, false)
        XCTAssertEqual(lamps.first?.power, false)
    }

    func testDeviceListIsFetchedOnceAcrossPolls() async throws {
        StubURLProtocol.handler = { [devicesJSON, stateJSON] request in
            request.url?.path.hasSuffix("/devices") == true ? .init(body: devicesJSON) : .init(body: stateJSON("off", 10))
        }
        let provider = provider()
        _ = try await provider.syncLights()
        _ = try await provider.syncLights()
        _ = try await provider.syncLights()
        XCTAssertEqual(count("/devices"), 1)
        XCTAssertEqual(count("/devices/state"), 3)
    }

    func testDuplicateDeviceEntriesDoNotCrash() async throws {
        let device = #"{"device":"AA:BB","model":"H6001","deviceName":"Strip","controllable":true,"retrievable":true,"supportCmds":["turn"]}"#
        StubURLProtocol.handler = { [stateJSON] request in
            request.url?.path.hasSuffix("/devices") == true
                ? .init(body: #"{"data":{"devices":[\#(device),\#(device)]}}"#)
                : .init(body: stateJSON("on", 5))
        }
        let lamps = try await provider().syncLights()
        XCTAssertEqual(lamps.count, 1)
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
