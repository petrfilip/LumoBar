import Foundation

@MainActor
final class AutomationScheduler {
    var onFire: ((Automation) -> Void)?

    /// Single pending minute-aligned timer; `stop()` / `start()` always
    /// invalidate it, so there is never an orphaned second timer.
    private var timer: Timer?
    private var automations: [Automation] = []
    private let calendar: Calendar
    private let now: () -> Date
    /// Last time each automation fired, kept here because `onFire` only
    /// updates the owner's copy of the automations.
    private var lastFired: [UUID: Date] = [:]

    init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    var isRunning: Bool { timer != nil }

    func start(with automations: [Automation]) {
        setAutomations(automations)
        stop()
        guard automations.contains(where: \.isEnabled) else { return }
        scheduleNextTick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func update(automations: [Automation]) {
        setAutomations(automations)
        if automations.contains(where: \.isEnabled) {
            if !isRunning { scheduleNextTick() }
        } else {
            stop()
        }
    }

    private func setAutomations(_ automations: [Automation]) {
        self.automations = automations
        let ids = Set(automations.map(\.id))
        lastFired = lastFired.filter { ids.contains($0.key) }
    }

    /// Fires at the next minute boundary, then re-arms itself; one timer at a
    /// time, aligned each round so it cannot drift.
    private func scheduleNextTick() {
        timer?.invalidate()
        let current = now()
        let next = calendar.nextDate(after: current, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? current.addingTimeInterval(60)
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.timer = nil
                self.tick()
                if self.automations.contains(where: \.isEnabled) { self.scheduleNextTick() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Automations due at `date` that have not already fired in that minute.
    /// Records them as fired, so calling twice for the same minute is a no-op.
    func dueAutomations(at date: Date) -> [Automation] {
        var due: [Automation] = []
        for automation in automations where automation.isEnabled {
            guard automation.shouldFire(at: date, calendar: calendar) else { continue }
            let alreadyFired = [lastFired[automation.id], automation.lastFiredDate].contains { last in
                last.map { calendar.isDate($0, equalTo: date, toGranularity: .minute) } ?? false
            }
            if alreadyFired { continue }
            lastFired[automation.id] = date
            due.append(automation)
        }
        return due
    }

    func tick() {
        for automation in dueAutomations(at: now()) {
            onFire?(automation)
        }
    }
}
