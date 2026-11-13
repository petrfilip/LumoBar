import XCTest
@testable import LumoBar

final class HueClientTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    private let settings = HueSettings(bridgeID: "b", bridgeIP: "192.168.1.2", username: "user")
    private let unauthorized = #"[{"error":{"type":1,"address":"/lights","description":"unauthorized user"}}]"#

    private func client() -> HueClient { HueClient(session: StubURLProtocol.session()) }

    func testLightsDecodeNormalReply() async throws {
        StubURLProtocol.handler = { _ in
            .init(body: #"{"1":{"name":"Desk","state":{"on":true,"bri":100,"reachable":true}}}"#)
        }
        let lights = try await client().lights(settings: settings)
        XCTAssertEqual(lights["1"]?.name, "Desk")
    }

    func testInvalidUserOnLightsMapsToConfigurationError() async {
        StubURLProtocol.handler = { [unauthorized] _ in .init(body: unauthorized) }
        do {
            _ = try await client().lights(settings: settings)
            XCTFail("expected error")
        } catch LampControlError.configuration {
            // mapped to the localized "pair the bridge again" message
        } catch {
            XCTFail("expected .configuration, got \(error)")
        }
    }

    func testInvalidUserOnSetStateMapsToConfigurationError() async {
        StubURLProtocol.handler = { [unauthorized] _ in .init(body: unauthorized) }
        do {
            try await client().setState(settings: settings, lightID: "1", state: HueStateCommand(on: true))
            XCTFail("expected error")
        } catch LampControlError.configuration {
        } catch {
            XCTFail("expected .configuration, got \(error)")
        }
    }

    func testOtherApiErrorOnSetStateStaysADeviceError() async {
        StubURLProtocol.handler = { _ in
            .init(body: #"[{"error":{"type":201,"address":"/lights/1/state/bri","description":"parameter not modifiable"}}]"#)
        }
        do {
            try await client().setState(settings: settings, lightID: "1", state: HueStateCommand(on: true))
            XCTFail("expected error")
        } catch LampControlError.device(let message) {
            XCTAssertTrue(message.contains("parameter not modifiable"))
        } catch {
            XCTFail("expected .device, got \(error)")
        }
    }

    func testSuccessReplyOnSetStateIsAccepted() async throws {
        StubURLProtocol.handler = { _ in .init(body: #"[{"success":{"/lights/1/state/on":true}}]"#) }
        try await client().setState(settings: settings, lightID: "1", state: HueStateCommand(on: true))
    }

    func testPairingStillReportsLinkButtonError() async {
        StubURLProtocol.handler = { _ in
            .init(body: #"[{"error":{"type":101,"address":"","description":"link button not pressed"}}]"#)
        }
        do {
            _ = try await client().createUser(bridgeIP: "192.168.1.2")
            XCTFail("expected error")
        } catch LampControlError.configuration(let message) {
            XCTAssertTrue(message.contains("link button not pressed"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRequestsUseHTTPNotHTTPS() async throws {
        StubURLProtocol.handler = { _ in .init(body: "{}") }
        _ = try await client().lights(settings: settings)
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.scheme, "http")
    }
}
