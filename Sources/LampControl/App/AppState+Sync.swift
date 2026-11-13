import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    func syncLamps(silent: Bool = false) async {
        guard canSync else { return }

        if silent {
            guard !isBusy && !isAutoSyncing else { return }
            // Don't poll bulbs while the user is adjusting one: the reply would be stale on arrival.
            guard !interactionGuard.isAnyHolding(now: Date()), commandQueue.isAllIdle else { return }
            isAutoSyncing = true
            defer { isAutoSyncing = false }

            let generation = syncGeneration.value
            let merged = await syncConfiguredProviders()
            // The user acted (or settings changed) while the providers were answering: this
            // result describes the state from before, and would revert their change in the UI
            // or bring back a device they just removed. The next poll starts fresh.
            guard syncGeneration.isCurrent(generation) else { return }
            applySync(merged)
            reportSyncFailures(merged, silent: true)
            if merged.didSync {
                scheduleYeelightRecovery()
            }

            return
        }

        await runBusy {
            let merged = await syncConfiguredProviders()
            let synced = applySync(merged)
            finishManualSync(merged, message: synced.isEmpty ? L10n.lampsNoneFound : L10n.lampsSynced(synced.count))
            scheduleYeelightRecovery()
        }
    }

    /// Syncs every configured provider independently and concurrently. A provider that fails
    /// keeps its previous lamps (marked offline) and is reported in `failures`; it never drops
    /// the other providers' lamps. Never throws.
    func syncConfiguredProviders(dropPrevious: Set<LightProviderKind> = []) async -> ProviderSyncMerge {
        var results: [ProviderSyncResult] = []
        var runnable: [(kind: LightProviderKind, provider: any LightProvider)] = []
        for kind in configuredProviderKinds {
            do {
                runnable.append((kind, try makeLightProvider(for: kind)))
            } catch {
                results.append(ProviderSyncResult(kind: kind, outcome: .failure(error)))
            }
        }
        await withTaskGroup(of: ProviderSyncResult.self) { group in
            for (kind, provider) in runnable {
                group.addTask {
                    do {
                        return ProviderSyncResult(kind: kind, outcome: .success(try await provider.syncLights()))
                    } catch {
                        return ProviderSyncResult(kind: kind, outcome: .failure(error))
                    }
                }
            }
            for await result in group { results.append(result) }
        }
        return ProviderSyncMerge.merge(previous: lamps, results: results, dropPrevious: dropPrevious)
    }

    /// Publishes a finished sync: the lamp list, the selections that still apply and the sync time.
    /// Every property is assigned only when its value changed: each assignment makes SwiftUI
    /// re-render the popover, and a background poll usually finds nothing new.
    @discardableResult
    func applySync(_ merged: ProviderSyncMerge) -> [LampDevice] {
        setSyncedLamps(merged.lamps)
        let ids = Set(merged.lamps.map(\.id))
        let selected = selectedLampIds.intersection(ids)
        if selected != selectedLampIds { selectedLampIds = selected }
        let expanded = expandedLampIds.intersection(ids)
        if expanded != expandedLampIds { expandedLampIds = expanded }
        if merged.didSync {
            let now = Date()
            // The status line shows the time to the minute: a newer second changes nothing visible.
            let isNewMinute = lastSyncDate.map { !Calendar.current.isDate($0, equalTo: now, toGranularity: .minute) } ?? true
            if isNewMinute { lastSyncDate = now }
            noteSyncSucceeded()
        }
        return merged.lamps
    }

    private func noteSyncSucceeded() {
        hasSyncedOnce = true
        if circadianApplyPending {
            circadianApplyPending = false
            scheduleCircadianApply()
        }
    }

    /// Ends a manual sync: shows `text`, then any provider failures (which replace it, so the
    /// working providers still appear in the list but the problem is not hidden). `kind` is the
    /// provider the user just set up; the view only moves on to the lamp list when it answered.
    func finishManualSync(_ merged: ProviderSyncMerge, message text: String, ownedBy kind: LightProviderKind? = nil) {
        message = text
        reportSyncFailures(merged, silent: false)
        if let kind, !merged.failedKinds.contains(kind) { selectedTab = .lamps }
    }

    /// Shows what went wrong during a sync without hiding the providers that worked. A silent
    /// background poll announces each failing provider once until it recovers.
    private func reportSyncFailures(_ merged: ProviderSyncMerge, silent: Bool) {
        var failures = merged.failures
        if silent {
            // A background poll must not talk over an error the user has not seen yet (a data
            // recovery notice, a failed save). Nothing is marked as reported, so a provider that
            // is still failing is announced by a later poll, once the banner has moved on.
            if messageIsError && !message.isEmpty { return }
            let fresh = syncFailureTracker.newlyFailed(merged.failedKinds)
            failures = failures.filter { fresh.contains($0.kind) }
        } else {
            _ = syncFailureTracker.newlyFailed(merged.failedKinds)
        }
        guard !failures.isEmpty else { return }
        showError(failures
            .map { L10n.providerSyncFailed($0.kind.title, detail: $0.error.localizedDescription) }
            .joined(separator: "\n"))
    }

    /// Stores a freshly polled lamp list, layering the (newer) live Yeelight state on top and
    /// avoiding a SwiftUI publish when nothing changed.
    private func setSyncedLamps(_ synced: [LampDevice]) {
        let merged = synced.map { lamp -> LampDevice in
            guard lamp.providerID == .yeelight,
                  let bulb = yeelightSettings.bulbs.first(where: { $0.id == lamp.nativeID }),
                  let live = yeelightLiveSync.liveProperties(for: bulb.id)
            else { return lamp }
            return YeelightLightProvider.makeLamp(bulb: bulb, properties: live, online: true)
        }
        // A poll that was already running when the user started adjusting a lamp returns the
        // state from before their value: keep what is on screen for lamps being adjusted.
        let now = Date()
        let guarded = merged.map { lamp -> LampDevice in
            LampInteractionGuard.resolve(
                incoming: lamp,
                current: lamps.first { $0.id == lamp.id },
                holding: interactionGuard.isHolding(lamp.id, now: now, commandsPending: !commandQueue.isIdle(lamp.id)))
        }
        if lamps != guarded { lamps = guarded }
    }

    func updateLamp(_ next: LampDevice) {
        guard let index = lamps.firstIndex(where: { $0.id == next.id }) else { return }
        let previous = lamps[index]
        // Publishing an identical lamp still re-rendered the whole popover (every command
        // result and push echo repeats the optimistic value): skip no-ops.
        guard previous != next else { return }
        lamps[index] = next
    }

    func startAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.syncLamps(silent: true)
            }
        }
    }

    /// Runs a user operation with the busy state on. Re-entrant: `isBusy` stays on until the last
    /// of the overlapping operations is done. `adaptiveNotice` belongs to this operation only
    /// (its scene switched adaptive lighting off), so another operation never shows or clears it.
    func runBusy(adaptiveNotice: Bool = false, _ operation: () async throws -> Void) async {
        // The previous message is kept until the operation sets a new one:
        // clearing it first made the banner vanish and reappear on every click
        // (visible flicker).
        busy.begin()
        if !isBusy { isBusy = true }
        // Whatever poll is in flight describes the state from before this operation.
        syncGeneration.bump()
        defer {
            busy.end()
            if isBusy != busy.isBusy { isBusy = busy.isBusy }
        }

        do {
            try await operation()
            let notice = L10n.adaptivePausedByScene
            if adaptiveNotice, !messageIsError, !message.contains(notice) {
                message = message.isEmpty ? notice : "\(message) \(notice)"
            }
        } catch is CancellationError {
            // Superseded (a newer Focus change): not a failure to report.
        } catch {
            showError(error)
        }
    }
}
