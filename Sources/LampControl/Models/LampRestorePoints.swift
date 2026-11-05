import Foundation

/// The last state of a lamp that is known to be real, kept while the user adjusts it.
///
/// Sliders and the picker show an optimistic value immediately. If the command then fails, the
/// UI must not keep showing an unapplied preview forever: it goes back to this state (or, for
/// bulbs that push their state, to the live one — see `restoredState`).
struct LampRestorePoints {
    private var points: [String: LampDevice] = [:]

    /// Remembers `lamp` as it is *before* the first preview of an adjustment. Later previews
    /// of the same adjustment do not overwrite it.
    mutating func remember(_ lamp: LampDevice) {
        if points[lamp.id] == nil { points[lamp.id] = lamp }
    }

    /// A command succeeded: the bulb reported `lamp`, which is the new known-real state.
    mutating func confirm(_ lamp: LampDevice) {
        if points[lamp.id] != nil { points[lamp.id] = lamp }
    }

    /// The adjustment is over without a failure.
    mutating func discard(_ lampID: String) {
        points[lampID] = nil
    }

    /// Removes and returns the restore point.
    mutating func take(_ lampID: String) -> LampDevice? {
        points.removeValue(forKey: lampID)
    }

    /// What to show after a failed command: the bulb's own live state when there is one,
    /// else the remembered pre-adjustment state.
    static func restoredState(live: LampDevice?, restorePoint: LampDevice?) -> LampDevice? {
        live ?? restorePoint
    }
}
