import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    func loadRoomsAndMigrateIfNeeded() async {
        let defaults = UserDefaults.standard
        let loadedRooms: [Room]
        do {
            loadedRooms = try roomStore.loadRooms()
        } catch {
            // Neither read nor moved aside: keep the file as it is and do not run the migration,
            // which would write a fresh rooms.json over it.
            showError(L10n.dataReadFailed("rooms.json"), sticky: true)
            return
        }
        let plan = RoomLayout.migrationPlan(
            loaded: loadedRooms,
            hasRoomsFile: roomStore.hasRoomsFile,
            alreadyMigrated: defaults.bool(forKey: roomsMigratedKey),
            lampIds: lamps.map(\.id),
            defaultRoomName: L10n.defaultRoomName)
        rooms = RoomLayout.relabeled(
            plan.rooms,
            defaultNames: L10n.allTranslations(of: "rooms.default.name"),
            currentName: L10n.defaultRoomName)
        if plan.persist {
            do {
                try roomStore.saveRooms(rooms)
            } catch {
                showError(L10n.roomsSaveFailed)
                return
            }
        }
        if plan.markMigrated && !isResettingApp { defaults.set(true, forKey: roomsMigratedKey) }
    }

    func persistRooms() {
        guard !isResettingApp else { return }
        do {
            try roomStore.saveRooms(rooms)
        } catch {
            showError(L10n.roomsSaveFailed)
        }
    }

    func lamps(in roomId: String) -> [LampDevice] {
        guard let room = rooms.first(where: { $0.id == roomId }) else { return [] }
        return lamps.filter { room.lampIds.contains($0.id) }
    }

    func roomForLamp(_ lampId: String) -> Room? {
        rooms.first { $0.lampIds.contains(lampId) }
    }

    func addRoom(name: String) {
        rooms.append(Room(name: name))
        persistRooms()
    }

    func renameRoom(_ roomId: String, to name: String) {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
        rooms[index].name = name
        persistRooms()
    }

    func deleteRoom(_ roomId: String) {
        rooms.removeAll { $0.id == roomId }
        persistRooms()
    }

    func assignLamp(_ lampId: String, to roomId: String) {
        // Remove from other rooms
        for i in rooms.indices {
            rooms[i].lampIds.removeAll { $0 == lampId }
        }

        if let idx = rooms.firstIndex(where: { $0.id == roomId }) {
            if !rooms[idx].lampIds.contains(lampId) {
                rooms[idx].lampIds.append(lampId)
            }
        }

        persistRooms()
    }

    func unassignLamp(_ lampId: String) {
        for i in rooms.indices {
            rooms[i].lampIds.removeAll { $0 == lampId }
        }
        persistRooms()
    }

    func setPowerForRoom(_ roomId: String, value: Bool) async {
        guard let room = rooms.first(where: { $0.id == roomId }) else { return }
        let targets = lamps.filter { room.lampIds.contains($0.id) && $0.online }
        guard !targets.isEmpty else { showError(L10n.roomNoOnlineLamp); return }

        await runBusy {
            try await setPower(value, on: targets)
            message = L10n.roomPower(value)
        }
    }

    func applyScene(_ scene: UserLightScene, toRoomId roomId: String, byUser: Bool = false) async {
        guard let room = rooms.first(where: { $0.id == roomId }) else { return }
        // A captured scene restores each lamp's own look (white-only lamps included); a plain
        // color scene needs color-capable lamps.
        let targets = lamps.filter {
            room.lampIds.contains($0.id) && $0.online && (scene.isCapture || $0.capabilities.colorCode != nil)
        }
        guard !targets.isEmpty else { showError(scene.isCapture ? L10n.roomNoOnlineLamp : L10n.roomNoOnlineRGB); return }
        let paused = await pauseAdaptiveForScene(byUser: byUser)

        await runBusy(adaptiveNotice: paused) {
            if let snapshots = scene.snapshots {
                let outcome = await restoreSnapshots(snapshots, on: targets)
                for lamp in outcome.updated { updateLamp(lamp) }
                if let error = outcome.firstError { throw error }
                try Task.checkCancellation()
            } else {
                try await applyColorToEach(scene.color, on: targets)
            }
            message = L10n.roomSceneApplied(scene.title)
        }
    }

    /// Brings each of `candidates` to its captured snapshot (see `LampSnapshot.steps`). A lamp
    /// that fails does not stop the others, and what changed before a failure is kept so the UI
    /// shows the real state; only the first error is returned, to be reported once.
    func restoreSnapshots(_ snapshots: [LampSnapshot], on candidates: [LampDevice])
        async -> (updated: [LampDevice], firstError: Error?) {
        var updated: [LampDevice] = []
        var firstError: Error?
        for snap in snapshots {
            guard !Task.isCancelled else { break }
            guard let lamp = candidates.first(where: { $0.id == snap.lampId && $0.online }) else { continue }
            noteUserActivity(lamp.id)
            var latest: LampDevice?
            do {
                let provider = try makeLightProvider(for: lamp)
                for step in snap.steps(for: lamp) {
                    switch step {
                    case .power(let on): latest = try await provider.setPower(deviceId: lamp.nativeID, value: on)
                    case .temperature(let v): latest = try await provider.setTemperature(deviceId: lamp.nativeID, value: v)
                    case .brightness(let v): latest = try await provider.setBrightness(deviceId: lamp.nativeID, value: v)
                    case .color(let c): latest = try await provider.setColor(deviceId: lamp.nativeID, color: c)
                    }
                }
            } catch {
                // A superseded run (cancelled Focus change) stops quietly.
                if Task.isCancelled || error is CancellationError { break }
                if firstError == nil { firstError = error }
            }
            if let latest {
                noteUserActivity(lamp.id)
                updated.append(latest)
            }
        }
        return (updated, firstError)
    }
}
