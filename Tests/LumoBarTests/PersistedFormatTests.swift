import XCTest
@testable import LumoBar

/// JSON in the format the current app writes, one sample per persisted type. These must keep
/// decoding: they stand in for the files existing users already have.
final class PersistedFormatTests: StoreTestCase {
    func testAutomationsFileDecodesEveryActionShape() throws {
        let profile = "0E5C1F1C-1D6B-4E5B-9E0A-5C7D3B7C9A11"
        try write("""
        [
          {"id":"11111111-1111-1111-1111-111111111111","name":"Morning","isEnabled":true,"hour":7,"minute":30,
           "weekdays":[1,2,3],"action":{"powerOnAll":{}},"lastFiredDate":721000000.5},
          {"id":"22222222-2222-2222-2222-222222222222","name":"Scene","isEnabled":false,"hour":20,"minute":0,
           "weekdays":[],"action":{"applyScenePreset":{"id":"focus"}}},
          {"id":"33333333-3333-3333-3333-333333333333","name":"Profile","isEnabled":true,"hour":21,"minute":15,
           "weekdays":[],"action":{"applyProfile":{"id":"\(profile)"}}},
          {"id":"44444444-4444-4444-4444-444444444444","name":"Off","isEnabled":true,"hour":23,"minute":0,
           "weekdays":[7],"action":{"powerOffAll":{}}},
          {"id":"55555555-5555-5555-5555-555555555555","name":"A","isEnabled":true,"hour":6,"minute":0,
           "weekdays":[],"action":{"enableAdaptiveLighting":{}}},
          {"id":"66666666-6666-6666-6666-666666666666","name":"B","isEnabled":true,"hour":6,"minute":0,
           "weekdays":[],"action":{"disableAdaptiveLighting":{}}}
        ]
        """, to: "automations.json")
        let list = try AutomationStore(directory: dir, recovery: recovery).load()
        XCTAssertEqual(list.count, 6)
        XCTAssertEqual(list[0].weekdays, [1, 2, 3])
        XCTAssertEqual(list[0].lastFiredDate, Date(timeIntervalSinceReferenceDate: 721000000.5))
        XCTAssertEqual(list[1].action, .applyScenePreset(id: "focus"))
        XCTAssertFalse(list[1].isEnabled)
        XCTAssertEqual(list[2].action, .applyProfile(id: UUID(uuidString: profile)!))
        XCTAssertEqual(list[3].action, .powerOffAll)
        XCTAssertEqual(list[4].action, .enableAdaptiveLighting)
        XCTAssertEqual(list[5].action, .disableAdaptiveLighting)
        XCTAssertTrue(recovery.drain().isEmpty)
    }

    func testAutomationEncodingKeepsTheShapeOldVersionsRead() throws {
        let a = Automation(name: "N", hour: 7, minute: 5, weekdays: [2], action: .applyScenePreset(id: "relax"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "name", "isEnabled", "hour", "minute", "weekdays", "action"])
        XCTAssertEqual((object["action"] as? [String: Any])?.keys.first, "applyScenePreset")
    }

    func testAutomationWithOnlyRequiredFieldsGetsDefaults() throws {
        let json = #"[{"name":"Old","hour":8,"minute":0,"action":{"powerOnAll":{}}}]"#
        try write(json, to: "automations.json")
        let a = try XCTUnwrap(AutomationStore(directory: dir, recovery: recovery).load().first)
        XCTAssertTrue(a.isEnabled)
        XCTAssertEqual(a.weekdays, [])
        XCTAssertNil(a.lastFiredDate)
    }

    func testUnknownAutomationActionKeepsTheOtherAutomations() throws {
        try write("""
        [{"name":"Keep","hour":8,"minute":0,"action":{"powerOnAll":{}}},
         {"name":"FromTheFuture","hour":9,"minute":0,"action":{"setMood":{"id":"x"}}},
         {"name":"AlsoKeep","hour":10,"minute":0,"action":{"powerOffAll":{}}}]
        """, to: "automations.json")
        let list = try AutomationStore(directory: dir, recovery: recovery).load()
        XCTAssertEqual(list.map(\.name), ["Keep", "AlsoKeep"])
        XCTAssertEqual(try backups(of: "automations").count, 1)
    }

