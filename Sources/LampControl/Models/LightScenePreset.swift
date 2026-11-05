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

    var isCapture: Bool { snapshots != nil }

    init(
        id: UUID = UUID(),
        title: String,
        icon: String,
        color: HSVColor,
        snapshots: [LampSnapshot]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.color = color
        self.snapshots = snapshots
        self.createdAt = createdAt
    }
}
