import XCTest
@testable import LampControl

final class TuyaClientTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    static let tokenReply = #"{"success":true,"result":{"access_token":"tok","expire_time":7200}}"#

    private func client() throws -> TuyaClient {
        try TuyaClient(accessId: "id", accessSecret: "secret", endpoint: "https://openapi.tuyaeu.com",
                       session: StubURLProtocol.session())
    }

    private func tokenRequests() -> Int {
        StubURLProtocol.requests.filter { $0.url?.path == "/v1.0/token" }.count
    }

    func testConcurrentCallsShareOneTokenRequest() async throws {
        StubURLProtocol.handler = { request in
            if request.url?.path == "/v1.0/token" { return .init(body: Self.tokenReply, delay: 0.2) }
            return .init(body: #"{"success":true,"result":{"ok":true}}"#)
        }
        let client = try client()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { let _: TuyaOK = try await client.get("/v1.0/ping"); }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(tokenRequests(), 1)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url?.path == "/v1.0/ping" }.count, 8)
    }

    func testTokenIsReusedAcrossSequentialCalls() async throws {
        StubURLProtocol.handler = { request in
            request.url?.path == "/v1.0/token" ? .init(body: Self.tokenReply)
                                               : .init(body: #"{"success":true,"result":{"ok":true}}"#)
        }
        let client = try client()
        let _: TuyaOK = try await client.get("/v1.0/a")
        let _: TuyaOK = try await client.get("/v1.0/b")
        XCTAssertEqual(tokenRequests(), 1)
    }

    func testFailedTokenFetchIsRetriedByTheNextCall() async throws {
        let calls = LockedInt()
        StubURLProtocol.handler = { request in
            if request.url?.path == "/v1.0/token" {
                return calls.next() == 1 ? .init(body: #"{"success":false,"code":1004,"msg":"sign invalid"}"#)
                                         : .init(body: Self.tokenReply)
            }
            return .init(body: #"{"success":true,"result":{"ok":true}}"#)
        }
        let client = try client()
        do {
            let _: TuyaOK = try await client.get("/v1.0/a")
            XCTFail("expected error")
        } catch let error as TuyaAPIError {
            XCTAssertEqual(error.code, 1004)
        }
        let _: TuyaOK = try await client.get("/v1.0/a")
        XCTAssertEqual(tokenRequests(), 2)
    }

    func testAPIErrorKeepsNumericCode() async throws {
        StubURLProtocol.handler = { request in
            request.url?.path == "/v1.0/token" ? .init(body: Self.tokenReply)
                : .init(body: #"{"success":false,"code":2008,"msg":"command or value not support"}"#)
        }
        let client = try client()
        do {
            let _: TuyaOK = try await client.post("/v1.0/devices/x/commands", body: ["a": 1])
            XCTFail("expected error")
        } catch let error as TuyaAPIError {
            XCTAssertEqual(error.code, 2008)
            XCTAssertTrue(error.isUnsupportedCommand)
        }
    }

    func testUnsupportedCommandClassification() {
        XCTAssertTrue(TuyaAPIError(message: "command or value not support", code: 2008).isUnsupportedCommand)
        XCTAssertTrue(TuyaAPIError(message: "param is illegal", code: 1109).isUnsupportedCommand)
        XCTAssertFalse(TuyaAPIError(message: "token invalid", code: 1010).isUnsupportedCommand)
        XCTAssertFalse(TuyaAPIError(message: "permission deny", code: 1106).isUnsupportedCommand)
        XCTAssertTrue(TuyaAPIError(message: "Command not supported", code: nil).isUnsupportedCommand)
        XCTAssertFalse(TuyaAPIError(message: "boom", code: nil).isUnsupportedCommand)
        XCTAssertFalse(LampControlError.offline.isTuyaUnsupportedCommand)
        XCTAssertFalse(LampControlError.http(500).isTuyaUnsupportedCommand)
    }
}

struct TuyaOK: Decodable { let ok: Bool? }

final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