    func testCircadianFileDecodes() throws {
        try write("""
        {"isEnabled":true,"applyBrightness":false,"applyTemperature":true,
         "keyframes":[{"id":"11111111-1111-1111-1111-111111111111","hour":6,"minute":0,"brightness":50,"temperature":4000},
                      {"id":"22222222-2222-2222-2222-222222222222","hour":22,"minute":30,"brightness":20,"temperature":2400}]}
        """, to: "circadian-settings.json")
        let s = try CircadianSettingsStore(directory: dir, recovery: recovery).load()
        XCTAssertTrue(s.isEnabled)
        XCTAssertFalse(s.applyBrightness)
        XCTAssertEqual(s.keyframes.map(\.minuteOfDay), [360, 1350])
    }

    func testCircadianFieldsAddedLaterFallBackToDefaults() throws {
        try write(#"{"isEnabled":true,"keyframes":[{"hour":6,"minute":0,"brightness":50,"temperature":4000}]}"#,
                  to: "circadian-settings.json")
        let s = try CircadianSettingsStore(directory: dir, recovery: recovery).load()
        XCTAssertTrue(s.applyBrightness)
        XCTAssertTrue(s.applyTemperature)
        XCTAssertEqual(s.keyframes.count, 1)

        try write("{}", to: "circadian-settings.json")
        let empty = try CircadianSettingsStore(directory: dir, recovery: recovery).load()
        XCTAssertEqual(empty, .default)
    }

