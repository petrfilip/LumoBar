import XCTest
@testable import LampControl

final class JSONFileStoreTests: StoreTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13:20 UTC

    private func listStore() -> JSONListStore<Room> {
        JSONListStore(directory: dir, fileName: "rooms.json", recovery: recovery, now: { self.fixedNow })
    }

    func testMissingFileReturnsDefaultAndWritesNothing() throws {
        XCTAssertEqual(try listStore().load(), [])
        XCTAssertEqual(try filesInDir(), [])
        XCTAssertTrue(recovery.drain().isEmpty)
    }

    func testSaveCreatesTheFolderAndRoundTrips() throws {
        let nested = dir.appendingPathComponent("a/b")
        let store = JSONListStore<Room>(directory: nested, fileName: "rooms.json", recovery: recovery)
        try store.save([Room(id: "r", name: "Desk", lampIds: ["x"])])
        XCTAssertEqual(try store.load(), [Room(id: "r", name: "Desk", lampIds: ["x"])])
    }

    func testCorruptFileIsMovedAsideNotOverwritten() throws {
        try write("{ this is not json", to: "rooms.json")
        let store = listStore()

        XCTAssertEqual(try store.load(), [])
        XCTAssertFalse(store.exists, "the damaged file must leave its original name")
        XCTAssertEqual(try backups(of: "rooms"), ["rooms.corrupt-20231114-221320.json"])
        XCTAssertEqual(try read("rooms.corrupt-20231114-221320.json"), "{ this is not json")

        // Saving afterwards writes a fresh file and leaves the backup alone.
        try store.save([Room(id: "r", name: "New")])
        XCTAssertEqual(try store.load().map(\.name), ["New"])
        XCTAssertEqual(try read("rooms.corrupt-20231114-221320.json"), "{ this is not json")

        let events = recovery.drain()
        XCTAssertEqual(events, [DataRecovery(fileName: "rooms.json", backupName: "rooms.corrupt-20231114-221320.json",
                                             kind: .unreadable)])
        XCTAssertTrue(recovery.drain().isEmpty, "reported once")
    }

    func testTwoCorruptionsInTheSameSecondDoNotCollide() throws {
        let store = listStore()
        try write("garbage 1", to: "rooms.json")
        _ = try store.load()
        try write("garbage 2", to: "rooms.json")
        _ = try store.load()
        XCTAssertEqual(try backups(of: "rooms").count, 2)
        XCTAssertEqual(try read("rooms.corrupt-20231114-221320.json"), "garbage 1")
        XCTAssertEqual(try read("rooms.corrupt-20231114-221320-2.json"), "garbage 2")
    }

    func testWrongShapeIsTreatedAsUnreadable() throws {
        try write(#"{"rooms": []}"#, to: "rooms.json")   // an object where an array is expected
        let store = listStore()
        XCTAssertEqual(try store.load(), [])
        XCTAssertEqual(try backups(of: "rooms").count, 1)
    }

    func testEmptyFileIsTreatedAsUnreadable() throws {
        try write("", to: "rooms.json")
        XCTAssertEqual(try listStore().load(), [])
        XCTAssertEqual(try backups(of: "rooms").count, 1)
    }

    func testBadElementsAreSkippedAndTheOriginalIsCopiedOnce() throws {
        let json = #"[{"id":"a","name":"Kitchen","lampIds":[]},{"id":"b"},{"id":"c","name":"Bed","lampIds":["l"]}]"#
        try write(json, to: "rooms.json")
        let store = listStore()

        XCTAssertEqual(try store.load().map(\.id), ["a", "c"])
        XCTAssertEqual(try read("rooms.json"), json, "the original stays in place until the next save")
        XCTAssertEqual(try backups(of: "rooms").count, 1)
        XCTAssertEqual(try read("rooms.corrupt-20231114-221320.json"), json)
        XCTAssertEqual(recovery.drain(), [DataRecovery(fileName: "rooms.json",
                                                       backupName: "rooms.corrupt-20231114-221320.json",
                                                       kind: .partial(skipped: 1))])

        // Loading the same content again must not pile up copies or nag again.
        _ = try store.load()
        XCTAssertEqual(try backups(of: "rooms").count, 1)
        XCTAssertTrue(recovery.drain().isEmpty)
    }

    func testUnreadableErrorsOtherThanDecodingDoNotTouchTheFile() throws {
        // A directory where the file should be: reading fails, and it must be left alone.
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("rooms.json"),
                                                withIntermediateDirectories: true)
        XCTAssertThrowsError(try listStore().load())
        XCTAssertEqual(try filesInDir(), ["rooms.json"])
    }

    func testSaveIsBlockedWhileTheCorruptFileCannotBeMovedAside() throws {
        try write("garbage", to: "rooms.json")
        let store = listStore()
        // A read-only folder: the file can be read but not renamed, nor replaced.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save([Room(id: "x", name: "X")]))
        XCTAssertEqual(try read("rooms.json"), "garbage")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try store.save([Room(id: "x", name: "X")])
        XCTAssertEqual(try backups(of: "rooms").count, 1)
        XCTAssertEqual(try store.load().map(\.id), ["x"])
    }

    func testKeyedStoreFallsBackToDefaultOnCorruption() throws {
        try write("nope", to: "circadian-settings.json")
        let store = CircadianSettingsStore(directory: dir, recovery: recovery)
        XCTAssertEqual(try store.load(), .default)
        XCTAssertEqual(try backups(of: "circadian-settings").count, 1)
    }
}
