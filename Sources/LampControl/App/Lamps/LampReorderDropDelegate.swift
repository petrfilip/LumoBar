import SwiftUI

struct LampReorderDropDelegate: DropDelegate {
    let targetLamp: LampDevice
    @Binding var draggedLampID: String?
    let appState: AppState
    let canReorder: Bool

    func validateDrop(info: DropInfo) -> Bool {
        LampDragRules.isLampDrag(dragged: draggedLampID, canReorder: canReorder)
    }

    func dropEntered(info: DropInfo) {
        guard LampDragRules.acceptsDrop(dragged: draggedLampID, onto: targetLamp.id, canReorder: canReorder),
              let draggedLampID
        else { return }

        // Lamps added after the order was saved are not in it yet: normalise first so they
        // can be dragged (and dropped on) like any other.
        guard let updatedOrder = LampOrder.moving(
            draggedLampID, onto: targetLamp.id,
            in: appState.lampOrderIds, knownIds: appState.lamps.map(\.id)) else { return }
        appState.updateLampOrder(updatedOrder)
    }

    func performDrop(info: DropInfo) -> Bool {
        let handled = draggedLampID != nil
        draggedLampID = nil
        return handled
    }
}
