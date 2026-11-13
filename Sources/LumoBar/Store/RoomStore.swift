import Foundation

/// `rooms.json`.
final class RoomStore {
    private let file: JSONListStore<Room>

    init(directory: URL = AppDirectories.support, recovery: RecoveryLog = .shared) {
        file = JSONListStore(directory: directory, fileName: "rooms.json", recovery: recovery)
    }

    func saveRooms(_ rooms: [Room]) throws { try file.save(rooms) }

    /// Whether rooms were ever saved (even as an empty list). An unreadable file is moved aside
    /// by `loadRooms`, so call that first.
    var hasRoomsFile: Bool { file.exists }

    func loadRooms() throws -> [Room] { try file.load() }
}
