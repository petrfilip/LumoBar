import XCTest
@testable import LumoBar

final class YeelightClientParseTests: XCTestCase {
    private func parse(_ line: String, id: Int = 42) -> YeelightClient.LineOutcome {
        YeelightClient.parse(line: Substring(line), requestID: id)
    }

    private func assertIgnored(_ text: String, id: Int = 42, file: StaticString = #filePath, line: UInt = #line) {
        if case .ignore = parse(text, id: id) { return }
        XCTFail("expected .ignore for \(text)", file: file, line: line)
    }

    func testMatchingIdReturnsResult() {
        guard case .result(let values) = parse(#"{"id":42,"result":["ok"]}"#) else {
            return XCTFail("expected .result")
        }
        XCTAssertEqual(values, ["ok"])
    }

    func testGetPropResultKeepsOrderAndEmptyStrings() {
        guard case .result(let values) = parse(#"{"id":42,"result":["on","80","","16711680"]}"#) else {
            return XCTFail("expected .result")
        }
        XCTAssertEqual(values, ["on", "80", "", "16711680"])
    }

    func testSurroundingWhitespaceAndCRLFAreTrimmed() {
        guard case .result(let values) = parse("  {\"id\":42,\"result\":[\"ok\"]}\r") else {
            return XCTFail("expected .result")
        }
        XCTAssertEqual(values, ["ok"])
    }

    func testPropsNotificationIsIgnored() {
        assertIgnored(#"{"method":"props","params":{"power":"on","bright":"50"}}"#)
    }

    func testOtherRequestIdIsIgnored() {
        assertIgnored(#"{"id":43,"result":["ok"]}"#)
        assertIgnored(#"{"id":43,"error":{"code":-1,"message":"nope"}}"#)
    }

    func testErrorWithMatchingIdMapsToYeelightError() {
        guard case .failure(let error) = parse(#"{"id":42,"error":{"code":-1,"message":"unsupported method"}}"#) else {
            return XCTFail("expected .failure")
        }
        guard case LampControlError.yeelight(let message) = error else {
            return XCTFail("expected LampControlError.yeelight, got \(error)")
        }
        XCTAssertEqual(message, "Yeelight: unsupported method (-1)")
        XCTAssertEqual(error.localizedDescription, message)
    }

    func testEmptyAndGarbageLinesAreIgnored() {
        assertIgnored("")
        assertIgnored("   \r")
        assertIgnored("not json at all")
        assertIgnored("{\"id\":42")          // truncated
        assertIgnored("[1,2,3]")             // not an object
    }

    func testMatchingIdWithoutResultOrErrorIsIgnored() {
        assertIgnored(#"{"id":42}"#)
    }

    func testResultWithNonStringElementsIsIgnored() {
        // YeelightResponse.result is [String]; a numeric array does not decode, so the
        // line is skipped rather than treated as an answer.
        assertIgnored(#"{"id":42,"result":[1,2]}"#)
    }
}
