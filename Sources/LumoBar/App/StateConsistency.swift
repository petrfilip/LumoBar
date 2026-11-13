import Foundation

// Small value types and helpers behind AppState's concurrency handling. They hold no UI and no
// I/O so they can be unit-tested.

/// Counts overlapping busy operations: the first one to finish must not clear the busy state
/// while others are still running.
struct BusyCounter {
    private(set) var count = 0

    var isBusy: Bool { count > 0 }

    mutating func begin() { count += 1 }

    mutating func end() { count = max(0, count - 1) }
}

/// A token that changes whenever the state a background poll was started against becomes
/// outdated (a user action, a settings save). A poll remembers the value when it starts and
/// drops its result when the value moved on in the meantime.
struct SyncGeneration {
    private(set) var value = 0

    mutating func bump() { value += 1 }

    func isCurrent(_ token: Int) -> Bool { token == value }
}

/// Why background polling is paused. Each reason is cleared only by its own "back" event.
enum PollingPauseReason: Hashable, CaseIterable {
    case systemSleep
    case displaySleep
    case sessionInactive
    case screenLocked
}

/// Decides whether the background poll may run. It tracks the set of active pause reasons, so
/// polling resumes only when all of them have cleared (a wake while the screen is still locked
/// keeps it paused). `pause` / `resume` report whether the gate changed between running and
/// paused, so a burst of wake notifications resumes only once.
struct PollingGate {
    private(set) var reasons: Set<PollingPauseReason> = []

    var isPaused: Bool { !reasons.isEmpty }

    /// Returns true when this call moved the gate from running to paused.
    @discardableResult
    mutating func pause(_ reason: PollingPauseReason) -> Bool {
        let wasPaused = isPaused
        reasons.insert(reason)
        return !wasPaused
    }

    /// Returns true when this call moved the gate from paused to running.
    @discardableResult
    mutating func resume(_ reason: PollingPauseReason) -> Bool {
        let wasPaused = isPaused
        reasons.remove(reason)
        return wasPaused && !isPaused
    }
}

/// Owns at most one task. Replacing it cancels the previous one, so a task is never orphaned
/// and can be cancelled on reset.
@MainActor
final class TaskSlot {
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    /// Cancels the running task and starts `operation`. The new task first waits for the
    /// cancelled one to wind down, so two runs never overlap (they are serialized).
    func replace(_ operation: @escaping @MainActor () async -> Void) {
        let previous = task
        previous?.cancel()
        let token = UUID()
        currentToken = token
        task = Task { @MainActor [weak self] in
            await previous?.value
            if !Task.isCancelled { await operation() }
            if self?.currentToken == token { self?.task = nil }
        }
    }

    /// Starts `operation` unless the previous one is still running. For work that must be
    /// allowed to finish (rate-limited discovery) instead of being aborted by the next trigger.
    func startIfIdle(_ operation: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        let token = UUID()
        currentToken = token
        task = Task { @MainActor [weak self] in
            await operation()
            if self?.currentToken == token { self?.task = nil }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        currentToken = nil
    }

    private var currentToken: UUID?
}

/// One owned task per key (e.g. per automation): a new run for a key replaces the previous one,
/// runs for different keys are independent.
@MainActor
final class KeyedTasks<Key: Hashable> {
    private var slots: [Key: TaskSlot] = [:]

    func replace(_ key: Key, _ operation: @escaping @MainActor () async -> Void) {
        let slot = slots[key] ?? TaskSlot()
        slots[key] = slot
        slot.replace(operation)
    }

    func cancelAll() {
        for slot in slots.values { slot.cancel() }
        slots.removeAll()
    }
}

/// Which form an editable list section currently shows. One value per section replaces the
/// separate "is creating" / "editing id" flags, which could both be set at once.
enum SectionEditor<ID: Hashable>: Equatable {
    case none
    case create
    case edit(ID)

    var isOpen: Bool { self != .none }

    var editingID: ID? {
        if case .edit(let id) = self { return id }
        return nil
    }

