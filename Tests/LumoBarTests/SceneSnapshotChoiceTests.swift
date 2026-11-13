import XCTest
@testable import LumoBar

final class SceneSnapshotChoiceTests: XCTestCase {
    private func snap(_ n: String) -> LampSnapshot {
        LampSnapshot(lampId: n, nativeID: n, providerID: .yeelight, name: n, power: true,
                     brightness: 1, temperature: nil, color: nil, workMode: nil)
    }

    func testEditingKeepsExistingSnapshotsByDefault() {
        var captured = false
        let result = SceneSnapshotChoice.snapshots(captureMode: true, existing: [snap("old")], isEditing: true, recapture: false) {
            captured = true; return [snap("new")]
        }
        XCTAssertEqual(result, [snap("old")])
        XCTAssertFalse(captured)
    }

    func testEditingWithRecaptureCapturesAgain() {
        let result = SceneSnapshotChoice.snapshots(captureMode: true, existing: [snap("old")], isEditing: true, recapture: true) { [snap("new")] }
        XCTAssertEqual(result, [snap("new")])
    }

    func testCreatingCaptures() {
        let result = SceneSnapshotChoice.snapshots(captureMode: true, existing: nil, isEditing: false, recapture: false) { [snap("new")] }
        XCTAssertEqual(result, [snap("new")])
    }

    func testColorSceneHasNoSnapshots() {
        XCTAssertNil(SceneSnapshotChoice.snapshots(captureMode: false, existing: nil, isEditing: true, recapture: true) { [snap("x")] })
    }
}
