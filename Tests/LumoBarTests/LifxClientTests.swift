import XCTest
@testable import LumoBar

final class LifxClientTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    private func client() -> LifxClient { LifxClient(session: StubURLProtocol.session()) }
    private let command = LifxStateCommand(power: "on", duration: 0.2, fast: true)

    func testSetStateAccepts202WithEmptyBody() async throws {
        StubURLProtocol.handler = { _ in .init(status: 202) }
        try await client().setState(token: "t", selector: "id:abc", command: command)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "PUT")
    }

    func testSetStateAccepts204AndNormalResultsBody() async throws {
        StubURLProtocol.handler = { _ in .init(status: 204) }
        try await client().setState(token: "t", selector: "id:abc", command: command)
        StubURLProtocol.handler = { _ in .init(status: 207, body: #"{"results":[{"id":"abc","status":"ok"}]}"#) }
        try await client().setState(token: "t", selector: "id:abc", command: command)
    }

    func testSetStateThrowsOnHTTPErrorWithMessage() async {
        StubURLProtocol.handler = { _ in .init(status: 401, body: #"{"error":"Bad token"}"#) }
        do {
            try await client().setState(token: "t", selector: "id:abc", command: command)
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"))
            XCTAssertTrue(error.localizedDescription.contains("Bad token"))
        }
    }

    func testListLightsStillDecodes() async throws {
        StubURLProtocol.handler = { _ in
            .init(status: 200, body: #"[{"id":"d1","label":"Desk","connected":true,"power":"on","brightness":0.5,"color":{"hue":10,"saturation":0.5,"kelvin":3500}}]"#)
        }
        let lights = try await client().listLights(token: "t")
        XCTAssertEqual(lights.map(\.label), ["Desk"])
    }
}
