import Foundation

/// One command needed to bring a lamp to a captured state.
enum SnapshotStep: Equatable {
    case power(Bool)
    case temperature(Int)
    case brightness(Int)
    case color(HSVColor)
}

extension LampSnapshot {
    /// Whether the lamp was emitting white light (chosen through color temperature) when captured.
    var wasWhiteMode: Bool { workMode == "white" || workMode == "ct" }

    /// The ordered commands that bring `lamp` to this snapshot.
    ///
    /// Bulbs (Yeelight...) reject color / temperature / brightness while off, so:
    /// - captured off: only make sure the lamp is off (nothing else could be applied, and
    ///   sending it to an already-off lamp used to throw);
    /// - captured on: switch on first when needed, then apply the captured look. A lamp
    ///   captured in white mode gets its temperature (and brightness), never the stale hue
    ///   the bulb keeps reporting.
    func steps(for lamp: LampDevice) -> [SnapshotStep] {
        guard power else { return lamp.power ? [.power(false)] : [] }

        var steps: [SnapshotStep] = []
        if !lamp.power { steps.append(.power(true)) }

        if wasWhiteMode, let temperature, lamp.capabilities.temperature != nil {
            steps.append(.temperature(temperature))
            if let brightness, lamp.capabilities.brightness != nil {
                steps.append(.brightness(brightness))
            }
        } else if let color, lamp.capabilities.colorCode != nil {
            steps.append(.color(color))
        } else if let brightness, lamp.capabilities.brightness != nil {
            steps.append(.brightness(brightness))
        } else if let temperature, lamp.capabilities.temperature != nil {
            steps.append(.temperature(temperature))
        }
        return steps
    }
}
