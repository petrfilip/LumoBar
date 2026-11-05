import XCTest
@testable import LampControl

final class LampOrderTests: XCTestCase {
    func testEmptyOrderYieldsKnownLamps() {
        XCTAssertEqual(LampOrder.normalized([], knownIds: ["a", "b"]), ["a", "b"])
    }

    func testNewLampsAreAppendedAndUnknownDropped() {
        XCTAssertEqual(LampOrder.normalized(["b", "gone", "a", "b"], knownIds: ["a", "b", "c"]), ["b", "a", "c"])
    }

    func testNewlyAddedLampCanBeMoved() {
        // Order was saved with a, b; c was added later and is not in it.
        let moved = LampOrder.moving("c", onto: "a", in: ["a", "b"], knownIds: ["a", "b", "c"])
        XCTAssertEqual(moved, ["c", "a", "b"])
    }

    func testDropOntoNewlyAddedLamp() {
        let moved = LampOrder.moving("a", onto: "c", in: ["a", "b"], knownIds: ["a", "b", "c"])
        XCTAssertEqual(moved, ["b", "a", "c"])
    }

    func testMovingDownAndUp() {
        XCTAssertEqual(LampOrder.moving("a", onto: "c", in: ["a", "b", "c"], knownIds: ["a", "b", "c"]), ["b", "a", "c"])
        XCTAssertEqual(LampOrder.moving("c", onto: "a", in: ["a", "b", "c"], knownIds: ["a", "b", "c"]), ["c", "a", "b"])
    }

    func testNoOpCases() {
        XCTAssertNil(LampOrder.moving("a", onto: "a", in: [], knownIds: ["a"]))
        XCTAssertNil(LampOrder.moving("x", onto: "a", in: [], knownIds: ["a"]))
    }
}
