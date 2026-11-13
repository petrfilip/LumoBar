import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    var preferredPopoverSize: NSSize {
        NSSize(width: 410, height: preferredPopoverHeight)
    }

    private var preferredPopoverHeight: CGFloat {
        let height: CGFloat
        switch selectedTab {
        case .settings: height = 720
        // LampsView wraps its body in a ScrollView; the popover is sized to
        // a content-aware target capped at 860pt. Anything beyond scrolls
        // (rooms, expanded rows, scene editor).
        case .lamps:    height = lampsPopoverHeight
        }
        let screenMax = (popoverScreenVisibleHeight ?? NSScreen.main?.visibleFrame.height ?? 900) - 80
        return min(max(height, 360), screenMax)
    }

    private var lampsPopoverHeight: CGFloat {
        // Quiet Glass v2: tab strip removed (gear/back lives in the header).
        // header 56 + outer paddings 28 = ~84pt fixed chrome
        var h: CGFloat = 84

        // The message banner is not reserved: resizing the popover each time a
        // banner appeared/disappeared caused flicker; the ScrollView absorbs it.

        // status bar card (~56pt)
        h += 56 + 12

        // No providers configured → just show onboarding card.
        if !canSync {
            return min(h + 220, 540)
        }

        // search + offline toggle row
        if showsLampFilters { h += 44 }

        // empty/filter empty state card
        if lamps.isEmpty && !isAutoSyncing { return min(h + 200, 540) }

        if lamps.contains(where: { $0.capabilities.colorCode != nil }) {
            h += 84   // ScenePresetBar
        }
        if showsGroupControls {
            h += isGroupPanelExpanded || selectedLampIds.count >= 2 ? 220 : 60
        }

        // Reserve room for every visible lamp row (expanded rows at their full
        // height) + room headers. Previously capped at 3 rows / 620 pt, so two
        // expanded lamps already did not fit; the screen height is the real
        // limit (see preferredPopoverHeight), the ScrollView absorbs the rest.
        // Lamps inside a collapsed room are not shown: only their room header counts.
        let hiddenByCollapse = RoomLayout.lampIdsHiddenByCollapse(rooms: rooms, collapsedRoomIds: collapsedRoomIds)
        for lamp in visibleLamps where !hiddenByCollapse.contains(lamp.id) {
            h += expandedLampIds.contains(lamp.id) ? expandedLampRowHeight(for: lamp) : 72
        }

        let roomsWithLamps = rooms.filter { room in visibleLamps.contains(where: { room.lampIds.contains($0.id) }) }.count
        h += CGFloat(roomsWithLamps) * 48

        return min(h, 860)
    }

    private func expandedLampRowHeight(for lamp: LampDevice) -> CGFloat {
        var height: CGFloat = 62

        if showsGroupControls { height += 37 }   // "Add to group" row

        if lamp.capabilities.colorCode != nil || lamp.capabilities.brightness != nil || lamp.capabilities.temperature != nil {
            height += 30
        }

        if lamp.capabilities.temperature != nil {
            height += 30
        }

        if lamp.capabilities.colorCode != nil {
            height += 98
        }

        return height
    }
}
