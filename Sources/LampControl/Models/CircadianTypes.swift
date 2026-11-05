import Foundation

struct CircadianKeyframe: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    var brightness: Int      // 0–100 %
    var temperature: Int     // Kelvin

    var minuteOfDay: Int { hour * 60 + minute }
}

struct CircadianSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var applyBrightness: Bool = true
    var applyTemperature: Bool = true
    var keyframes: [CircadianKeyframe]

    static let defaultKeyframes: [CircadianKeyframe] = [
        CircadianKeyframe(hour:  6, minute: 0, brightness: 50,  temperature: 4000),
        CircadianKeyframe(hour:  9, minute: 0, brightness: 90,  temperature: 5000),
        CircadianKeyframe(hour: 12, minute: 0, brightness: 100, temperature: 5500),
        CircadianKeyframe(hour: 17, minute: 0, brightness: 80,  temperature: 4000),
        CircadianKeyframe(hour: 20, minute: 0, brightness: 55,  temperature: 3000),
        CircadianKeyframe(hour: 22, minute: 0, brightness: 25,  temperature: 2400),
    ]

    static let `default` = CircadianSettings(keyframes: defaultKeyframes)

    /// Equality ignoring the enable switch, which is saved independently of
    /// the schedule edited in Settings.
    func hasSameContent(as other: CircadianSettings) -> Bool {
        var copy = other
        copy.isEnabled = isEnabled
        return self == copy
    }

    /// Interpolated brightness + temperature for a given time-of-day in minutes.
    func values(at minuteOfDay: Int) -> (brightness: Int, temperature: Int) {
        let sorted = keyframes.sorted { $0.minuteOfDay < $1.minuteOfDay }
        guard !sorted.isEmpty else { return (80, 4000) }
        guard sorted.count > 1 else { return (sorted[0].brightness, sorted[0].temperature) }

        // Before first keyframe or after last → wrap around midnight
        if minuteOfDay <= sorted.first!.minuteOfDay {
            // interpolate between last and first across midnight
            let prev = sorted.last!; let next = sorted.first!
            let span = (24 * 60 - prev.minuteOfDay) + next.minuteOfDay
            let elapsed = (24 * 60 - prev.minuteOfDay) + minuteOfDay
            return interpolate(prev, next, t: span > 0 ? Double(elapsed) / Double(span) : 0)
        }
        if minuteOfDay >= sorted.last!.minuteOfDay {
            let prev = sorted.last!; let next = sorted.first!
            let span = (24 * 60 - prev.minuteOfDay) + next.minuteOfDay
            let elapsed = minuteOfDay - prev.minuteOfDay
            return interpolate(prev, next, t: span > 0 ? Double(elapsed) / Double(span) : 0)
        }
        // Find surrounding keyframes
        for i in 0..<(sorted.count - 1) {
            let prev = sorted[i]; let next = sorted[i + 1]
            if minuteOfDay >= prev.minuteOfDay && minuteOfDay <= next.minuteOfDay {
                let span = next.minuteOfDay - prev.minuteOfDay
                let elapsed = minuteOfDay - prev.minuteOfDay
                return interpolate(prev, next, t: span > 0 ? Double(elapsed) / Double(span) : 0)
            }
        }
        return (80, 4000)
    }

    private func interpolate(_ a: CircadianKeyframe, _ b: CircadianKeyframe, t: Double) -> (brightness: Int, temperature: Int) {
        let t = max(0, min(1, t))
        return (
            brightness:   Int(round(Double(a.brightness)   + t * Double(b.brightness   - a.brightness))),
            temperature:  Int(round(Double(a.temperature)  + t * Double(b.temperature  - a.temperature)))
        )
    }
}