    /// Closes the editor when the item being edited no longer exists.
    func resolved(existingIDs: [ID]) -> SectionEditor<ID> {
        if case .edit(let id) = self, !existingIDs.contains(id) { return .none }
        return self
    }
}

/// What deleting a scene does to the things that point at it.
struct SceneDeletionCleanup {
    var automations: [Automation]
    var focusMappings: [FocusMapping]
    /// Automations and Focus mappings that were switched off because their scene is gone.
    var disabledCount: Int

    static func apply(deleting sceneID: UUID, automations: [Automation], focusMappings: [FocusMapping]) -> SceneDeletionCleanup {
        var disabled = 0
        let nextAutomations = automations.map { automation -> Automation in
            guard automation.isEnabled, automation.action == .applyProfile(id: sceneID) else { return automation }
            var copy = automation
            copy.isEnabled = false
            disabled += 1
            return copy
        }
        let nextMappings = focusMappings.map { mapping -> FocusMapping in
            guard mapping.sceneId == sceneID else { return mapping }
            var copy = mapping
            if copy.isEnabled { disabled += 1 }
            copy.isEnabled = false
            copy.sceneId = nil
            return copy
        }
        return SceneDeletionCleanup(automations: nextAutomations, focusMappings: nextMappings, disabledCount: disabled)
    }

    /// How many enabled automations / Focus mappings would be switched off by deleting the scene.
    static func referenceCount(for sceneID: UUID, automations: [Automation], focusMappings: [FocusMapping]) -> Int {
        apply(deleting: sceneID, automations: automations, focusMappings: focusMappings).disabledCount
    }
}

extension FocusMapping {
    /// Adds `mapping`, or, when a mapping for the same Focus already exists (identifiers match
    /// case-insensitively, like the URL scheme resolves them), points that one at the new scene
    /// and enables it instead of creating a second entry that could never win.
    static func adding(_ mapping: FocusMapping, to mappings: [FocusMapping]) -> [FocusMapping] {
        var result = mappings
        if let index = result.firstIndex(where: { $0.id == mapping.id || $0.matches(focusIdentifier: mapping.focusIdentifier) }) {
            result[index].sceneId = mapping.sceneId
            result[index].isEnabled = true
        } else {
            result.append(mapping)
        }
        return result
    }

    /// Replaces the mapping with `mapping.id`. A different mapping for the same Focus is
    /// dropped (the edited one takes over), so editing cannot create a duplicate either.
    static func updating(_ mapping: FocusMapping, in mappings: [FocusMapping]) -> [FocusMapping] {
        guard let index = mappings.firstIndex(where: { $0.id == mapping.id }) else { return mappings }
        var result = mappings
        result[index] = mapping
        return result.filter { $0.id == mapping.id || !$0.matches(focusIdentifier: mapping.focusIdentifier) }
    }
}

/// Rules for reordering lamps by drag and drop.
enum LampDragRules {
    /// A drop reorders only while one of our own lamp rows is being dragged: text dragged in from
    /// another app (or left over from a drag that was cancelled) must never move a lamp.
    static func acceptsDrop(dragged: String?, onto target: String, canReorder: Bool) -> Bool {
        isLampDrag(dragged: dragged, canReorder: canReorder) && dragged != target
    }

    /// Whether the drag in progress is one of our lamp rows and the list may be reordered.
    static func isLampDrag(dragged: String?, canReorder: Bool) -> Bool {
        canReorder && dragged != nil
    }

    /// SwiftUI reports neither a cancelled drag nor a drop outside every row. The left mouse
    /// button being up is the reliable sign that the drag session is over.
    static func isDragFinished(pressedMouseButtons: Int) -> Bool {
        pressedMouseButtons & 1 == 0
    }
}

/// How long the status banner stays up.
enum BannerPolicy {
    static let informationalLifetime: TimeInterval = 6
    static let errorLifetime: TimeInterval = 15

    /// `nil` means "until the user dismisses it". Sticky errors are the ones that must not be
    /// missed (a data file that was set aside), so they never expire.
    static func lifetime(isError: Bool, isSticky: Bool) -> TimeInterval? {
        if isError { return isSticky ? nil : errorLifetime }
        return informationalLifetime
    }
}
