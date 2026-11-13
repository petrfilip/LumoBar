import XCTest
@testable import LampControl

final class BulkLampActionTests: XCTestCase {
    private struct Boom: Error, Equatable { let id: String }

    private func lamp(_ id: String) -> LampDevice {
        LampDevice(id: id, providerID: .wiz, nativeID: id, name: id, online: true, power: false,
                   brightness: nil, temperature: nil, color: nil, workMode: nil, capabilities: LightCapabilities())
    }

    func testFailingLampDoesNotStopTheOthersAndEarlierUpdatesAreKept() async {
        var applied: [String] = []
        let outcome = await BulkLampAction.run(
            on: [lamp("a"), lamp("b"), lamp("c")],
            operation: { l in
                if l.id == "b" { throw Boom(id: "b") }
                return l.withPower(true)
            },
            onUpdate: { applied.append($0.id) })
        XCTAssertEqual(applied, ["a", "c"])
        XCTAssertEqual(outcome.updatedCount, 2)
        XCTAssertEqual(outcome.firstError as? Boom, Boom(id: "b"))
    }

    func testOnlyTheFirstErrorIsReported() async {
        let outcome = await BulkLampAction.run(
            on: [lamp("a"), lamp("b")],
            operation: { l in throw Boom(id: l.id) },
            onUpdate: { _ in XCTFail("nothing succeeded") })
        XCTAssertEqual(outcome.firstError as? Boom, Boom(id: "a"))
        XCTAssertEqual(outcome.updatedCount, 0)
    }

    func testAllSucceedingHasNoError() async {
        let outcome = await BulkLampAction.run(on: [lamp("a"), lamp("b")], operation: { $0 }, onUpdate: { _ in })
        XCTAssertNil(outcome.firstError)
        XCTAssertEqual(outcome.updatedCount, 2)
    }

    func testUpdatesAreAppliedAsEachLampReturns() async {
        var order: [String] = []
        _ = await BulkLampAction.run(
            on: [lamp("a"), lamp("b")],
            operation: { l in order.append("op-\(l.id)"); return l },
            onUpdate: { order.append("up-\($0.id)") })
        XCTAssertEqual(order, ["op-a", "up-a", "op-b", "up-b"])
    }

    func testCancellationStopsBetweenLampsWithoutReportingAnError() async {
        var applied: [String] = []
        let task = Task { () -> BulkLampAction.Outcome in
            await BulkLampAction.run(
                on: [lamp("a"), lamp("b"), lamp("c")],
                operation: { l in
                    if l.id == "a" { withUnsafeCurrentTask { $0?.cancel() } }
                    return l
                },
                onUpdate: { applied.append($0.id) })
        }
        let outcome = await task.value
        XCTAssertEqual(applied, ["a"])
        XCTAssertTrue(outcome.wasCancelled)
        XCTAssertNil(outcome.firstError)
    }

    func testCancellationErrorFromALampIsNotAnError() async {
        let outcome = await BulkLampAction.run(
            on: [lamp("a"), lamp("b")],
            operation: { _ in throw CancellationError() },
            onUpdate: { _ in XCTFail("nothing succeeded") })
        XCTAssertTrue(outcome.wasCancelled)
        XCTAssertNil(outcome.firstError)
    }
}
