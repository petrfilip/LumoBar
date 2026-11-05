import Foundation

/// Protects the value the user is setting from stale updates.
///
/// While a slider or the color picker is being dragged — and for a short grace period after
/// the last command was sent — the lamp's state in the UI belongs to the user. Anything that
/// arrives from elsewhere in that window describes the lamp *before* the user's latest value:
/// a `props` push for an earlier command, the 60 s poll that started before the drag, the
/// result of an out-of-date command. Applying it makes the thumb jump back. Outside the window
/// (wall switch, another app) updates apply normally, and once the window closes the owner
/// reconciles with the bulb's latest known state.
///
/// Pure value type with an injectable clock so it can be unit-tested.
struct LampInteractionGuard {
    /// How long after the last activity incoming state stays ignored. Long enough for the
    /// bulb's pushes about our own commands (and `smooth` transitions) to arrive and be dropped.
    var grace: TimeInterval = 2.5
    /// Ceiling for a drag that never reports its end (view torn down, popover closed).
    var dragTimeout: TimeInterval = 8

    private var holdUntil: [String: Date] = [:]
    private var dragging: Set<String> = []

    mutating func beginDrag(_ lampID: String, now: Date) {
        dragging.insert(lampID)
        extend(lampID, now: now)
    }

    mutating func endDrag(_ lampID: String, now: Date) {
        dragging.remove(lampID)
        // The release resets the window: the long drag allowance must not outlive the drag.
        holdUntil[lampID] = now.addingTimeInterval(grace)
    }

    /// Any user activity (a preview, a command being sent, its reply) pushes the end of the
    /// window out.
    mutating func touch(_ lampID: String, now: Date) {
        extend(lampID, now: now)
    }

    mutating func clear(_ lampID: String) {
        holdUntil[lampID] = nil
        dragging.remove(lampID)
    }

    private mutating func extend(_ lampID: String, now: Date) {
        let window = dragging.contains(lampID) ? dragTimeout : grace
        holdUntil[lampID] = max(holdUntil[lampID] ?? .distantPast, now.addingTimeInterval(window))
    }

    /// `commandsPending`: commands for this lamp are queued or in flight, so the lamp's
    /// state is certainly about to change by the user's own doing.
    func isHolding(_ lampID: String, now: Date, commandsPending: Bool = false) -> Bool {
        if commandsPending { return true }
        guard let until = holdUntil[lampID] else { return false }
        return until > now
    }

    /// When the window of `lampID` currently ends (nil: not tracked).
    func holdEnd(_ lampID: String) -> Date? { holdUntil[lampID] }

    func isAnyHolding(now: Date) -> Bool {
        holdUntil.values.contains { $0 > now }
    }

    /// Picks the lamp state to publish when `incoming` (poll / push) meets the `current` one.
    /// A lamp that went offline is always reported: that is information, not a stale value.
    static func resolve(incoming: LampDevice, current: LampDevice?, holding: Bool) -> LampDevice {
        guard holding, let current, incoming.online else { return incoming }
        return current
    }
}
