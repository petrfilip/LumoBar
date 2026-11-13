import Foundation

/// Represents an available macOS Focus mode
struct FocusMode: Identifiable, Hashable {
    var identifier: String
    var displayName: String
    var id: String { identifier }
}

/// Maps a macOS Focus mode to a lamp scene
struct FocusMapping: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var focusIdentifier: String  // e.g., "work", "sleep", "custom-name"
    var focusDisplayName: String // e.g., "Travail", "Sommeil"
    var sceneId: UUID?           // UserLightScene ID or preset scene ID
    var isEnabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, focusIdentifier, focusDisplayName, sceneId, isEnabled
    }

    init(id: String = UUID().uuidString, focusIdentifier: String, focusDisplayName: String, sceneId: UUID? = nil, isEnabled: Bool = true) {
        self.id = id
        self.focusIdentifier = focusIdentifier
        self.focusDisplayName = focusDisplayName
        self.sceneId = sceneId
        self.isEnabled = isEnabled
    }
}

extension FocusMapping {
    /// Explicit so an older file without `id` / `isEnabled` still decodes (synthesized `Decodable`
    /// ignores the property defaults).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            focusIdentifier: try c.decode(String.self, forKey: .focusIdentifier),
            focusDisplayName: try c.decodeIfPresent(String.self, forKey: .focusDisplayName) ?? "",
            sceneId: try c.decodeIfPresent(UUID.self, forKey: .sceneId),
            isEnabled: try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true)
    }

    /// True when `identifier` names this mapping's Focus. Identifiers are matched
    /// case-insensitively (and ignoring surrounding whitespace) because the
    /// `lampcontrol://focus?mode=` URL is resolved that way.
    func matches(focusIdentifier identifier: String) -> Bool {
        Self.normalized(focusIdentifier) == Self.normalized(identifier)
    }

    /// First enabled mapping for `identifier`, if any.
    static func enabledMapping(for identifier: String, in mappings: [FocusMapping]) -> FocusMapping? {
        mappings.first { $0.isEnabled && $0.matches(focusIdentifier: identifier) }
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
