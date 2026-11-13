import Foundation

// Live (while dragging) lamp updates.
//
// A slider or the color picker produces a value per mouse event (~60 Hz). Bulbs cannot take
// that — a Yeelight drops connections past ~60 commands/min per connection and ~144/min in
// total — so values are *coalesced*: per lamp and per kind of command only the most recent
// value is ever kept, commands of one lamp are sent strictly one at a time (so a slow reply can
// never be overtaken by, or overwrite, a newer one) and a pacer spaces them out.
//
// The pure parts (`LampCommand`, `LiveUpdatePolicy`, `CommandPacer`, `CoalescingBuffer`) hold
// all the decisions and are unit-tested; `LampCommandQueue` is only the thin async driver.

/// What the user is adjusting. One pending slot per kind per lamp.
enum LampCommandKind: Hashable {
    case brightness
    case temperature
    case color
}

enum LampCommand: Equatable {
    case brightness(Int)
    case temperature(Int)
    case color(HSVColor)

    var kind: LampCommandKind {
        switch self {
        case .brightness: return .brightness
        case .temperature: return .temperature
        case .color: return .color
        }
    }
}

/// How fast a provider can be fed while the user drags. Providers without a policy only get
/// the final value when the user lets go (the historical behaviour).
struct LiveUpdatePolicy: Equatable {
    /// Minimum gap between two commands to one lamp; also the length of the `smooth`
    /// transition of intermediate commands so consecutive steps blend into a continuous fade.
    var minInterval: TimeInterval
    /// Hard ceiling of *intermediate* commands per `window`, for quota-limited bulbs.
    var maxPerWindow: Int
    var window: TimeInterval = 60

    /// Yeelight: 2 commands/s is 120/min, under the ~144/min per-bulb quota; the 100/min
    /// ceiling keeps headroom for the listener's snapshot, polls and the final commands.
    static let yeelight = LiveUpdatePolicy(minInterval: 0.5, maxPerWindow: 100, window: 60)
}

/// Decides when the next command to a lamp may be sent.
struct CommandPacer {
    var minInterval: TimeInterval
    var maxPerWindow: Int
    var window: TimeInterval
    private(set) var sendTimes: [Date] = []

    init(minInterval: TimeInterval, maxPerWindow: Int = .max, window: TimeInterval = 60) {
        self.minInterval = minInterval
        self.maxPerWindow = maxPerWindow
        self.window = window
    }

    init(policy: LiveUpdatePolicy?) {
        self.init(minInterval: policy?.minInterval ?? 0,
                  maxPerWindow: policy?.maxPerWindow ?? .max,
                  window: policy?.window ?? 60)
    }

    /// Earliest instant (>= `now`) at which a command may go out. The last value of a drag
    /// (`isFinal`) is exempt from the per-window ceiling: it must always arrive promptly.
    func earliestSend(now: Date, isFinal: Bool) -> Date {
        var earliest = now
        if let last = sendTimes.last {
            earliest = max(earliest, last.addingTimeInterval(minInterval))
        }
        if !isFinal, maxPerWindow > 0, sendTimes.count >= maxPerWindow {
            let blocking = sendTimes[sendTimes.count - maxPerWindow]
            earliest = max(earliest, blocking.addingTimeInterval(window))
        }
        return earliest
    }

    mutating func recordSend(at time: Date) {
        sendTimes.append(time)
        // Only the last `maxPerWindow` timestamps (or those within the window) can matter.
        let cutoff = time.addingTimeInterval(-window)
        sendTimes.removeAll { $0 < cutoff }
        if maxPerWindow < Int.max, sendTimes.count > maxPerWindow {
            sendTimes.removeFirst(sendTimes.count - maxPerWindow)
        }
    }
}

/// Latest-value-wins buffer of one lamp: at most one pending command per kind, delivered in
/// the order the kinds were first touched, one at a time.
struct CoalescingBuffer {
    struct Entry: Equatable {
        var command: LampCommand
        /// The user let go: nothing newer of this kind is coming.
        var isFinal: Bool
    }

    private var pending: [LampCommandKind: Entry] = [:]
    private var order: [LampCommandKind] = []
    private(set) var isInFlight = false

    var hasPending: Bool { !order.isEmpty }
    var isIdle: Bool { !hasPending && !isInFlight }

    func pendingCommand(of kind: LampCommandKind) -> LampCommand? { pending[kind]?.command }

    /// Whether the next entry to be sent is a final one (used to pick the pacing rule).
    var nextIsFinal: Bool {
        guard let kind = order.first else { return false }
        return pending[kind]?.isFinal ?? false
    }

