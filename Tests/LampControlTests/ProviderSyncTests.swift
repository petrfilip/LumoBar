import XCTest
@testable import LampControl

final class ProviderSyncTests: XCTestCase {
    private struct Boom: Error {}

    private func lamp(_ id: String, _ name: String, _ kind: LightProviderKind, online: Bool = true) -> LampDevice {
        LampDevice(id: id, providerID: kind, nativeID: id, name: name, online: online, power: true,
                   brightness: nil, temperature: nil, color: nil, workMode: nil, capabilities: LightCapabilities())
    }

    func testFailingProviderKeepsItsPreviousLampsOfflineAndOthersSurvive() {
        let previous = [lamp("t1", "Tuya lamp", .tuya), lamp("w1", "WiZ lamp", .wiz)]
        let merged = ProviderSyncMerge.merge(previous: previous, results: [
            ProviderSyncResult(kind: .tuya, outcome: .failure(Boom())),
            ProviderSyncResult(kind: .wiz, outcome: .success([lamp("w1", "WiZ lamp", .wiz), lamp("w2", "Another", .wiz)]))
        ])
        XCTAssertEqual(merged.lamps.map(\.id), ["w2", "t1", "w1"])
        XCTAssertFalse(merged.lamps.first { $0.id == "t1" }!.online)
        XCTAssertTrue(merged.lamps.first { $0.id == "w1" }!.online)
        XCTAssertEqual(merged.failedKinds, [.tuya])
        XCTAssertTrue(merged.didSync)
    }

    func testAllProvidersFailingKeepsEverythingOfflineAndDidNotSync() {
        let previous = [lamp("t1", "A", .tuya), lamp("w1", "B", .wiz)]
        let merged = ProviderSyncMerge.merge(previous: previous, results: [
            ProviderSyncResult(kind: .tuya, outcome: .failure(Boom())),
            ProviderSyncResult(kind: .wiz, outcome: .failure(Boom()))
        ])
        XCTAssertEqual(merged.lamps.count, 2)
        XCTAssertTrue(merged.lamps.allSatisfy { !$0.online })
        XCTAssertFalse(merged.didSync)
    }

    func testDroppedProviderForgetsItsOldLampsOnFailure() {
        let previous = [lamp("t1", "A", .tuya), lamp("w1", "B", .wiz)]
        let merged = ProviderSyncMerge.merge(previous: previous, results: [
            ProviderSyncResult(kind: .tuya, outcome: .failure(Boom())),
            ProviderSyncResult(kind: .wiz, outcome: .success([lamp("w1", "B", .wiz)]))
        ], dropPrevious: [.tuya])
        XCTAssertEqual(merged.lamps.map(\.id), ["w1"])
    }

    func testNoConfiguredProvidersMeansEmptyListAndNothingFailed() {
        let merged = ProviderSyncMerge.merge(previous: [lamp("t1", "A", .tuya)], results: [])
        XCTAssertTrue(merged.lamps.isEmpty)
        XCTAssertTrue(merged.failures.isEmpty)
        XCTAssertTrue(merged.didSync)
    }

    func testLampsAreSortedByNameAcrossProviders() {
        let merged = ProviderSyncMerge.merge(previous: [], results: [
            ProviderSyncResult(kind: .wiz, outcome: .success([lamp("w", "banana", .wiz)])),
            ProviderSyncResult(kind: .lifx, outcome: .success([lamp("l", "Apple", .lifx), lamp("l2", "cherry", .lifx)]))
        ])
        XCTAssertEqual(merged.lamps.map(\.name), ["Apple", "banana", "cherry"])
    }

    func testFailureTrackerAnnouncesOnceUntilRecovery() {
        var tracker = SyncFailureTracker()
        XCTAssertEqual(tracker.newlyFailed([.tuya]), [.tuya])
        XCTAssertEqual(tracker.newlyFailed([.tuya]), [])
        XCTAssertEqual(tracker.newlyFailed([.tuya, .wiz]), [.wiz])
        XCTAssertEqual(tracker.newlyFailed([]), [])
        XCTAssertEqual(tracker.newlyFailed([.tuya]), [.tuya])
    }
}
