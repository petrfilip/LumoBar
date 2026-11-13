import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    // MARK: - Live adjustments (sliders, color picker)
    //
    // `preview*` runs on every drag event: it updates the UI immediately and, for providers
    // that declare a `liveUpdatePolicy`, hands the value to the coalescing queue so the lamp
    // follows while the user is still dragging. `commit*` runs once on release with the final
    // value, which always goes out. Providers without a policy only receive the final value.

    func toggle(_ lamp: LampDevice) async -> Bool {
        // A poll already in flight describes the lamp from before this click: hold the lamp
        // (and drop that poll) so the new state is not reverted until the lamp has answered.
        syncGeneration.bump()
        noteUserActivity(lamp.id)
        updateLamp(lamp.withPower(!lamp.power))

        do {
            let updated = try await makeLightProvider(for: lamp).setPower(deviceId: lamp.nativeID, value: !lamp.power)
            noteUserActivity(lamp.id)
            updateLamp(updated)
            return true
        } catch {
            noteUserActivity(lamp.id)
            updateLamp(lamp)
            showError(error)
            return false
        }
    }

    /// The user grabbed a control of `lamp`: from now on state coming from elsewhere is
    /// ignored for it until they are done (see `LampInteractionGuard`).
    func beginAdjusting(_ lamp: LampDevice) {
        interactionGuard.beginDrag(lamp.id, now: Date())
        scheduleHoldExpiry(for: lamp.id)
    }

    func previewBrightness(_ lamp: LampDevice, value: Int) {
        noteUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        updateLamp(lamp.withBrightness(value).withPower(true))
        enqueue(.brightness(value), for: lamp, isFinal: false)
    }

    func commitBrightness(_ lamp: LampDevice, value: Int) async {
        endUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        enqueue(.brightness(value), for: lamp, isFinal: true)
    }

    func previewTemperature(_ lamp: LampDevice, value: Int) {
        noteUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        updateLamp(lamp.withTemperature(value))
        enqueue(.temperature(value), for: lamp, isFinal: false)
    }

    func commitTemperature(_ lamp: LampDevice, value: Int) async {
        endUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        enqueue(.temperature(value), for: lamp, isFinal: true)
    }

    func previewColor(_ lamp: LampDevice, color: HSVColor) {
        noteUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        updateLamp(lamp.previewingColor(color).withPower(true))
        enqueue(.color(color), for: lamp, isFinal: false)
    }

    func commitColor(_ lamp: LampDevice, color: HSVColor) async {
        endUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        enqueue(.color(color), for: lamp, isFinal: true)
    }

    /// Runs before every preview / commit: remembers the real state to fall back to if the
    /// command fails, and flags a lamp that is off so the first command switches it on (bulbs
    /// such as Yeelight reject color / temperature / brightness while off). The state is read
    /// from `lamps`, not from `lamp`: after the first preview the UI already shows it as on.
    private func prepareAdjustment(of lamp: LampDevice) {
        let current = lamps.first { $0.id == lamp.id } ?? lamp
        restorePoints.remember(current)
        if !current.power { lampsNeedingPowerOn.insert(lamp.id) }
    }

    /// A command failed: stop showing the unapplied preview. Bulbs that push their state
    /// (Yeelight) go back to the live one, the others to the state from before the adjustment.
    private func restoreAfterFailure(_ lampID: String) {
        lampsNeedingPowerOn.remove(lampID)
        let restorePoint = restorePoints.take(lampID)
        var live: LampDevice?
        if let lamp = lamps.first(where: { $0.id == lampID }), lamp.providerID == .yeelight,
           let bulb = yeelightSettings.bulbs.first(where: { $0.id == lamp.nativeID }),
           let props = yeelightLiveSync.liveProperties(for: bulb.id) {
            live = YeelightLightProvider.makeLamp(bulb: bulb, properties: props, online: true)
        }
        guard let restored = LampRestorePoints.restoredState(live: live, restorePoint: restorePoint) else { return }
        if live != nil { (lightProviders[.yeelight] as? YeelightLightProvider)?.noteExternalState(restored) }
        updateLamp(restored)
    }

    // MARK: - Stale update protection

    func isHolding(_ lampID: String) -> Bool {
        interactionGuard.isHolding(lampID, now: Date(), commandsPending: !commandQueue.isIdle(lampID))
    }

    func noteUserActivity(_ lampID: String) {
        interactionGuard.touch(lampID, now: Date())
        scheduleHoldExpiry(for: lampID)
    }

    private func endUserActivity(_ lampID: String) {
        interactionGuard.endDrag(lampID, now: Date())
        scheduleHoldExpiry(for: lampID)
    }

    /// Waits for the user's window on `lampID` to close (it keeps getting pushed out by new
    /// activity and by command replies), then reconciles with what the bulb really reports.
    private func scheduleHoldExpiry(for lampID: String) {
        guard holdExpiryTasks[lampID] == nil else { return }
        holdExpiryTasks[lampID] = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let end = self.interactionGuard.holdEnd(lampID) else { break }
                let remaining = end.timeIntervalSinceNow
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000) + 50_000_000)
                    continue
                }
                if !self.commandQueue.isIdle(lampID) {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
                self.interactionGuard.clear(lampID)
                self.reconcileAfterInteraction(lampID)
                break
            }
            self?.holdExpiryTasks[lampID] = nil
        }
    }

    /// Initial cache of a freshly created Yeelight provider. The provider skips commands that
    /// match what its cache says the bulb shows, so the cache must describe the *bulb*, never
    /// the optimistic value on screen: prefer the state the bulb pushed, and leave out lamps the
    /// user is adjusting (their on-screen value has not reached the bulb yet).
    func yeelightProviderSeed() -> [LampDevice] {
        lamps.compactMap { lamp in
            guard lamp.providerID == .yeelight else { return nil }
            if let bulb = yeelightSettings.bulbs.first(where: { $0.id == lamp.nativeID }),
               let live = yeelightLiveSync.liveProperties(for: bulb.id) {
                return YeelightLightProvider.makeLamp(bulb: bulb, properties: live, online: true)
            }
            return isHolding(lamp.id) ? nil : lamp
        }
    }

    private func reconcileAfterInteraction(_ lampID: String) {
        guard let lamp = lamps.first(where: { $0.id == lampID }), lamp.providerID == .yeelight,
              let bulb = yeelightSettings.bulbs.first(where: { $0.id == lamp.nativeID }),
              let live = yeelightLiveSync.liveProperties(for: bulb.id)
        else { return }
        applyYeelightLiveState(bulb: bulb, properties: live, online: true)
    }

    private func enqueue(_ command: LampCommand, for lamp: LampDevice, isFinal: Bool) {
        let policy = (try? makeLightProvider(for: lamp))?.liveUpdatePolicy
        guard isFinal || policy != nil else { return }
        commandQueue.submit(lampID: lamp.id, command: command, isFinal: isFinal, policy: policy)
    }

    func makeCommandQueue() -> LampCommandQueue {
        let queue = LampCommandQueue { [weak self] lampID, command, transition in
            guard let self else { return nil }
            return try await self.perform(command, lampID: lampID, transition: transition)
        }
        queue.onApplied = { [weak self] lampID, lamp in
            guard let self else { return }
            self.interactionGuard.touch(lampID, now: Date())
            self.restorePoints.confirm(lamp)
            self.updateLamp(lamp)
        }
        queue.onIdle = { [weak self] lampID in
            guard let self else { return }
            self.restorePoints.discard(lampID)
            // The grace period counts from the last command's reply.
            self.interactionGuard.touch(lampID, now: Date())
            self.scheduleHoldExpiry(for: lampID)
        }
        queue.onFailure = { [weak self] lampID, error in
            guard let self else { return }
            self.restoreAfterFailure(lampID)
            self.showError(error)
        }
        return queue
    }

    private func perform(_ command: LampCommand, lampID: String, transition: TimeInterval) async throws -> LampDevice? {
        guard var lamp = lamps.first(where: { $0.id == lampID }) else { return nil }
        // The UI already shows the lamp as on; the bulb may still be off.
        let wasOff = lampsNeedingPowerOn.remove(lampID) != nil
        if wasOff { lamp.power = false }
        let provider = try makeLightProvider(for: lamp)
        switch command {
        case .brightness(let value):
            if wasOff { _ = try await provider.setPower(deviceId: lamp.nativeID, value: true) }
            return try await provider.setBrightness(deviceId: lamp.nativeID, value: value, transition: transition)
        case .temperature(let value):
            if wasOff { _ = try await provider.setPower(deviceId: lamp.nativeID, value: true) }
            return try await provider.setTemperature(deviceId: lamp.nativeID, value: value, transition: transition)
        case .color(let color):
            return try await applyColor(color, to: lamp, transition: transition)
        }
    }

    func applyGroupPower(_ value: Bool) async {
        guard lamps.contains(where: { selectedLampIds.contains($0.id) }) else {
            showError(L10n.selectLamp)
            return
        }
        // Offline lamps cannot answer: skip them instead of failing the whole group.
        let targets = lamps.filter { selectedLampIds.contains($0.id) && $0.online }
        guard !targets.isEmpty else {
            showError(L10n.roomNoOnlineLamp)
            return
        }

        await runBusy {
            try await setPower(value, on: targets)
            message = L10n.groupPower(value)
        }
    }

    // MARK: - White handling

    /// Whether `color` can be rendered on `lamp`: RGB lamps take any color,
    /// white-only (tunable) lamps take near-white colors via color temperature.
    func canShow(_ color: HSVColor, on lamp: LampDevice) -> Bool {
        lamp.capabilities.colorCode != nil || (color.isNearWhite && lamp.capabilities.temperature != nil)
    }

    /// Sends `color` to `lamp`. Near-white colors are sent as a neutral color
    /// temperature when the lamp supports it: RGB "white" (saturation 0) looks
    /// dim and bluish on most bulbs, while CT mode uses the dedicated white LEDs.
    private func applyColor(_ color: HSVColor, to lamp: LampDevice, transition: TimeInterval = 0.2) async throws -> LampDevice {
        let provider = try makeLightProvider(for: lamp)
        // Many bulbs (e.g. Yeelight) reject color/CT/brightness commands while
        // off; applying a color implies the lamp should light up.
        if !lamp.power {
            _ = try await provider.setPower(deviceId: lamp.nativeID, value: true)
        }
        guard color.isNearWhite, let temperature = lamp.capabilities.temperature else {
            return try await provider.setColor(deviceId: lamp.nativeID, color: color, transition: transition)
        }

        var updated = try await provider.setTemperature(
            deviceId: lamp.nativeID,
            value: LampDevice.neutralWhite(for: temperature),
            transition: transition
        )
        if let brightness = lamp.capabilities.brightness {
            let value = LampDevice.brightness(forColorValue: color.v, capability: brightness)
            updated = try await provider.setBrightness(deviceId: lamp.nativeID, value: value, transition: transition)
        }
        return updated
    }

    // MARK: - Multi-lamp actions

    /// Switches every lamp of `targets`. A failing lamp does not stop the others; what worked is
    /// shown, then the first error is thrown (see `BulkLampAction`).
    @discardableResult
    func setPower(_ value: Bool, on targets: [LampDevice]) async throws -> Int {
        try await applyToEach(targets) { lamp in
            try await self.makeLightProvider(for: lamp).setPower(deviceId: lamp.nativeID, value: value)
        }
    }

    @discardableResult
    func applyColorToEach(_ color: HSVColor, on targets: [LampDevice]) async throws -> Int {
        try await applyToEach(targets) { lamp in try await self.applyColor(color, to: lamp) }
    }

    private func applyToEach(_ targets: [LampDevice], _ operation: (LampDevice) async throws -> LampDevice) async throws -> Int {
        // Hold every target while the action runs, so a poll answering in between does not
        // put the old state back on a lamp that was already updated.
        for lamp in targets { noteUserActivity(lamp.id) }
        let outcome = await BulkLampAction.run(on: targets, operation: operation, onUpdate: { updated in
            noteUserActivity(updated.id)
            updateLamp(updated)
        })
        if let error = outcome.firstError { throw error }
        if outcome.wasCancelled { throw CancellationError() }
        return outcome.updatedCount
    }

    // MARK: - Power all

    func applyPowerAll(_ value: Bool) async {
        let targets = lamps.filter { $0.online }
        guard !targets.isEmpty else { return }
        await runBusy {
            try await setPower(value, on: targets)
            message = L10n.allLampsPower(value)
        }
    }
}