    /// Keeps only the newest value of the command's kind.
    mutating func submit(_ command: LampCommand, isFinal: Bool) {
        let kind = command.kind
        pending[kind] = Entry(command: command, isFinal: isFinal)
        if !order.contains(kind) { order.append(kind) }
    }

    /// Removes and returns the next command and marks the lamp busy.
    mutating func takeNext() -> Entry? {
        guard !isInFlight, let kind = order.first else { return nil }
        order.removeFirst()
        let entry = pending.removeValue(forKey: kind)
        isInFlight = entry != nil
        return entry
    }

    mutating func finish() { isInFlight = false }

    mutating func removeAll() {
        pending.removeAll()
        order.removeAll()
    }
}

/// Async driver. One lane per lamp; each lane runs at most one pump task.
@MainActor
final class LampCommandQueue {
    /// Sends one command and returns the lamp state the provider reports afterwards.
    /// Throwing aborts nothing else: the failure is reported through `onFailure`.
    typealias Perform = (_ lampID: String, _ command: LampCommand, _ transition: TimeInterval) async throws -> LampDevice?

    private final class Lane {
        var buffer = CoalescingBuffer()
        var pacer: CommandPacer
        var task: Task<Void, Never>?
        init(pacer: CommandPacer) { self.pacer = pacer }
    }

    /// Transition of final commands: short but not abrupt.
    static let finalTransition: TimeInterval = 0.25

    private var lanes: [String: Lane] = [:]
    private let now: () -> Date
    private let sleep: (TimeInterval) async -> Void
    private let perform: Perform

    /// A command finished and nothing newer of its kind is waiting: the returned lamp is
    /// the freshest state and may be shown. Never called for superseded commands.
    var onApplied: ((String, LampDevice) -> Void)?
    var onFailure: ((String, Error) -> Void)?
    /// A lane just ran out of work.
    var onIdle: ((String) -> Void)?

    init(now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) },
         perform: @escaping Perform) {
        self.now = now
        self.sleep = sleep
        self.perform = perform
    }

    func isIdle(_ lampID: String) -> Bool { lanes[lampID]?.buffer.isIdle ?? true }
    var isAllIdle: Bool { lanes.values.allSatisfy { $0.buffer.isIdle } }

    func pendingCommand(_ lampID: String, kind: LampCommandKind) -> LampCommand? {
        lanes[lampID]?.buffer.pendingCommand(of: kind)
    }

    /// Queues `command`, replacing any older one of the same kind that has not gone out yet.
    func submit(lampID: String, command: LampCommand, isFinal: Bool, policy: LiveUpdatePolicy?) {
        let lane = lanes[lampID] ?? Lane(pacer: CommandPacer(policy: policy))
        lanes[lampID] = lane
        if let policy {
            lane.pacer.minInterval = policy.minInterval
            lane.pacer.maxPerWindow = policy.maxPerWindow
            lane.pacer.window = policy.window
        }
        lane.buffer.submit(command, isFinal: isFinal)
        guard lane.task == nil else { return }
        lane.task = Task { [weak self] in await self?.pump(lampID: lampID, lane: lane) }
    }

    /// Drops everything not yet sent (e.g. the lamp was removed).
    func cancelPending(lampID: String) {
        lanes[lampID]?.buffer.removeAll()
    }

    private func pump(lampID: String, lane: Lane) async {
        while lane.buffer.hasPending {
            // Wait first, take afterwards: values submitted while waiting replace the
            // pending one, so the command that finally goes out is the newest.
            let wait = lane.pacer.earliestSend(now: now(), isFinal: lane.buffer.nextIsFinal).timeIntervalSince(now())
            if wait > 0.001 { await sleep(wait) }
            guard let entry = lane.buffer.takeNext() else { break }

            let transition = entry.isFinal ? Self.finalTransition : max(0.1, lane.pacer.minInterval)
            lane.pacer.recordSend(at: now())
            do {
                let updated = try await perform(lampID, entry.command, transition)
                lane.buffer.finish()
                // Superseded results are stale by definition: skip them.
                if let updated, lane.buffer.pendingCommand(of: entry.command.kind) == nil {
                    onApplied?(lampID, updated)
                }
            } catch {
                lane.buffer.finish()
                // The user's intent for this lamp failed; later queued values would be built
                // on top of unknown state.
                lane.buffer.removeAll()
                onFailure?(lampID, error)
            }
        }
        lane.task = nil
        onIdle?(lampID)
    }
}