    func testFocusMappingsDecodeWithAndWithoutOptionalFields() throws {
        let scene = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        try write("""
        [{"id":"m1","focusIdentifier":"work","focusDisplayName":"Work","sceneId":"\(scene)","isEnabled":false},
         {"focusIdentifier":"sleep","focusDisplayName":"Sleep"}]
        """, to: "focusMappings.json")
        let list = try FocusMappingStore(directory: dir, recovery: recovery).loadMappings()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].sceneId, UUID(uuidString: scene))
        XCTAssertFalse(list[0].isEnabled)
        XCTAssertTrue(list[1].isEnabled)
        XCTAssertNil(list[1].sceneId)
        XCTAssertFalse(list[1].id.isEmpty)
    }

    func testRoomsDecode() throws {
        try write(#"[{"id":"r1","name":"Living room","lampIds":["tuya:a","wiz:b"]}]"#, to: "rooms.json")
        let rooms = try RoomStore(directory: dir, recovery: recovery).loadRooms()
        XCTAssertEqual(rooms, [Room(id: "r1", name: "Living room", lampIds: ["tuya:a", "wiz:b"])])
    }

    func testScenesDecodePresetAndCaptureScenes() throws {
        try write("""
        [{"id":"11111111-1111-1111-1111-111111111111","title":"Focus","icon":"sun.max.fill",
          "color":{"h":42,"s":360,"v":1000},"createdAt":700000000,"presetId":"focus"},
         {"id":"22222222-2222-2222-2222-222222222222","title":"Snap","icon":"camera","color":{"h":0,"s":0,"v":1000},
          "createdAt":700000001,
          "snapshots":[{"lampId":"yeelight:1","nativeID":"1","providerID":"yeelight","name":"Desk","power":true,
                        "brightness":80,"temperature":4000,"color":{"h":10,"s":20,"v":30},"workMode":"white"}]}]
        """, to: "scenes.json")
        let scenes = try LightSceneStore(directory: dir, recovery: recovery).load()
        XCTAssertEqual(scenes.count, 2)
        XCTAssertEqual(scenes[0].presetId, "focus")
        XCTAssertFalse(scenes[0].isCapture)
        XCTAssertTrue(scenes[1].isCapture)
        XCTAssertEqual(scenes[1].snapshots?.first?.providerID, .yeelight)
        XCTAssertEqual(scenes[1].snapshots?.first?.color, HSVColor(h: 10, s: 20, v: 30))
        XCTAssertEqual(scenes[1].snapshots?.first?.workMode, "white")
        XCTAssertTrue(recovery.drain().isEmpty)
    }

    func testSceneSavedByOldVersionWithoutOptionalFieldsDecodes() throws {
        try write("""
        [{"id":"11111111-1111-1111-1111-111111111111","title":"Old","icon":"moon","color":{"h":1,"s":2,"v":3},
          "createdAt":1,"snapshots":[{"lampId":"a","nativeID":"a","providerID":"tuya","name":"L","power":false}]}]
        """, to: "scenes.json")
        let scene = try XCTUnwrap(LightSceneStore(directory: dir, recovery: recovery).load().first)
        XCTAssertNil(scene.presetId)
        XCTAssertNil(scene.snapshots?.first?.brightness)
    }

    func testUnknownProviderInASnapshotKeepsTheSceneAndOtherSnapshots() throws {
        try write("""
        [{"id":"11111111-1111-1111-1111-111111111111","title":"Snap","icon":"camera","color":{"h":0,"s":0,"v":0},
          "createdAt":1,
          "snapshots":[{"lampId":"a","nativeID":"a","providerID":"tuya","name":"Ok","power":true},
                       {"lampId":"b","nativeID":"b","providerID":"somethingNew","name":"New","power":true}]},
         {"id":"22222222-2222-2222-2222-222222222222","title":"Other","icon":"moon","color":{"h":1,"s":2,"v":3},
          "createdAt":1}]
        """, to: "scenes.json")
        let scenes = try LightSceneStore(directory: dir, recovery: recovery).load()
        XCTAssertEqual(scenes.map(\.title), ["Snap", "Other"])
        XCTAssertEqual(scenes[0].snapshots?.map(\.name), ["Ok"])
        XCTAssertEqual(try backups(of: "scenes").count, 1)
    }

    func testSceneWithNullSnapshotsIsNotACaptureScene() throws {
        try write(#"[{"id":"11111111-1111-1111-1111-111111111111","title":"T","icon":"i","color":{"h":1,"s":2,"v":3},"createdAt":1,"snapshots":null}]"#,
                  to: "scenes.json")
        let scene = try XCTUnwrap(LightSceneStore(directory: dir, recovery: recovery).load().first)
        XCTAssertFalse(scene.isCapture)
    }

    func testTuyaSettingsFileDecodesAndUnknownRegionBecomesCustom() throws {
        try write(#"{"accessId":"id","endpoint":"https://openapi.tuyaeu.com","uid":"u1","region":"eu"}"#, to: "settings.json")
        let store = SettingsStore(directory: dir, keychain: MemorySecrets(), recovery: recovery)
        let snapshot = try store.load()
        XCTAssertEqual(snapshot.settings.region, .eu)
        XCTAssertEqual(snapshot.settings.uid, "u1")
        XCTAssertFalse(snapshot.hasSecret)

        try write(#"{"accessId":"id","endpoint":"https://example.test","uid":"u1","region":"mars"}"#, to: "settings.json")
        let future = try store.load().settings
        XCTAssertEqual(future.region, .custom)
        XCTAssertEqual(future.endpoint, "https://example.test", "the endpoint of the unknown region is kept")
        XCTAssertTrue(recovery.drain().isEmpty, "an unknown region is tolerated, not a corruption")
    }

    func testTuyaSettingsRoundTripKeepsTheSecretOutOfTheFile() throws {
        let secrets = MemorySecrets()
        let store = SettingsStore(directory: dir, keychain: secrets, recovery: recovery)
        var settings = TuyaSettings()
        settings.accessId = "id"; settings.accessSecret = "topsecret"; settings.uid = "u"
        let saved = try store.save(settings)
        XCTAssertTrue(saved.hasSecret)
        XCTAssertFalse(try read("settings.json").contains("topsecret"))
        XCTAssertEqual(try store.accessSecret(), "topsecret")
        XCTAssertEqual(secrets.items["LumoBar.Tuya/tuya-access-secret"], "topsecret")
    }

    func testLampOrderDecodesAndSurvivesCorruption() throws {
        try write(#"["tuya:a","wiz:b"]"#, to: "lampOrder.json")
        let store = SettingsStore(directory: dir, keychain: MemorySecrets(), recovery: recovery)
        XCTAssertEqual(store.loadLampOrder(), ["tuya:a", "wiz:b"])

        try write("not json", to: "lampOrder.json")
        XCTAssertEqual(store.loadLampOrder(), [])
        XCTAssertEqual(try backups(of: "lampOrder").count, 1)
        store.saveLampOrder(["x"])
        XCTAssertEqual(store.loadLampOrder(), ["x"])
    }

    func testHueSettingsDecodeAndNeverStoreTheUserInTheFile() throws {
        try write(#"{"bridgeID":"b1","bridgeIP":"192.168.1.2","username":""}"#, to: "hue-settings.json")
        let secrets = MemorySecrets()
        let store = HueSettingsStore(directory: dir, keychain: secrets, recovery: recovery)
        XCTAssertEqual(try store.load().bridgeIP, "192.168.1.2")

        let saved = try store.save(HueSettings(bridgeID: "b1", bridgeIP: "10.0.0.5", username: "user-key"))
        XCTAssertEqual(saved.username, "user-key")
        XCTAssertFalse(try read("hue-settings.json").contains("user-key"))
    }

    func testYeelightSettingsDecodeWithAndWithoutDeviceId() throws {
        try write("""
        {"bulbs":[{"id":"b1","host":"192.168.1.4","port":55443,"name":"Desk","deviceId":"0x0000000000152"},
                  {"id":"b2","host":"192.168.1.5","port":55443,"name":"Old"}]}
        """, to: "yeelight-settings.json")
        let s = try YeelightSettingsStore(directory: dir, recovery: recovery).load()
        XCTAssertEqual(s.bulbs.map(\.id), ["b1", "b2"])
        XCTAssertEqual(s.bulbs[0].deviceId, "0x0000000000152")
        XCTAssertNil(s.bulbs[1].deviceId)
    }

    func testOneBadYeelightBulbDoesNotDropTheOthers() throws {
        try write(#"{"bulbs":[{"id":"b1","host":"h","port":1,"name":"A"},{"id":"b2"}]}"#, to: "yeelight-settings.json")
        let s = try YeelightSettingsStore(directory: dir, recovery: recovery).load()
        XCTAssertEqual(s.bulbs.map(\.id), ["b1"])
        XCTAssertEqual(try backups(of: "yeelight-settings").count, 1)
    }

    func testWizSettingsDecodeWithAndWithoutPort() throws {
        try write("""
        {"devices":[{"id":"11111111-1111-1111-1111-111111111111","name":"Bulb","host":"192.168.1.7","port":38899},
                    {"name":"NoPort","host":"192.168.1.8"}]}
        """, to: "wiz-settings.json")
        let s = try WizSettingsStore(directory: dir, recovery: recovery).load()
        XCTAssertEqual(s.devices.map(\.host), ["192.168.1.7", "192.168.1.8"])
        XCTAssertEqual(s.devices[1].port, 38899)
    }

    func testWizSettingsRoundTrip() throws {
        let store = WizSettingsStore(directory: dir, recovery: recovery)
        let device = WizDevice(name: "A", host: "10.0.0.2", port: 1234)
        let saved = try store.save(WizSettings(devices: [device]))
        XCTAssertEqual(saved.devices.first?.id, device.id)
        XCTAssertEqual(saved.devices.first?.port, 1234)
    }
}
