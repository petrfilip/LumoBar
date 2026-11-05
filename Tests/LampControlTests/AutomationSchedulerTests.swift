import XCTest
@testable import LampControl

@MainActor
final class AutomationSchedulerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }

    private func automation(hour: Int, minute: Int, enabled: Bool = true) -> Automation {
        Automation(name: "A", isEnabled: enabled, hour: hour, minute: minute, action: .powerOffAll)
    }

    func testFiresOnceWithinAMinute() {
        let scheduler = AutomationScheduler(calendar: calendar)
        scheduler.update(automations: [automation(hour: 7, minute: 30)])
        XCTAssertEqual(scheduler.dueAutomations(at: date(6, 7, 30, second: 0)).count, 1)
        XCTAssertTrue(scheduler.dueAutomations(at: date(6, 7, 30, second: 30)).isEmpty)
        scheduler.stop()
    }

    func testDedupSurvivesUpdateWithStaleCopy() {
        // AppState pushes its own copy (lastFiredDate nil) back in on every edit.
        let scheduler = AutomationScheduler(calendar: calendar)
        let item = automation(hour: 7, minute: 30)
        scheduler.update(automations: [item])
        XCTAssertEqual(scheduler.dueAutomations(at: date(6, 7, 30)).count, 1)
        scheduler.update(automations: [item])
        XCTAssertTrue(scheduler.dueAutomations(at: date(6, 7, 30, second: 40)).isEmpty)
        scheduler.stop()
    }

    func testFiresAgainNextDay() {
        let scheduler = AutomationScheduler(calendar: calendar)
        scheduler.update(automations: [automation(hour: 7, minute: 30)])
        XCTAssertEqual(scheduler.dueAutomations(at: date(6, 7, 30)).count, 1)
        XCTAssertEqual(scheduler.dueAutomations(at: date(7, 7, 30)).count, 1)
        scheduler.stop()
    }

    func testHonoursPersistedLastFiredDate() {
        let scheduler = AutomationScheduler(calendar: calendar)
        var item = automation(hour: 7, minute: 30)
        item.lastFiredDate = date(6, 7, 30, second: 5)
        scheduler.update(automations: [item])
        XCTAssertTrue(scheduler.dueAutomations(at: date(6, 7, 30)).isEmpty)
        scheduler.stop()
    }

    func testDisabledAndOtherMinutesDoNotFire() {
        let scheduler = AutomationScheduler(calendar: calendar)
        scheduler.update(automations: [automation(hour: 7, minute: 30, enabled: false), automation(hour: 8, minute: 0)])
        XCTAssertTrue(scheduler.dueAutomations(at: date(6, 7, 30)).isEmpty)
        XCTAssertTrue(scheduler.dueAutomations(at: date(6, 7, 31)).isEmpty)
        scheduler.stop()
    }

    func testTickCallsOnFireOnce() {
        let now = date(6, 7, 30)
        let scheduler = AutomationScheduler(calendar: calendar, now: { now })
        var fired = 0
        scheduler.onFire = { _ in fired += 1 }
        scheduler.update(automations: [automation(hour: 7, minute: 30)])
        scheduler.tick()
        scheduler.tick()
        XCTAssertEqual(fired, 1)
        scheduler.stop()
    }

    func testUpdateWhileRunningDoesNotCreateSecondTimer() {
        let scheduler = AutomationScheduler(calendar: calendar)
        let items = [automation(hour: 7, minute: 30)]
        scheduler.start(with: items)
        XCTAssertTrue(scheduler.isRunning)
        scheduler.update(automations: items)
        scheduler.update(automations: items)
        scheduler.stop()
        XCTAssertFalse(scheduler.isRunning)
    }

    func testStartAndUpdateLifecycle() {
        let scheduler = AutomationScheduler(calendar: calendar)
        scheduler.start(with: [automation(hour: 7, minute: 30, enabled: false)])
        XCTAssertFalse(scheduler.isRunning)
        scheduler.update(automations: [automation(hour: 7, minute: 30)])
        XCTAssertTrue(scheduler.isRunning)
        scheduler.update(automations: [])
        XCTAssertFalse(scheduler.isRunning)
    }
}
