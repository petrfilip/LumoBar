import XCTest
@testable import LumoBar

final class WizClientTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testGetPilotReplyDecodes() throws {
        let reply = #"{"method":"getPilot","env":"pro","result":{"mac":"a8bb","rssi":-60,"state":true,"dimming":42,"temp":2700}}"#
        let response = try WizClient.parseReply(data(reply))
        XCTAssertEqual(response.result?.state, true)
        XCTAssertEqual(response.result?.dimming, 42)
        XCTAssertEqual(response.result?.temp, 2700)
    }

    func testErrorReplyThrowsDeviceError() {
        let reply = #"{"method":"setPilot","env":"pro","error":{"code":-32602,"message":"Invalid params"}}"#
        XCTAssertThrowsError(try WizClient.parseReply(data(reply))) { error in
            // (NSLocalizedString does not resolve the app's strings under XCTest, so only the case is checked.)
            guard case LampControlError.device = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try WizClient.validateSetReply(data(reply)))
    }

    func testSetReplySuccessIsAccepted() throws {
        try WizClient.validateSetReply(data(#"{"method":"setPilot","env":"pro","result":{"success":true}}"#))
    }

    func testSetReplyWithSuccessFalseThrows() {
        XCTAssertThrowsError(try WizClient.validateSetReply(data(#"{"method":"setPilot","result":{"success":false}}"#)))
    }

    func testSetReplyThatIsNotJSONIsTolerated() throws {
        try WizClient.validateSetReply(data("ok"))
    }

    func testGetPilotWithGarbageIsInvalidResponse() {
        XCTAssertThrowsError(try WizClient.parseReply(data("nope"))) { error in
            guard case LampControlError.invalidResponse = error else { return XCTFail("\(error)") }
        }
    }

    func testOneShotResumesOnlyOnceUnderRace() async throws {
        let cleanups = LockedCounter()
        let value: Int? = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let gate = OneShot<Int>(continuation) { cleanups.increment() }
            DispatchQueue.concurrentPerform(iterations: 200) { i in
                gate.finish(i == 0 ? .failure(LampControlError.offline) : .success(i))
            }
        }
        _ = value  // either the success or the failure won; what matters is a single resume
        XCTAssertEqual(cleanups.value, 1)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
