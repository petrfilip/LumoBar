import SwiftUI
import AppKit

struct LampsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draggedLampID: String?
    @State private var dragWatch: Task<Void, Never>?
    private let ink = LCPalette.ink
    private let muted = LCPalette.muted
    private let accent = LCPalette.accent

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            scrollableContent
        }
        .scrollIndicators(.never)
        .onDisappear {
            dragWatch?.cancel()
            draggedLampID = nil
        }
    }

    @ViewBuilder
    private var scrollableContent: some View {
        // `visibleLamps` filters and sorts every time it is read: evaluate it once per body.
        let visibleLamps = appState.visibleLamps
        VStack(spacing: LCSpacing.sm) {
            statusBar(onlineCount: visibleLamps.lazy.filter(\.online).count)

            // Search and filter controls
            if appState.showsLampFilters && appState.canSync {
                HStack(spacing: LCSpacing.xs) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(muted)
                        TextField("lamps.search.placeholder", text: $appState.searchText)
                            .font(LCTypo.body())
                            .textFieldStyle(.plain)
                        if !appState.searchText.isEmpty {
                            Button { appState.searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(muted)
                                    .frame(width: 22, height: 22)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(LCPressableButtonStyle())
                            .help("help.search.clear")
                        }
                    }
                    .padding(.horizontal, LCSpacing.sm)
                    .frame(height: 36)
                    .lcChip(tint: Color.white.opacity(0.05))

                    // Toggle offline lamps
                    Button {
                        withAnimation(LCAnimation.snap) {
                            appState.hideOfflineLamps.toggle()
                        }
                    } label: {
                        Image(systemName: appState.hideOfflineLamps ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(appState.hideOfflineLamps ? accent : muted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(LCGlassButtonStyle(prominent: appState.hideOfflineLamps, radius: 18))
                    .help(appState.hideOfflineLamps ? L10n.lampsShowAllHelp : L10n.lampsHideOfflineHelp)
                }
            }

            if !appState.canSync {
                onboardingCard
            } else if appState.lamps.isEmpty && !appState.isAutoSyncing {
                emptyStateCard
            } else if visibleLamps.isEmpty && !appState.lamps.isEmpty {
                HStack(spacing: LCSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(muted)
                        .frame(width: 32, height: 32)
                        .lcCard(radius: 16, tint: Color.white.opacity(0.06))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("lamps.filter.empty.title")
                            .font(LCTypo.bodySemibold())
                            .foregroundStyle(ink)
                        Text(appState.hideOfflineLamps ? "lamps.filter.empty.offline" : "lamps.filter.empty.search")
                            .font(LCTypo.micro())
                            .foregroundStyle(muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, LCSpacing.sm)
                .padding(.vertical, LCSpacing.sm)
                .lcCard(radius: LCRadius.card, tint: LCPalette.accent.opacity(0.08))
            }

            if appState.lamps.contains(where: { $0.capabilities.colorCode != nil }) {
                ScenePresetBar()
            }
            if appState.showsGroupControls {
                GroupControlEntry()
            }

            LazyVStack(spacing: 8) {
                // Group lamps by room, in one pass over the visible lamps.
                let grouping = RoomLayout.group(lamps: visibleLamps, rooms: appState.rooms)
                let showsGroupControls = appState.showsGroupControls

                ForEach(grouping.sections) { section in
                    let room = section.room
                    let roomLamps = section.lamps
                    VStack(spacing: LCSpacing.xs) {
                        HStack(spacing: LCSpacing.xs) {
                            Button {
                                withAnimation(LCAnimation.snap) { appState.toggleRoomExpanded(room.id) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: appState.isRoomExpanded(room.id) ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(muted)
                                        .frame(width: 12)
                                    Text(room.name.uppercased())
                                        .font(LCTypo.sectionHeader())
                                        .tracking(0.6)
                                        .foregroundStyle(muted)
                                        .lineLimit(1)
                                    if !appState.isRoomExpanded(room.id) {
                                        Text(L10n.lampCount(roomLamps.count))
                                            .font(LCTypo.micro())
                                            .foregroundStyle(muted.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(LCPressableButtonStyle())

                            Menu {
                                Button {
                                    Task { await appState.setPowerForRoom(room.id, value: true) }
                                } label: { Label(L10n.roomAllOn, systemImage: "lightbulb.fill") }
                                Button {
                                    Task { await appState.setPowerForRoom(room.id, value: false) }
                                } label: { Label(L10n.roomAllOff, systemImage: "lightbulb.slash") }
                                if !appState.userScenes.isEmpty {
                                    Divider()
                                    Section("lamps.room.scenes") {
                                        ForEach(appState.userScenes) { scene in
                                            Button(scene.title) { Task { await appState.applyScene(scene, toRoomId: room.id, byUser: true) } }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(LCPalette.muted)
                                    .frame(width: 28, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(BorderlessButtonMenuStyle())
                            .help("help.room.menu")
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .disabled(appState.isBusy)
                        }
                        .padding(.horizontal, LCSpacing.xs)
                        .padding(.top, LCSpacing.sm)
                        .padding(.bottom, LCSpacing.xxs)

                        if appState.isRoomExpanded(room.id) {
                            ForEach(roomLamps) { lamp in
                                reorderableRow(lamp, showsGroupControls: showsGroupControls)
                            }
                        }
                    }
                }

                // Unassigned lamps
                let unassigned = grouping.unassigned
                if !unassigned.isEmpty {
                    VStack(spacing: LCSpacing.xs) {
                        HStack(spacing: LCSpacing.xs) {
                            Text("lamps.unassigned")
                                .font(LCTypo.sectionHeader())
                                .tracking(0.5)
                                .foregroundStyle(muted)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, LCSpacing.xs)
                        .padding(.top, LCSpacing.xxs)

                        ForEach(unassigned) { lamp in
                            reorderableRow(lamp, showsGroupControls: showsGroupControls)
                        }
                    }
                }
            }
        }
        .foregroundStyle(ink)
    }

    private var canReorderLamps: Bool {
        appState.searchText.isEmpty && !appState.hideOfflineLamps
    }

    private func reorderableRow(_ lamp: LampDevice, showsGroupControls: Bool) -> some View {
        LampRow(
            appState: appState,
            lamp: lamp,
            isSelected: appState.selectedLampIds.contains(lamp.id),
            isExpanded: appState.isAdvancedControlsExpanded(for: lamp),
            showsGroupControls: showsGroupControls
        )
        .equatable()
            .opacity(draggedLampID == lamp.id ? 0.72 : 1)
            .onDrag {
                beginDragging(lamp.id)
                return NSItemProvider(object: lamp.id as NSString)
            }
            .onDrop(of: [.text], delegate: LampReorderDropDelegate(
                targetLamp: lamp,
                draggedLampID: $draggedLampID,
                appState: appState,
                canReorder: canReorderLamps
            ))
    }

    /// SwiftUI never says when a drag was cancelled (Escape, released outside every row), which
    /// left the row dimmed and later let any dragged text reorder the list. Watch the mouse
    /// button instead: once it is up the drag session is over; a normal drop has handled
    /// itself by then, so the short wait only clears what a drop did not.
    private func beginDragging(_ lampID: String) {
        draggedLampID = lampID
        dragWatch?.cancel()
        dragWatch = Task { @MainActor in
            while !Task.isCancelled, !LampDragRules.isDragFinished(pressedMouseButtons: NSEvent.pressedMouseButtons) {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { draggedLampID = nil }
        }
    }

    private var onboardingCard: some View {
        Button {
            withAnimation(LCAnimation.snap) {
                appState.selectedTab = .settings
            }
        } label: {
            HStack(spacing: LCSpacing.sm) {
                LCIconBadge(systemName: "sparkles",
                            size: 40,
                            tint: .orange,
                            fontSize: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("lamps.welcome.title")
                        .font(LCTypo.bodySemibold())
                        .foregroundStyle(ink)
                    Text("lamps.welcome.subtitle")
                        .font(LCTypo.micro())
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: LCSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(muted)
            }
            .padding(LCSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(LCPressableButtonStyle())
        .lcCard(radius: LCRadius.card, tint: Color.orange.opacity(0.12))
        .lcHoverable(glowTint: .orange, radius: LCRadius.card)
        .help("lamps.open.settings")
    }

    private var emptyStateCard: some View {
        LCEmptyState(
            icon: "lightbulb.slash",
            title: "lamps.empty.title",
            subtitle: "lamps.empty.subtitle"
        )
    }

    private func statusBar(onlineCount: Int) -> some View {
        HStack(spacing: LCSpacing.sm) {
            Text(syncLabel)
                .font(LCTypo.micro())
                .foregroundStyle(LCPalette.muted)
                .lineLimit(1)

            Text("·").foregroundStyle(LCPalette.muted.opacity(0.5))

            Text(L10n.onlineLamps(onlineCount))
                .font(LCTypo.micro())
                .foregroundStyle(LCPalette.muted)

            Spacer(minLength: LCSpacing.xs)

            Button { Task { await appState.syncLamps() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LCPalette.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .rotationEffect(.degrees(appState.isAutoSyncing ? 360 : 0))
                    .animation(appState.isAutoSyncing ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default, value: appState.isAutoSyncing)
            }
            .buttonStyle(LCPressableButtonStyle())
            .disabled(appState.isBusy || !appState.canSync)
            .opacity(appState.isBusy || !appState.canSync ? 0.45 : 1)
            .help("lamps.sync.now")
        }
        .padding(.horizontal, LCSpacing.xxs)
        .frame(height: 24)
    }

    private var syncLabel: String {
        if appState.isAutoSyncing { return L10n.syncUpdating }
        guard let d = appState.lastSyncDate else { return L10n.syncAuto }
        return L10n.syncTime(d.formatted(date: .omitted, time: .shortened))
    }
}
