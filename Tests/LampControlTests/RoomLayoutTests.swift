import XCTest
@testable import LampControl

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
