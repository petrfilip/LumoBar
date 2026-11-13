import Foundation

struct LightScenePreset: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let color: HSVColor

    static let presets: [LightScenePreset] = [
        LightScenePreset(id: "white", title: NSLocalizedString("scene.white", comment: ""), icon: "lightbulb.fill",  color: HSVColor.white),
        LightScenePreset(id: "focus", title: NSLocalizedString("scene.focus", comment: ""), icon: "sun.max.fill",    color: HSVColor(h: 42,  s: 360, v: 1000)),
        LightScenePreset(id: "relax", title: NSLocalizedString("scene.relax", comment: ""), icon: "moon.fill",       color: HSVColor(h: 24,  s: 760, v: 780)),
        LightScenePreset(id: "neon",  title: NSLocalizedString("scene.neon",  comment: ""), icon: "sparkles",        color: HSVColor(h: 278, s: 860, v: 1000)),
        LightScenePreset(id: "night", title: NSLocalizedString("scene.night", comment: ""), icon: "bed.double.fill", color: HSVColor(h: 220, s: 720, v: 320)),
    ]

    static func preset(id: String) -> LightScenePreset? {
        presets.first { $0.id == id }
    }

    /// A regular, editable scene carrying this preset's definition. The
    /// `presetId` is what lets automations keep resolving it.
    func makeScene(sceneId: UUID = UUID()) -> UserLightScene {
        UserLightScene(id: sceneId, title: title, icon: icon, color: color, presetId: id)
    }
}

/// Pure list transformations for the built-in presets that live in the user's
/// scene list (kept free of I/O so they can be unit-tested).
enum PresetScenes {
    /// UserDefaults flag set once the built-ins have been seeded into the scene list.
    static let seededDefaultsKey = "LampControl.scenes.presetsSeeded.v1"

    /// First launch with editable presets: put every built-in in front of the
    /// user's own scenes. Built-ins already present (by `presetId`) are kept.
    static func seeded(_ existing: [UserLightScene], presets: [LightScenePreset] = LightScenePreset.presets) -> [UserLightScene] {
        let present = Set(existing.compactMap(\.presetId))
        let missing = presets.filter { !present.contains($0.id) }.map { $0.makeScene() }
        return missing + existing
    }

    /// "Restore default scenes": every built-in is back at its definition (a
    /// modified one is reset in place, keeping its UUID so references stay
    /// valid; a deleted one is re-added). Built-ins come first, in default
    /// order; the user's own scenes keep their order after them.
    static func restored(_ existing: [UserLightScene], presets: [LightScenePreset] = LightScenePreset.presets) -> [UserLightScene] {
        var head: [UserLightScene] = []
        for preset in presets {
            if var scene = existing.first(where: { $0.presetId == preset.id }) {
                scene.title = preset.title
                scene.icon = preset.icon
                scene.color = preset.color
                scene.snapshots = nil
                head.append(scene)
            } else {
                head.append(preset.makeScene())
            }
        }
        let known = Set(presets.map(\.id))
        let rest = existing.filter { scene in
            guard let pid = scene.presetId else { return true }
            return !known.contains(pid)
        }
        return head + rest
    }

    /// The scene a built-in id ("focus"...) resolves to: the user's (possibly
    /// edited) scene if it still exists, otherwise nil so the caller falls
    /// back to the hard-coded preset.
    static func scene(forPresetId id: String, in scenes: [UserLightScene]) -> UserLightScene? {
        scenes.first { $0.presetId == id }
    }
}

/// Snapshot of a single lamp's state, used by capture-type scenes.
struct LampSnapshot: Codable, Equatable, Hashable {
    var lampId: String
    var nativeID: String
    var providerID: LightProviderKind
    var name: String
    var power: Bool
    var brightness: Int?
    var temperature: Int?
    var color: HSVColor?
    /// "white" when captured in color-temperature mode. Optional so scenes
    /// saved by older versions still decode.
    var workMode: String?
}

struct UserLightScene: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var icon: String
    var color: HSVColor
    var snapshots: [LampSnapshot]?
    var createdAt: Date
    /// Id of the built-in preset this scene was seeded from ("white", "focus"...).
    /// Optional so scenes saved by older versions still decode.
    var presetId: String?

    var isCapture: Bool { snapshots != nil }

    enum CodingKeys: String, CodingKey {
        case id, title, icon, color, snapshots, createdAt, presetId
    }

    /// Explicit so one snapshot of a lamp whose provider this version does not know is skipped
    /// instead of making the whole scene (and with it the scene file) unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        icon = try c.decode(String.self, forKey: .icon)
        color = try c.decode(HSVColor.self, forKey: .color)
        if try !c.contains(.snapshots) || c.decodeNil(forKey: .snapshots) {
            snapshots = nil
        } else {
            snapshots = try c.decodeLossyArray(LampSnapshot.self, forKey: .snapshots)
        }
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        presetId = try c.decodeIfPresent(String.self, forKey: .presetId)
    }

    init(
        id: UUID = UUID(),
        title: String,
        icon: String,
        color: HSVColor,
        snapshots: [LampSnapshot]? = nil,
        createdAt: Date = Date(),
        presetId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.color = color
        self.snapshots = snapshots
        self.createdAt = createdAt
        self.presetId = presetId
    }
}
