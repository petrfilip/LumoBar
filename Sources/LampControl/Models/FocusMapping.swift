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

    init(id: String = UUID().uuidString, focusIdentifier: String, focusDisplayName: String, sceneId: UUID? = nil, isEnabled: Bool = true) {
        self.id = id
        self.focusIdentifier = focusIdentifier
        self.focusDisplayName = focusDisplayName
        self.sceneId = sceneId
        self.isEnabled = isEnabled
    }
}

extension FocusMapping {
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
