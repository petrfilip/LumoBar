import Foundation

/// Applies one operation to several lamps (group / room / "all" actions). A lamp that fails
/// does not stop the others, and every lamp that succeeded is reported immediately so the UI
/// shows the real state; only the first error is kept, to be shown once.
enum BulkLampAction {
    struct Outcome {
        var updatedCount = 0
        var firstError: Error?
        /// The surrounding task was cancelled: the rest of the lamps was left alone and the
        /// cancellation is not reported as an error.
        var wasCancelled = false
    }

    static func run(
        on lamps: [LampDevice],
        operation: (LampDevice) async throws -> LampDevice,
        onUpdate: (LampDevice) -> Void
    ) async -> Outcome {
        var outcome = Outcome()
        for lamp in lamps {
            guard !Task.isCancelled else {
                outcome.wasCancelled = true
                break
            }
            do {
                onUpdate(try await operation(lamp))
                outcome.updatedCount += 1
            } catch {
                if Task.isCancelled || error is CancellationError {
                    outcome.wasCancelled = true
                    break
                }
                if outcome.firstError == nil { outcome.firstError = error }
            }
        }
        return outcome
    }
}
