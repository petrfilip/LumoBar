import Foundation

/// Pure room decisions (first-run migration, collapsed rooms) so they can be unit-tested.
enum RoomLayout {
    struct MigrationPlan: Equatable {
        var rooms: [Room]
        /// The rooms have to be written to disk.
        var persist: Bool
        /// The migration flag must be set (the migration ran, or rooms already existed).
        var markMigrated: Bool
    }

    /// First-run migration: every known lamp goes into one default room.
    ///
    /// It runs at most once. "No rooms" used to mean "never migrated", so a user who deleted
    /// all rooms got the default one back at every launch; now a flag (or an existing
    /// `rooms.json`, even an empty one) records that the user's rooms are theirs.
    static func migrationPlan(
        loaded: [Room],
        hasRoomsFile: Bool,
        alreadyMigrated: Bool,
        lampIds: [String],
        defaultRoomName: String
    ) -> MigrationPlan {
        if !loaded.isEmpty {
            return MigrationPlan(rooms: loaded, persist: false, markMigrated: true)
        }
        if alreadyMigrated || hasRoomsFile {
            return MigrationPlan(rooms: [], persist: false, markMigrated: true)
        }
        // Nothing to group yet (the first poll found no lamp): try again at a later launch.
        guard !lampIds.isEmpty else {
            return MigrationPlan(rooms: [], persist: false, markMigrated: false)
        }
        return MigrationPlan(rooms: [Room(name: defaultRoomName, lampIds: lampIds)], persist: true, markMigrated: true)
    }

    /// The default room keeps the name it got in the language of the day it was created
    /// (LampControl's old migration even hard-coded "Unassigned"). While it still has one of
    /// those default names, show it in the current language; a name the user chose is kept.
    static let legacyDefaultRoomName = "Unassigned"

    static func relabeled(_ rooms: [Room], defaultNames: Set<String>, currentName: String) -> [Room] {
        let names = defaultNames.union([legacyDefaultRoomName])
        return rooms.map { room in
            guard names.contains(room.name), room.name != currentName else { return room }
            var relabeled = room
            relabeled.name = currentName
            return relabeled
        }
    }

    /// Ids of lamps whose row is not shown because their room is collapsed.
    static func lampIdsHiddenByCollapse(rooms: [Room], collapsedRoomIds: Set<String>) -> Set<String> {
        var hidden = Set<String>()
        for room in rooms where collapsedRoomIds.contains(room.id) {
            hidden.formUnion(room.lampIds)
        }
        return hidden
    }

    struct RoomSection: Identifiable, Equatable {
        let room: Room
        /// In the order of the `lamps` that were grouped.
        let lamps: [LampDevice]
        var id: String { room.id }
    }

    struct Grouping: Equatable {
        /// Rooms in their own order; rooms without a (visible) lamp are left out.
        var sections: [RoomSection]
        /// Lamps that no room lists, in the order of the `lamps` that were grouped.
        var unassigned: [LampDevice]
    }

    /// Splits `lamps` (already filtered and ordered) over `rooms` in a single pass, instead of
    /// filtering the whole list once per room. A lamp listed by several rooms appears in each of
    /// them; a lamp listed by none is `unassigned`.
    static func group(lamps: [LampDevice], rooms: [Room]) -> Grouping {
        var roomIndexesByLamp: [String: [Int]] = [:]
        for (index, room) in rooms.enumerated() {
            for lampId in Set(room.lampIds) {
                roomIndexesByLamp[lampId, default: []].append(index)
            }
        }
        var lampsByRoom = [[LampDevice]](repeating: [], count: rooms.count)
        var unassigned: [LampDevice] = []
        for lamp in lamps {
            if let indexes = roomIndexesByLamp[lamp.id] {
                for index in indexes { lampsByRoom[index].append(lamp) }
            } else {
                unassigned.append(lamp)
            }
        }
        let sections = rooms.enumerated().compactMap { index, room in
            lampsByRoom[index].isEmpty ? nil : RoomSection(room: room, lamps: lampsByRoom[index])
        }
        return Grouping(sections: sections, unassigned: unassigned)
    }
}
