import XCTest
@testable import LampControl

final class BusyCounterTests: XCTestCase {
    func testStaysBusyUntilTheLastOverlappingOperationEnds() {
        var busy = BusyCounter()
        XCTAssertFalse(busy.isBusy)
        busy.begin()
        busy.begin()
        busy.end()
        XCTAssertTrue(busy.isBusy, "the first operation to finish must not clear the busy state")
        busy.end()
        XCTAssertFalse(busy.isBusy)
    }

    func testUnbalancedEndNeverGoesNegative() {
        var busy = BusyCounter()
        busy.end()
        busy.begin()
        XCTAssertTrue(busy.isBusy)
    }
}

final class SyncGenerationTests: XCTestCase {
    func testTokenIsStaleAfterABump() {
        var generation = SyncGeneration()
        let token = generation.value
        XCTAssertTrue(generation.isCurrent(token))
        generation.bump()
        XCTAssertFalse(generation.isCurrent(token))
        XCTAssertTrue(generation.isCurrent(generation.value))
    }
}

@MainActor
final class TaskSlotTests: XCTestCase {
    func testReplaceCancelsThePreviousTaskAndRunsAfterItEnds() async {
        let slot = TaskSlot()
        var log: [String] = []
        slot.replace {
            log.append("first-start")
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000) }
            log.append("first-cancelled")
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        slot.replace { log.append("second") }
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(log, ["first-start", "first-cancelled", "second"])
        XCTAssertFalse(slot.isRunning)
    }

    func testCancelledBeforeItStartsNeverRuns() async {
        let slot = TaskSlot()
        var ran = false
        slot.replace { ran = true }
        slot.cancel()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(ran)
    }

    func testStartIfIdleKeepsTheRunningTask() async {
        let slot = TaskSlot()
        var runs = 0
        slot.startIfIdle { runs += 1; try? await Task.sleep(nanoseconds: 60_000_000) }
        slot.startIfIdle { runs += 100 }
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(runs, 1)
        slot.startIfIdle { runs += 10 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(runs, 11, "an idle slot accepts new work")
    }

    func testKeyedTasksReplaceOnlyTheSameKey() async {
        let tasks = KeyedTasks<String>()
        var finished: [String] = []
        tasks.replace("a") {
            try? await Task.sleep(nanoseconds: 40_000_000)
            if !Task.isCancelled { finished.append("a1") }
        }
        tasks.replace("b") {
            try? await Task.sleep(nanoseconds: 40_000_000)
            if !Task.isCancelled { finished.append("b") }
        }
        tasks.replace("a") { finished.append("a2") }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(Set(finished), ["a2", "b"])
        XCTAssertFalse(finished.contains("a1"))
    }
}

final class SectionEditorTests: XCTestCase {
    func testOnlyOneFormIsOpenAtATime() {
        var editor: SectionEditor<String> = .none
        XCTAssertFalse(editor.isOpen)
        editor = .create
        XCTAssertTrue(editor.isOpen)
        XCTAssertNil(editor.editingID)
        editor = .edit("r1")
        XCTAssertEqual(editor.editingID, "r1")
        XCTAssertNotEqual(editor, .create)
    }

    func testEditorClosesWhenItsItemDisappears() {
        XCTAssertEqual(SectionEditor<String>.edit("r1").resolved(existingIDs: ["r2"]), .none)
        XCTAssertEqual(SectionEditor<String>.edit("r1").resolved(existingIDs: ["r1"]), .edit("r1"))
        XCTAssertEqual(SectionEditor<String>.create.resolved(existingIDs: []), .create)
    }
}

final class SceneDeletionCleanupTests: XCTestCase {
    private let scene = UUID()

    func testDisablesDependentAutomationsAndMappingsOnly() {
        let dependent = Automation(name: "Evening", hour: 20, minute: 0, action: .applyProfile(id: scene))
        let other = Automation(name: "Other", hour: 21, minute: 0, action: .applyProfile(id: UUID()))
        let preset = Automation(name: "Preset", hour: 22, minute: 0, action: .applyScenePreset(id: "focus"))
        let mapping = FocusMapping(focusIdentifier: "work", focusDisplayName: "Work", sceneId: scene)
        let otherMapping = FocusMapping(focusIdentifier: "sleep", focusDisplayName: "Sleep", sceneId: UUID())

        let result = SceneDeletionCleanup.apply(
            deleting: scene, automations: [dependent, other, preset], focusMappings: [mapping, otherMapping])

        XCTAssertEqual(result.disabledCount, 2)
        XCTAssertEqual(result.automations.map(\.isEnabled), [false, true, true])
        XCTAssertFalse(result.focusMappings[0].isEnabled)
        XCTAssertNil(result.focusMappings[0].sceneId)
        XCTAssertTrue(result.focusMappings[1].isEnabled)
        XCTAssertNotNil(result.focusMappings[1].sceneId)
    }

