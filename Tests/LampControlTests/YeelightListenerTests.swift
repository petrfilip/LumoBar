import XCTest
@testable import LampControl

final class YeelightListenerTests: XCTestCase {
    private func event(_ line: String) -> YeelightNotificationListener.Event? {
        YeelightNotificationListener.event(fromLine: Data(line.utf8))
    }

    func testPropsNotificationBecomesDeltaWithStringifiedValues() {
        let line = #"{"method":"props","params":{"power":"on","bright":80,"ct":4000}}"#
        guard case .delta(let props) = event(line) else { return XCTFail("expected .delta") }
        XCTAssertEqual(props, ["power": "on", "bright": "80", "ct": "4000"])
    }

    func testSnapshotAnswerBecomesSnapshotKeyedByPropertyKeys() {
        let id = YeelightNotificationListener.snapshotRequestID
        let line = "{\"id\":\(id),\"result\":[\"on\",\"75\",\"3500\",\"16711680\",\"359\",\"100\",\"2\",\"Desk\"]}"
        guard case .snapshot(let props) = event(line) else { return XCTFail("expected .snapshot") }
        XCTAssertEqual(props["power"], "on")
        XCTAssertEqual(props["bright"], "75")
        XCTAssertEqual(props["ct"], "3500")
        XCTAssertEqual(props["color_mode"], "2")
        XCTAssertEqual(props["name"], "Desk")
        XCTAssertEqual(props.count, YeelightLightProvider.propertyKeys.count)
    }

    func testSnapshotWithMixedNumericAndStringResultIsStringified() {
        let id = YeelightNotificationListener.snapshotRequestID
        let line = "{\"id\":\(id),\"result\":[\"off\",10,\"\",\"\",\"\",\"\",1,\"\"]}"
        guard case .snapshot(let props) = event(line) else { return XCTFail("expected .snapshot") }
        XCTAssertEqual(props["power"], "off")
        XCTAssertEqual(props["bright"], "10")
        XCTAssertEqual(props["color_mode"], "1")
    }

    func testAnswerToAnotherRequestIsIgnored() {
        XCTAssertNil(event(#"{"id":1,"result":["ok"]}"#))
    }

    func testOtherNotificationMethodsAreIgnored() {
        XCTAssertNil(event(#"{"method":"nope","params":{"a":"b"}}"#))
    }

    func testEmptyPropsNotificationIsIgnored() {
        XCTAssertNil(event(#"{"method":"props","params":{}}"#))
        XCTAssertNil(event(#"{"method":"props"}"#))
    }

    func testGarbageIsIgnored() {
        XCTAssertNil(event(""))
        XCTAssertNil(event("garbage"))
        XCTAssertNil(event("[1,2]"))
        XCTAssertNil(YeelightNotificationListener.event(fromLine: Data([0xFF, 0xFE, 0x00])))
    }

    func testStringify() {
        XCTAssertEqual(YeelightNotificationListener.stringify("x" as Any), "x")
        XCTAssertEqual(YeelightNotificationListener.stringify(NSNumber(value: 12)), "12")
        XCTAssertEqual(YeelightNotificationListener.stringify(NSNumber(value: 1.5)), "1.5")
        XCTAssertEqual(YeelightNotificationListener.stringify(["a": 1, "b": "two"] as [String: Any]),
                       ["a": "1", "b": "two"])
    }

    func testMaxBackoffIsOneMinute() {
        XCTAssertEqual(YeelightNotificationListener.maxBackoff, 60)
    }
}
