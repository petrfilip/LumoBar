import XCTest
@testable import LumoBar

final class RoomLayoutTests: XCTestCase {
    private func plan(loaded: [Room] = [], file: Bool = false, migrated: Bool = false, lamps: [String] = ["a", "b"]) -> RoomLayout.MigrationPlan {
        RoomLayout.migrationPlan(loaded: loaded, hasRoomsFile: file, alreadyMigrated: migrated, lampIds: lamps, defaultRoomName: "My lamps")
    }

    func testFirstRunCreatesLocalizedDefaultRoomWithAllLamps() {
        let result = plan()
        XCTAssertEqual(result.rooms.count, 1)
        XCTAssertEqual(result.rooms[0].name, "My lamps")
        XCTAssertEqual(result.rooms[0].lampIds, ["a", "b"])
        XCTAssertTrue(result.persist)
        XCTAssertTrue(result.markMigrated)
    }

    func testDeletingAllRoomsDoesNotRecreateThem() {
        XCTAssertEqual(plan(migrated: true).rooms, [])
        XCTAssertFalse(plan(migrated: true).persist)
        // Upgrade case: no flag yet but the user already saved an (empty) rooms file.
        XCTAssertEqual(plan(file: true).rooms, [])
        XCTAssertTrue(plan(file: true).markMigrated)
    }

    func testExistingRoomsAreKeptAndFlagged() {
        let rooms = [Room(name: "Kitchen", lampIds: ["a"])]
        let result = plan(loaded: rooms, file: true)
        XCTAssertEqual(result.rooms, rooms)
        XCTAssertFalse(result.persist)
        XCTAssertTrue(result.markMigrated)
    }

    func testNoLampsYetDefersMigration() {
        let result = plan(lamps: [])
        XCTAssertEqual(result.rooms, [])
        XCTAssertFalse(result.markMigrated)
        XCTAssertFalse(result.persist)
    }

    func testLampsHiddenByCollapse() {
        let kitchen = Room(id: "k", name: "Kitchen", lampIds: ["a", "b"])
        let bedroom = Room(id: "r", name: "Bedroom", lampIds: ["c"])
        XCTAssertEqual(RoomLayout.lampIdsHiddenByCollapse(rooms: [kitchen, bedroom], collapsedRoomIds: ["k"]), ["a", "b"])
        XCTAssertEqual(RoomLayout.lampIdsHiddenByCollapse(rooms: [kitchen, bedroom], collapsedRoomIds: []), [])
        XCTAssertEqual(RoomLayout.lampIdsHiddenByCollapse(rooms: [kitchen], collapsedRoomIds: ["gone"]), [])
    }
}

final class RoomGroupingTests: XCTestCase {
    private func lamp(_ id: String) -> LampDevice {
        LampDevice(id: id, providerID: .wiz, nativeID: id, name: id, online: true, power: false,
                   brightness: nil, temperature: nil, color: nil, workMode: nil, capabilities: LightCapabilities())
    }

    func testLampsFollowTheirOrderInsideEachRoomAndRoomsKeepTheirOrder() {
        let kitchen = Room(id: "k", name: "Kitchen", lampIds: ["a", "c"])
        let bedroom = Room(id: "b", name: "Bedroom", lampIds: ["b"])
        // Visible order differs from the order in the room's own list.
        let result = RoomLayout.group(lamps: [lamp("c"), lamp("b"), lamp("a")], rooms: [kitchen, bedroom])
        XCTAssertEqual(result.sections.map(\.id), ["k", "b"])
        XCTAssertEqual(result.sections[0].lamps.map(\.id), ["c", "a"])
        XCTAssertEqual(result.sections[1].lamps.map(\.id), ["b"])
        XCTAssertTrue(result.unassigned.isEmpty)
    }

    func testUnassignedLampsAreCollectedInOrder() {
        let room = Room(id: "k", name: "Kitchen", lampIds: ["a"])
        let result = RoomLayout.group(lamps: [lamp("z"), lamp("a"), lamp("y")], rooms: [room])
        XCTAssertEqual(result.unassigned.map(\.id), ["z", "y"])
    }

    func testRoomsWithoutVisibleLampsAreOmitted() {
        let empty = Room(id: "e", name: "Empty", lampIds: [])
        let hidden = Room(id: "h", name: "Hidden", lampIds: ["gone"])
        let shown = Room(id: "s", name: "Shown", lampIds: ["a"])
        let result = RoomLayout.group(lamps: [lamp("a")], rooms: [empty, hidden, shown])
        XCTAssertEqual(result.sections.map(\.id), ["s"])
    }

    func testLampListedByTwoRoomsAppearsInBothAndIsNotUnassigned() {
        let one = Room(id: "1", name: "One", lampIds: ["a", "a"])
        let two = Room(id: "2", name: "Two", lampIds: ["a"])
        let result = RoomLayout.group(lamps: [lamp("a")], rooms: [one, two])
        XCTAssertEqual(result.sections.map(\.id), ["1", "2"])
        XCTAssertEqual(result.sections.map { $0.lamps.map(\.id) }, [["a"], ["a"]])
        XCTAssertTrue(result.unassigned.isEmpty)
    }

    func testNoRoomsMeansEverythingIsUnassigned() {
        let result = RoomLayout.group(lamps: [lamp("a"), lamp("b")], rooms: [])
        XCTAssertTrue(result.sections.isEmpty)
        XCTAssertEqual(result.unassigned.map(\.id), ["a", "b"])
    }
}
