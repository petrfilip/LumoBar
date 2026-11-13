import Foundation

/// Applies one operation to several lamps (group / room / "all" actions). A lamp that fails
/// does not stop the others, and every lamp that succeeded is reported immediately so the UI
/// shows the real state; only the first error is kept, to be shown once.
enum BulkLampAction {
    struct Outcome {
        var updatedCount = 0
        var firstError: Error?
    }

    static func run(
        on lamps: [LampDevice],
        operation: (LampDevice) async throws -> LampDevice,
        onUpdate: (LampDevice) -> Void
    ) async -> Outcome {
        var outcome = Outcome()
        for lamp in lamps {
            do {
                onUpdate(try await operation(lamp))
                outcome.updatedCount += 1
            } catch {
                if outcome.firstError == nil { outcome.firstError = error }
            }
        }
        return outcome
    }
}
