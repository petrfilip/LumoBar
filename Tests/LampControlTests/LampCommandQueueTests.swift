import XCTest
@testable import LampControl

final class CoalescingBufferTests: XCTestCase {
    func testKeepsOnlyTheNewestValueOfAKind() {
        var buffer = CoalescingBuffer()
        for value in 1...100 { buffer.submit(.brightness(value), isFinal: false) }
        XCTAssertEqual(buffer.pendingCommand(of: .brightness), .brightness(100))
        XCTAssertEqual(buffer.takeNext()?.command, .brightness(100))
        XCTAssertNil(buffer.takeNext(), "nothing else was pending")
    }

    func testKindsAreDeliveredInFirstTouchedOrderWithLatestValues() {
        var buffer = CoalescingBuffer()
        buffer.submit(.brightness(10), isFinal: false)
        buffer.submit(.temperature(3000), isFinal: false)
        buffer.submit(.brightness(20), isFinal: true)
        XCTAssertEqual(buffer.takeNext(), CoalescingBuffer.Entry(command: .brightness(20), isFinal: true))
        buffer.finish()
        XCTAssertEqual(buffer.takeNext()?.command, .temperature(3000))
    }

    func testOnlyOneCommandInFlight() {
        var buffer = CoalescingBuffer()
        buffer.submit(.brightness(10), isFinal: false)
        buffer.submit(.color(.white), isFinal: false)
        XCTAssertNotNil(buffer.takeNext())
        XCTAssertNil(buffer.takeNext(), "must wait for the reply of the first command")
        XCTAssertFalse(buffer.isIdle)
        buffer.finish()
        XCTAssertNotNil(buffer.takeNext())
        buffer.finish()
        XCTAssertTrue(buffer.isIdle)
    }

    func testSubmitWhileInFlightKeepsTheNewValuePending() {
        var buffer = CoalescingBuffer()
        buffer.submit(.brightness(10), isFinal: false)
        _ = buffer.takeNext()
        buffer.submit(.brightness(55), isFinal: true)
        XCTAssertTrue(buffer.hasPending)
        buffer.finish()
        XCTAssertEqual(buffer.takeNext(), CoalescingBuffer.Entry(command: .brightness(55), isFinal: true))
    }
}

final class CommandPacerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testFirstCommandIsImmediate() {
        let pacer = CommandPacer(policy: .yeelight)
        XCTAssertEqual(pacer.earliestSend(now: t0, isFinal: false), t0)
    }

    func testMinimumIntervalBetweenCommands() {
        var pacer = CommandPacer(policy: .yeelight)
        pacer.recordSend(at: t0)
        XCTAssertEqual(pacer.earliestSend(now: t0.addingTimeInterval(0.1), isFinal: false), t0.addingTimeInterval(0.5))
        XCTAssertEqual(pacer.earliestSend(now: t0.addingTimeInterval(0.1), isFinal: true), t0.addingTimeInterval(0.5))
        XCTAssertEqual(pacer.earliestSend(now: t0.addingTimeInterval(2), isFinal: false), t0.addingTimeInterval(2))
    }

    func testNoPolicyMeansNoPacing() {
        var pacer = CommandPacer(policy: nil)
        pacer.recordSend(at: t0)
        XCTAssertEqual(pacer.earliestSend(now: t0, isFinal: false), t0)
    }

    func testWindowCeilingDelaysIntermediateButNotFinalCommands() {
        var pacer = CommandPacer(minInterval: 0.1, maxPerWindow: 5, window: 60)
        for i in 0..<5 { pacer.recordSend(at: t0.addingTimeInterval(Double(i) * 0.2)) }
        let now = t0.addingTimeInterval(1)
        // The 6th intermediate command has to wait until the first one left the window.
        XCTAssertEqual(pacer.earliestSend(now: now, isFinal: false), t0.addingTimeInterval(60))
        // The final value is only subject to the minimum interval.
        XCTAssertEqual(pacer.earliestSend(now: now, isFinal: true), now)
    }

    /// Simulates a minute-long drag (events at 60 Hz) against the Yeelight policy and checks
    /// the bulb's quota is never approached.
    func testSustainedDragStaysWithinTheYeelightQuota() {
        let policy = LiveUpdatePolicy.yeelight
        var pacer = CommandPacer(policy: policy)
        var now = t0
        var sent: [Date] = []
        let end = t0.addingTimeInterval(120)
        while now < end {
            // A drag event is always pending (latest-wins): send as soon as the pacer allows.
            let next = pacer.earliestSend(now: now, isFinal: false)
            now = next
            sent.append(now)
            pacer.recordSend(at: now)
            now = now.addingTimeInterval(0.01)   // reply latency
        }
        for (a, b) in zip(sent, sent.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), policy.minInterval - 0.0001)
        }
        for start in sent {
            let inWindow = sent.filter { $0 >= start && $0 < start.addingTimeInterval(60) }.count
            XCTAssertLessThanOrEqual(inWindow, policy.maxPerWindow)
        }
        // Below the ~144/min quota with plenty of room, and still close to 2/s at the start.
        XCTAssertLessThan(Double(policy.maxPerWindow), 144)
    }
}

