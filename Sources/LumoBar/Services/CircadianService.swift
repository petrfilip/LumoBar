import Foundation

@MainActor
final class CircadianService {
    var onApply: ((Int, Int) -> Void)?   // (brightness%, temperatureK)

    private var timer: Timer?
    private(set) var settings: CircadianSettings = .default

    func start(with settings: CircadianSettings) {
        self.settings = settings
        stop()
        guard settings.isEnabled else { return }

        applyNow()

        // Fire every 15 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop, so this is already the main actor.
            MainActor.assumeIsolated { self?.applyNow() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func applyNow() {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: Date())
        let minuteOfDay = (comps.hour ?? 12) * 60 + (comps.minute ?? 0)
        let (brightness, temp) = settings.values(at: minuteOfDay)
        onApply?(brightness, temp)
    }

    func currentValues() -> (brightness: Int, temperature: Int) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: Date())
        let minuteOfDay = (comps.hour ?? 12) * 60 + (comps.minute ?? 0)
        return settings.values(at: minuteOfDay)
    }
}
