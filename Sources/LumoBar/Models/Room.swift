import Foundation

struct Room: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var lampIds: [String]

    init(id: String = UUID().uuidString, name: String, lampIds: [String] = []) {
        self.id = id
        self.name = name
        self.lampIds = lampIds
    }
}