@MainActor
final class LampCommandQueueTests: XCTestCase {
    private final class Clock {
        var time = Date(timeIntervalSince1970: 2_000_000)
    }

    private struct Boom: Error {}

    private func waitUntilIdle(_ queue: LampCommandQueue, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 {
            if queue.isAllIdle { return }
            await Task.yield()
        }
        XCTFail("queue did not become idle", file: file, line: line)
    }

    func testBurstIsCoalescedToTheLastValue() async {
        let clock = Clock()
        var performed: [LampCommand] = []
        let queue = LampCommandQueue(now: { clock.time }, sleep: { clock.time.addTimeInterval($0) }) { _, command, _ in
            performed.append(command)
            return nil
        }
        for value in 1...200 { queue.submit(lampID: "l", command: .brightness(value), isFinal: false, policy: .yeelight) }
        queue.submit(lampID: "l", command: .brightness(77), isFinal: true, policy: .yeelight)
        await waitUntilIdle(queue)
        XCTAssertEqual(performed, [.brightness(77)])
    }

    func testSustainedDragRespectsPolicyAndEndsOnTheFinalValue() async {
        let clock = Clock()
        let start = clock.time
        var sends: [(time: Date, value: Int)] = []
        var counter = 0
        let queueBox = QueueBox()

        // While the pump sleeps or a command is in flight, the "user" keeps dragging at 60 Hz
        // for a minute, then lets go.
        let advance: (TimeInterval) -> Void = { duration in
            let steps = max(1, Int(duration / (1.0 / 60.0)))
            for _ in 0..<steps {
                clock.time.addTimeInterval(duration / Double(steps))
                if clock.time.timeIntervalSince(start) < 60 {
                    counter += 1
                    queueBox.queue?.submit(lampID: "l", command: .brightness(counter), isFinal: false, policy: .yeelight)
                }
            }
        }
        let queue = LampCommandQueue(now: { clock.time }, sleep: { advance($0) }) { _, command, _ in
            if case .brightness(let value) = command { sends.append((clock.time, value)) }
            advance(0.05)   // reply latency, during which the drag goes on
            return nil
        }
        queueBox.queue = queue
        queue.submit(lampID: "l", command: .brightness(0), isFinal: false, policy: .yeelight)
        await waitUntilIdle(queue)
        queue.submit(lampID: "l", command: .brightness(9_999), isFinal: true, policy: .yeelight)
        await waitUntilIdle(queue)

        XCTAssertGreaterThan(sends.count, 40, "the lamp must actually follow the drag")
        for (a, b) in zip(sends, sends.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.time.timeIntervalSince(a.time), 0.5 - 0.0001)
            XCTAssertGreaterThan(b.value, a.value, "an older value must never be sent after a newer one")
        }
        for first in sends {
            let inWindow = sends.filter { $0.time >= first.time && $0.time < first.time.addingTimeInterval(60) }.count
            XCTAssertLessThanOrEqual(inWindow, LiveUpdatePolicy.yeelight.maxPerWindow + 1)   // +1: the final value
        }
        XCTAssertEqual(sends.last?.value, 9_999)
    }

    func testIntermediateTransitionMatchesIntervalAndFinalIsShort() async {
        let clock = Clock()
        var transitions: [TimeInterval] = []
        let queue = LampCommandQueue(now: { clock.time }, sleep: { clock.time.addTimeInterval($0) }) { _, _, transition in
            transitions.append(transition)
            return nil
        }
        queue.submit(lampID: "l", command: .brightness(10), isFinal: false, policy: .yeelight)
        await waitUntilIdle(queue)
        queue.submit(lampID: "l", command: .brightness(20), isFinal: true, policy: .yeelight)
        await waitUntilIdle(queue)
        XCTAssertEqual(transitions, [0.5, LampCommandQueue.finalTransition])
    }

    func testResultsOfSupersededCommandsAreNotApplied() async {
        let clock = Clock()
        var applied: [Int] = []
        var lampBox: QueueBox?
        lampBox = QueueBox()
        let queue = LampCommandQueue(now: { clock.time }, sleep: { clock.time.addTimeInterval($0) }) { _, command, _ in
            guard case .brightness(let value) = command else { return nil }
            if value == 1 {
                // The user moves on while the first command is still in flight.
                lampBox?.queue?.submit(lampID: "l", command: .brightness(2), isFinal: true, policy: nil)
                await Task.yield()
            }
            var lamp = LampWhiteModeTests.sampleLamp()
            lamp.brightness = value
            return lamp
        }
        lampBox?.queue = queue
        queue.onApplied = { _, lamp in applied.append(lamp.brightness ?? -1) }
        queue.submit(lampID: "l", command: .brightness(1), isFinal: false, policy: nil)
        await waitUntilIdle(queue)
        XCTAssertEqual(applied, [2])
    }

    func testFailureIsReportedAndDropsPendingCommands() async {
        let clock = Clock()
        var failures = 0
        var performed = 0
        let queue = LampCommandQueue(now: { clock.time }, sleep: { clock.time.addTimeInterval($0) }) { _, _, _ in
            performed += 1
            throw Boom()
        }
        queue.onFailure = { _, _ in failures += 1 }
        queue.submit(lampID: "l", command: .brightness(1), isFinal: false, policy: nil)
        queue.submit(lampID: "l", command: .temperature(3000), isFinal: false, policy: nil)
        await waitUntilIdle(queue)
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(performed, 1)
        XCTAssertTrue(queue.isIdle("l"))
    }

    func testLampsHaveIndependentLanes() async {
        let clock = Clock()
        var performed: [String] = []
        let queue = LampCommandQueue(now: { clock.time }, sleep: { clock.time.addTimeInterval($0) }) { lampID, _, _ in
            performed.append(lampID)
            return nil
        }
        queue.submit(lampID: "a", command: .brightness(1), isFinal: true, policy: .yeelight)
        queue.submit(lampID: "b", command: .brightness(1), isFinal: true, policy: .yeelight)
        await waitUntilIdle(queue)
        XCTAssertEqual(Set(performed), ["a", "b"])
        XCTAssertEqual(clock.time, Date(timeIntervalSince1970: 2_000_000), "a second lamp must not wait for the first one's interval")
    }

    private final class QueueBox {
        var queue: LampCommandQueue?
    }
}

extension LampWhiteModeTests {
    static func sampleLamp() -> LampDevice {
        YeelightLightProvider.makeLamp(
            bulb: YeelightBulb(id: "bulb-1", host: "192.168.1.77", port: 55443, name: "Desk"),
            properties: ["power": "on", "bright": "50", "ct": "4000", "color_mode": "2"],
            online: true)
    }
}
