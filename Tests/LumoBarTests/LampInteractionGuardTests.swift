import XCTest
@testable import LumoBar

final class LampInteractionGuardTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    func testIdleLampIsNotHeld() {
        let guardState = LampInteractionGuard()
        XCTAssertFalse(guardState.isHolding("a", now: t0))
        XCTAssertFalse(guardState.isAnyHolding(now: t0))
    }

    func testHeldDuringDragEvenWithoutMovement() {
        var guardState = LampInteractionGuard()
        guardState.beginDrag("a", now: t0)
        // Mouse held still for longer than the post-release grace period: still the user's.
        XCTAssertTrue(guardState.isHolding("a", now: t0.addingTimeInterval(guardState.grace + 1)))
    }

    func testDragThatNeverEndsEventuallyReleases() {
        var guardState = LampInteractionGuard()
        guardState.beginDrag("a", now: t0)
        XCTAssertFalse(guardState.isHolding("a", now: t0.addingTimeInterval(guardState.dragTimeout + 0.1)))
    }

    func testGraceStartsAtRelease() {
        var guardState = LampInteractionGuard()
        guardState.beginDrag("a", now: t0)
        let release = t0.addingTimeInterval(5)
        guardState.endDrag("a", now: release)
        XCTAssertTrue(guardState.isHolding("a", now: release.addingTimeInterval(guardState.grace - 0.1)))
        XCTAssertFalse(guardState.isHolding("a", now: release.addingTimeInterval(guardState.grace + 0.1)))
    }

    func testActivityExtendsAndNeverShortensTheWindow() {
        var guardState = LampInteractionGuard()
        guardState.touch("a", now: t0)
        guardState.touch("a", now: t0.addingTimeInterval(2))
        XCTAssertTrue(guardState.isHolding("a", now: t0.addingTimeInterval(2 + guardState.grace - 0.1)))
        // An earlier timestamp (out-of-order reply) must not pull the end back.
        guardState.touch("a", now: t0)
        XCTAssertTrue(guardState.isHolding("a", now: t0.addingTimeInterval(2 + guardState.grace - 0.1)))
    }

    func testPendingCommandsHoldRegardlessOfTime() {
        let guardState = LampInteractionGuard()
        XCTAssertTrue(guardState.isHolding("a", now: t0, commandsPending: true))
    }

    func testLampsAreIndependent() {
        var guardState = LampInteractionGuard()
        guardState.beginDrag("a", now: t0)
        XCTAssertTrue(guardState.isHolding("a", now: t0))
        XCTAssertFalse(guardState.isHolding("b", now: t0), "genuine changes of other lamps still apply")
        XCTAssertTrue(guardState.isAnyHolding(now: t0))
    }

    func testClearEndsTheWindow() {
        var guardState = LampInteractionGuard()
        guardState.beginDrag("a", now: t0)
        guardState.clear("a")
        XCTAssertFalse(guardState.isHolding("a", now: t0))
        XCTAssertNil(guardState.holdEnd("a"))
    }

    // MARK: resolve

    private func lamp(brightness: Int, online: Bool = true) -> LampDevice {
        var lamp = LampWhiteModeTests.sampleLamp()
        lamp.brightness = brightness
        lamp.online = online
        return lamp
    }

    func testStaleIncomingStateIsDroppedWhileHolding() {
        let current = lamp(brightness: 80)      // the user's value
        let stale = lamp(brightness: 20)        // what the poll saw before
        XCTAssertEqual(LampInteractionGuard.resolve(incoming: stale, current: current, holding: true), current)
    }

    func testExternalChangeAppliesOutsideTheWindow() {
        let current = lamp(brightness: 80)
        let external = lamp(brightness: 20)     // wall switch / other app
        XCTAssertEqual(LampInteractionGuard.resolve(incoming: external, current: current, holding: false), external)
    }

    func testOfflineIsAlwaysReported() {
        let current = lamp(brightness: 80)
        let offline = lamp(brightness: 80, online: false)
        XCTAssertEqual(LampInteractionGuard.resolve(incoming: offline, current: current, holding: true), offline)
    }

    func testUnknownLampIsTakenAsIs() {
        let incoming = lamp(brightness: 10)
        XCTAssertEqual(LampInteractionGuard.resolve(incoming: incoming, current: nil, holding: true), incoming)
    }
}
