import XCTest
@testable import LumoBar

final class TuyaProviderTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    private func device(_ id: String, online: Bool = true) -> String {
        #"{"id":"\#(id)","name":"Lamp \#(id)","online":\#(online),"status":[{"code":"switch_led","value":true}]}"#
    }

    private let simpleSpec = #"{"success":true,"result":{"functions":[{"code":"switch_led","type":"Boolean","values":"{}"}]}}"#
    private let colourSpec = #"{"success":true,"result":{"functions":[{"code":"switch_led","type":"Boolean","values":"{}"},{"code":"temp_value_v2","type":"Integer","values":"{\"min\":0,\"max\":1000,\"step\":1}"},{"code":"colour_data_v2","type":"Json","values":"{}"},{"code":"work_mode","type":"Enum","values":"{}"}]}}"#

    private func provider() throws -> TuyaLightProvider {
        let client = try TuyaClient(accessId: "id", accessSecret: "s", endpoint: "https://openapi.tuyaeu.com",
                                    session: StubURLProtocol.session())
        return TuyaLightProvider(client: client, uid: "uid")
    }

    private func count(_ needle: String) -> Int {
        StubURLProtocol.requests.filter { $0.url?.path.contains(needle) == true }.count
    }

    /// Routes the Tuya endpoints; `spec` decides the reply per device id.
    private func route(devices: [String], spec: @escaping (String) -> StubURLProtocol.Reply,
                       commands: @escaping () -> StubURLProtocol.Reply = { .init(body: #"{"success":true,"result":true}"#) }) {
        let list = "[" + devices.joined(separator: ",") + "]"
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/v1.0/token" { return .init(body: TuyaClientTests.tokenReply) }
            if path.hasSuffix("/devices") { return .init(body: #"{"success":true,"result":\#(list)}"#) }
            if path.hasSuffix("/specifications") {
                let id = path.components(separatedBy: "/").dropLast().last ?? ""
                return spec(id)
            }
            if path.hasSuffix("/commands") { return commands() }
            return .init(status: 404)
        }
    }

    func testSpecificationsAreFetchedOncePerDeviceAcrossPolls() async throws {
        route(devices: [device("a"), device("b")], spec: { [simpleSpec] _ in .init(body: simpleSpec) })
        let provider = try provider()
        _ = try await provider.syncLights()
        _ = try await provider.syncLights()
        _ = try await provider.syncLights()
        XCTAssertEqual(count("/specifications"), 2)
    }

    func testFailingSpecificationSkipsOnlyThatDevice() async throws {
        route(devices: [device("a"), device("bad")], spec: { [simpleSpec] id in
            id == "bad" ? .init(status: 500) : .init(body: simpleSpec)
        })
        let lamps = try await provider().syncLights()
        XCTAssertEqual(lamps.map(\.nativeID), ["a"])
    }

    func testEverySpecificationFailingRethrowsInsteadOfReportingNoLamps() async throws {
        route(devices: [device("a"), device("b")], spec: { _ in .init(status: 500) })
        do {
            _ = try await provider().syncLights()
            XCTFail("expected error")
        } catch LampControlError.http(let status) {
            XCTAssertEqual(status, 500)
        }
    }

    func testDuplicateDevicesAndFunctionCodesDoNotCrash() async throws {
        let dupSpec = #"{"success":true,"result":{"functions":[{"code":"switch_led","type":"Boolean","values":"{}"},{"code":"switch_led","type":"Boolean","values":"{}"}]}}"#
        route(devices: [device("a"), device("a")], spec: { _ in .init(body: dupSpec) })
        let lamps = try await provider().syncLights()
        XCTAssertEqual(lamps.count, 1)
    }

    func testModeFallbackRetriesWithoutWorkModeOnUnsupportedCommandCode() async throws {
        let posts = LockedInt()
        route(devices: [device("a")], spec: { [colourSpec] _ in .init(body: colourSpec) }, commands: {
            posts.next() == 1 ? .init(body: #"{"success":false,"code":2008,"msg":"command or value not support"}"#)
                              : .init(body: #"{"success":true,"result":true}"#)
        })
        let provider = try provider()
        _ = try await provider.syncLights()
        let lamp = try await provider.setTemperature(deviceId: "a", value: 500)
        XCTAssertEqual(lamp.temperature, 500)
        XCTAssertEqual(count("/commands"), 2)
        let bodies = StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/commands") == true }
            .compactMap { $0.httpBody ?? $0.httpBodyStream.flatMap(Self.read) }
            .map { String(decoding: $0, as: UTF8.self) }
        XCTAssertTrue(bodies[0].contains("work_mode"))
        XCTAssertFalse(bodies[1].contains("work_mode"))
    }

    func testTransportErrorIsNotRetriedAndPassesThroughUnchanged() async throws {
        route(devices: [device("a")], spec: { [colourSpec] _ in .init(body: colourSpec) },
              commands: { .init(status: 503) })
        let provider = try provider()
        _ = try await provider.syncLights()
        do {
            _ = try await provider.setTemperature(deviceId: "a", value: 500)
            XCTFail("expected error")
        } catch LampControlError.http(let status) {
            XCTAssertEqual(status, 503)
        }
        XCTAssertEqual(count("/commands"), 1, "a transport error must not trigger the work_mode fallback")
    }

    func testOtherTuyaErrorCodesAreNotRetried() async throws {
        route(devices: [device("a")], spec: { [colourSpec] _ in .init(body: colourSpec) },
              commands: { .init(body: #"{"success":false,"code":1106,"msg":"permission deny"}"#) })
        let provider = try provider()
        _ = try await provider.syncLights()
        do {
            _ = try await provider.setTemperature(deviceId: "a", value: 500)
            XCTFail("expected error")
        } catch let error as TuyaAPIError {
            XCTAssertEqual(error.code, 1106)
            XCTAssertNotNil(error.commandCodes)
        }
        XCTAssertEqual(count("/commands"), 1)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
