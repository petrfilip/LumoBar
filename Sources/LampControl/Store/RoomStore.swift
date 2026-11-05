import Foundation

final class RoomStore {
    private let fileName = "rooms.json"

    func saveRooms(_ rooms: [Room]) throws {
        let data = try JSONEncoder().encode(rooms)
        try data.write(to: roomsURL, options: .atomic)
    }

    /// Whether rooms were ever saved (even as an empty list).
    var hasRoomsFile: Bool {
        FileManager.default.fileExists(atPath: roomsURL.path)
    }

    func loadRooms() -> [Room] {
        guard FileManager.default.fileExists(atPath: roomsURL.path) else { return [] }
        guard let data = try? Data(contentsOf: roomsURL) else { return [] }
        if let decoded = try? JSONDecoder().decode([Room].self, from: data) {
            return decoded
        }
        return []
    }

    private var roomsURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LampControl", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent(fileName)
    }
}
