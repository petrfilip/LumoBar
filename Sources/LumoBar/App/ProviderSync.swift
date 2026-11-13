import Foundation

/// What one provider returned from a sync attempt.
struct ProviderSyncResult {
    let kind: LightProviderKind
    let outcome: Result<[LampDevice], Error>
}

/// The combined result of syncing every configured provider independently: a provider that
/// failed no longer takes the others' lamps down with it.
struct ProviderSyncMerge {
    struct Failure {
        let kind: LightProviderKind
        let error: Error
    }

    /// Lamps of the providers that answered, plus the previously known lamps of the providers
    /// that failed (marked offline), sorted by name.
    var lamps: [LampDevice]
    var failures: [Failure]
    /// True when at least one provider answered, or when there was nothing to ask.
    var didSync: Bool

    var failedKinds: Set<LightProviderKind> { Set(failures.map(\.kind)) }

    /// - Parameters:
    ///   - previous: the lamps currently shown.
    ///   - dropPrevious: providers whose settings just changed: their old lamps may no longer
    ///     exist (a removed device), so a failure does not keep them around.
    static func merge(previous: [LampDevice], results: [ProviderSyncResult],
                      dropPrevious: Set<LightProviderKind> = []) -> ProviderSyncMerge {
        var lamps: [LampDevice] = []
        var failures: [Failure] = []
        var succeeded = 0
        for result in results {
            switch result.outcome {
            case .success(let synced):
                succeeded += 1
                lamps.append(contentsOf: synced)
            case .failure(let error):
                failures.append(Failure(kind: result.kind, error: error))
                guard !dropPrevious.contains(result.kind) else { continue }
                lamps.append(contentsOf: previous.filter { $0.providerID == result.kind }.map { lamp in
                    var offline = lamp
                    offline.online = false
                    return offline
                })
            }
        }
        lamps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return ProviderSyncMerge(lamps: lamps, failures: failures, didSync: failures.isEmpty || succeeded > 0)
    }
}

/// Remembers which providers' failures were already shown, so a background poll that keeps
/// failing does not re-announce the same problem every minute.
struct SyncFailureTracker {
    private var reported = Set<LightProviderKind>()

    /// Returns the providers that failed now and were not announced yet; forgets the ones that
    /// recovered so a later failure is announced again.
    mutating func newlyFailed(_ failed: Set<LightProviderKind>) -> Set<LightProviderKind> {
        let fresh = failed.subtracting(reported)
        reported = failed
        return fresh
    }

    mutating func reset() { reported = [] }
}