    func testAlreadyDisabledEntriesAreNotCounted() {
        var automation = Automation(name: "Off", hour: 1, minute: 0, action: .applyProfile(id: scene))
        automation.isEnabled = false
        var mapping = FocusMapping(focusIdentifier: "work", focusDisplayName: "Work", sceneId: scene)
        mapping.isEnabled = false
        let result = SceneDeletionCleanup.apply(deleting: scene, automations: [automation], focusMappings: [mapping])
        XCTAssertEqual(result.disabledCount, 0)
        XCTAssertNil(result.focusMappings[0].sceneId, "the dangling reference is cleared either way")
    }

    func testReferenceCountMatchesWhatDeletionWouldDisable() {
        let automation = Automation(name: "A", hour: 1, minute: 0, action: .applyProfile(id: scene))
        XCTAssertEqual(SceneDeletionCleanup.referenceCount(for: scene, automations: [automation], focusMappings: []), 1)
        XCTAssertEqual(SceneDeletionCleanup.referenceCount(for: UUID(), automations: [automation], focusMappings: []), 0)
    }
}

final class FocusMappingListTests: XCTestCase {
    func testAddingTheSameFocusTwiceKeepsOneEntryWithTheNewScene() {
        let firstScene = UUID(), secondScene = UUID()
        let first = FocusMapping(focusIdentifier: "Work", focusDisplayName: "Work", sceneId: firstScene)
        var list = FocusMapping.adding(first, to: [])
        list = FocusMapping.adding(FocusMapping(focusIdentifier: " work ", focusDisplayName: "work", sceneId: secondScene), to: list)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, first.id)
        XCTAssertEqual(list[0].sceneId, secondScene)
    }

    func testAddingReEnablesADisabledMapping() {
        var disabled = FocusMapping(focusIdentifier: "sleep", focusDisplayName: "Sleep", sceneId: nil)
        disabled.isEnabled = false
        let list = FocusMapping.adding(FocusMapping(focusIdentifier: "sleep", focusDisplayName: "sleep", sceneId: UUID()), to: [disabled])
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(list[0].isEnabled)
    }

    func testAddingTheSameMappingIdTwiceDoesNotDuplicate() {
        let mapping = FocusMapping(focusIdentifier: "a", focusDisplayName: "a", sceneId: UUID())
        let list = FocusMapping.adding(mapping, to: FocusMapping.adding(mapping, to: []))
        XCTAssertEqual(list.count, 1)
    }

    func testUpdatingToAnExistingFocusDropsTheOtherEntry() {
        let a = FocusMapping(focusIdentifier: "work", focusDisplayName: "work", sceneId: UUID())
        var b = FocusMapping(focusIdentifier: "sleep", focusDisplayName: "sleep", sceneId: UUID())
        b.focusIdentifier = "Work"
        let list = FocusMapping.updating(b, in: [a, FocusMapping(id: b.id, focusIdentifier: "sleep", focusDisplayName: "sleep")])
        XCTAssertEqual(list.map(\.id), [b.id])
    }

    func testUpdatingAnUnknownMappingChangesNothing() {
        let a = FocusMapping(focusIdentifier: "work", focusDisplayName: "work")
        let list = FocusMapping.updating(FocusMapping(focusIdentifier: "x", focusDisplayName: "x"), in: [a])
        XCTAssertEqual(list, [a])
    }
}

final class LampDragPayloadTests: XCTestCase {
    func testRoundTrip() {
        XCTAssertEqual(LampDragPayload.decode(LampDragPayload.encode("yeelight:abc")), "yeelight:abc")
    }

    func testForeignTextIsNotALamp() {
        XCTAssertNil(LampDragPayload.decode("some text dragged from a browser"))
        XCTAssertNil(LampDragPayload.decode(""))
        XCTAssertNil(LampDragPayload.decode(LampDragPayload.encode("")))
    }
}
