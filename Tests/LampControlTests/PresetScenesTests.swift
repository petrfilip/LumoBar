import XCTest
@testable import LampControl

/// Pure-logic tests for the built-in presets that live in the user's scene
/// list (seeding migration, restore defaults, id resolution). No disk access.
final class PresetScenesTests: XCTestCase {
    private let ids = ["white", "focus", "relax", "neon", "night"]

    private func userScene(_ title: String) -> UserLightScene {
        UserLightScene(title: title, icon: "flame.fill", color: HSVColor(h: 10, s: 500, v: 500))
    }

    func testSeedingPutsAllBuiltinsFirstInDefaultOrder() {
        let mine = [userScene("Mine A"), userScene("Mine B")]
        let seeded = PresetScenes.seeded(mine)
        XCTAssertEqual(seeded.prefix(5).compactMap(\.presetId), ids)
        XCTAssertEqual(seeded.suffix(2).map(\.title), ["Mine A", "Mine B"])
        XCTAssertEqual(seeded.count, 7)
    }

    func testSeedingKeepsExistingPresetAndOnlyAddsMissing() {
        var focus = LightScenePreset.preset(id: "focus")!.makeScene()
        focus.title = "My focus"
        let seeded = PresetScenes.seeded([focus])
        XCTAssertEqual(seeded.count, 5)
        XCTAssertEqual(seeded.first(where: { $0.presetId == "focus" })?.title, "My focus")
    }

    func testRestoreReAddsDeletedAndResetsModifiedKeepingUUIDAndUserScenes() {
        var seeded = PresetScenes.seeded([userScene("Mine")])
        // delete "relax", modify "neon" (also capture-ify it)
        seeded.removeAll { $0.presetId == "relax" }
        let neonIndex = seeded.firstIndex { $0.presetId == "neon" }!
        let neonId = seeded[neonIndex].id
        seeded[neonIndex].title = "Custom"
        seeded[neonIndex].icon = "leaf.fill"
        seeded[neonIndex].color = HSVColor(h: 1, s: 2, v: 3)
        seeded[neonIndex].snapshots = []

        let restored = PresetScenes.restored(seeded)
        XCTAssertEqual(restored.prefix(5).compactMap(\.presetId), ids)
        XCTAssertEqual(restored.last?.title, "Mine")
        XCTAssertEqual(restored.count, 6)

        let neon = restored.first { $0.presetId == "neon" }!
        let def = LightScenePreset.preset(id: "neon")!
        XCTAssertEqual(neon.id, neonId)
        XCTAssertEqual(neon.title, def.title)
        XCTAssertEqual(neon.icon, def.icon)
        XCTAssertEqual(neon.color, def.color)
        XCTAssertNil(neon.snapshots)
    }

    func testRestoreIsIdempotent() {
        let once = PresetScenes.restored([userScene("Mine")])
        XCTAssertEqual(PresetScenes.restored(once), once)
    }

    func testResolveByPresetIdAndFallbackWhenDeleted() {
        var scenes = PresetScenes.seeded([])
        XCTAssertNotNil(PresetScenes.scene(forPresetId: "focus", in: scenes))
        scenes.removeAll { $0.presetId == "focus" }
        XCTAssertNil(PresetScenes.scene(forPresetId: "focus", in: scenes))
        // the caller falls back to the hard-coded definition
        XCTAssertNotNil(LightScenePreset.preset(id: "focus"))
        XCTAssertNil(LightScenePreset.preset(id: "nope"))
    }

    func testLegacySceneJSONWithoutPresetIdStillDecodes() throws {
        let legacy = """
        [{"id":"7B0E4B0C-6D6E-4D1F-9A2B-3C1D5E6F7A8B","title":"Old","icon":"moon.fill",
          "color":{"h":1,"s":2,"v":3},"createdAt":700000000}]
        """
        let decoder = JSONDecoder()
        let scenes = try decoder.decode([UserLightScene].self, from: Data(legacy.utf8))
        XCTAssertEqual(scenes.count, 1)
        XCTAssertNil(scenes[0].presetId)
    }

    func testPresetIdRoundTrips() throws {
        let scene = LightScenePreset.preset(id: "night")!.makeScene()
        let data = try JSONEncoder().encode([scene])
        let back = try JSONDecoder().decode([UserLightScene].self, from: data)
        XCTAssertEqual(back.first?.presetId, "night")
    }
}
