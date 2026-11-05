import SwiftUI
import AppKit

struct LampsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draggedLampID: String?
    @State private var expandedRoomIds: Set<String> = []
    private let ink = LCTheme.ink
    private let muted = LCTheme.muted
    private let accent = LCTheme.accent

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
    }

    private var scrollableContent: some View {
        VStack(spacing: LCSpacing.sm) {
            statusBar

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
            } else if appState.visibleLamps.isEmpty && !appState.lamps.isEmpty {
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

            if appState.hiddenLampCount > 0 {
                premiumLimitCard
            }

            LazyVStack(spacing: 8) {
                // Group lamps by room
                let rooms = appState.rooms
                

                ForEach(rooms) { room in
                    let roomLamps = appState.visibleLamps.filter { room.lampIds.contains($0.id) }
                    if !roomLamps.isEmpty {
                        VStack(spacing: LCSpacing.xs) {
                            HStack(spacing: LCSpacing.xs) {
                                Button {
                                    if expandedRoomIds.contains(room.id) { expandedRoomIds.remove(room.id) } else { expandedRoomIds.insert(room.id) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: expandedRoomIds.contains(room.id) ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(muted)
                                            .frame(width: 12)
                                        Text(room.name.uppercased())
                                            .font(LCTypo.sectionHeader())
                                            .tracking(0.6)
                                            .foregroundStyle(muted)
                                            .lineLimit(1)
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
                            }
                            .padding(.horizontal, LCSpacing.xs)
                            .padding(.top, LCSpacing.sm)
                            .padding(.bottom, LCSpacing.xxs)

                            if expandedRoomIds.contains(room.id) {
                                ForEach(roomLamps) { lamp in
                                    LampRow(lamp: lamp)
                                        .opacity(draggedLampID == lamp.id ? 0.72 : 1)
                                        .onDrag {
                                            draggedLampID = lamp.id
                                            return NSItemProvider(object: lamp.id as NSString)
                                        }
                                        .onDrop(of: [.text], delegate: LampReorderDropDelegate(
                                            targetLamp: lamp,
                                            draggedLampID: $draggedLampID,
                                            appState: appState,
                                            canReorder: canReorderLamps
                                        ))
                                }
                            }
                        }
                    }
                }

                // Unassigned lamps
                let unassigned = appState.visibleLamps.filter { appState.roomForLamp($0.id) == nil }
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
                            LampRow(lamp: lamp)
                                .opacity(draggedLampID == lamp.id ? 0.72 : 1)
                                .onDrag {
                                    draggedLampID = lamp.id
                                    return NSItemProvider(object: lamp.id as NSString)
                                }
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

    private var statusBar: some View {
        HStack(spacing: LCSpacing.sm) {
            Text(syncLabel)
                .font(LCTypo.micro())
                .foregroundStyle(LCPalette.muted)
                .lineLimit(1)

            Text("·").foregroundStyle(LCPalette.muted.opacity(0.5))

            Text(L10n.onlineLamps(appState.visibleLamps.filter(\.online).count))
                .font(LCTypo.micro())
                .foregroundStyle(LCPalette.muted)

            Spacer(minLength: LCSpacing.xs)

            Button { Task { await appState.syncLamps() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appState.isAutoSyncing ? LCPalette.muted : LCPalette.muted)
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

    private var premiumLimitCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .liquidGlassSurface(radius: 10, tint: Color.yellow.opacity(0.10))

            Text(L10n.hiddenLamps(appState.hiddenLampCount))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(muted)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlassSurface(radius: 16, tint: Color.yellow.opacity(0.08))
    }

    private var syncLabel: String {
        if appState.isAutoSyncing { return L10n.syncUpdating }
        guard let d = appState.lastSyncDate else { return L10n.syncAuto }
        return L10n.syncTime(d.formatted(date: .omitted, time: .shortened))
    }
}

private struct ScenePresetBar: View {
    @EnvironmentObject private var appState: AppState
    @State private var isEditing = false
    @State private var editingId: UUID?
    @State private var draftTitle = ""
    @State private var draftIcon = "paintpalette.fill"
    @State private var draftColor = HSVColor.warm
    @State private var captureMode = false

    private let iconChoices = [
        "paintpalette.fill", "sparkles", "moon.fill", "sun.max.fill",
        "flame.fill", "leaf.fill", "bed.double.fill", "square.stack.3d.up.fill",
        "briefcase.fill", "film.fill", "gamecontroller.fill", "house.fill"
    ]

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    // Built-in presets are regular scenes now (seeded first in the list),
                    // so they get the same Edit / Delete menu as the user's own.
                    ForEach(appState.userScenes) { scene in
                        // No dimming while busy: every click dimmed and restored all
                        // chips, which read as flicker.
                        Button { Task { await appState.applyScene(scene, byUser: true) } } label: {
                            SceneChip(title: scene.title, icon: scene.icon, color: scene.color, isCapture: scene.isCapture)
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isBusy)
                        .help(scene.isCapture ? L10n.sceneApplyCapture(scene.title)
                              : scene.presetId != nil ? L10n.sceneApplyPreset(scene.title)
                              : L10n.sceneApplyAmbiance(scene.title))
                        .contextMenu {
                            Button("lamps.scene.edit") { beginEditing(scene) }
                            Button("lamps.scene.delete", role: .destructive) { appState.deleteUserScene(scene) }
                        }
                    }

                    Button { beginCreating() } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("lamps.scene.button")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(LCTheme.accent)
                        .frame(width: 56).frame(height: 52)
                        .liquidGlassSurface(radius: 15, tint: LCTheme.accent.opacity(0.10), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)

            if isEditing {
                sceneEditor.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .liquidGlassSurface(radius: 18)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isEditing)
    }

    // MARK: - Editor

    private var sceneEditor: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("lamps.scene.name.placeholder", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .liquidGlassSurface(radius: 12, tint: Color.white.opacity(0.06), interactive: true)

                Picker("", selection: $draftIcon) {
                    ForEach(iconChoices, id: \.self) { Image(systemName: $0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
                .frame(width: 48, height: 32)
                .liquidGlassSurface(radius: 12, tint: Color.white.opacity(0.06))
            }

            if editingId == nil {
                HStack(spacing: 0) {
                    modeButton(label: "lamps.color.mode",   icon: "paintpalette.fill", selected: !captureMode) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) { captureMode = false }
                    }
                    modeButton(label: "lamps.capture.mode", icon: "square.stack.3d.up.fill", selected: captureMode) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) { captureMode = true }
                    }
                }
                .padding(3)
                .liquidGlassSurface(radius: 14)
            }

            if captureMode {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LCTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.captureState(appState.lamps.count))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LCTheme.ink)
                        Text("lamps.capture.state.detail")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(LCTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(10)
                .liquidGlassSurface(radius: 12, tint: LCTheme.accent.opacity(0.06))
            } else {
                HStack(spacing: 8) {
                    ColorSpectrumPicker(color: Binding(
                        get: { draftColor },
                        set: { draftColor = $0.withValue(draftColor.v) }
                    ))
                    .frame(height: 50)

                    VStack(spacing: 6) {
                        confirmButton; cancelButton
                    }
                }
            }

            if captureMode {
                HStack(spacing: 8) { confirmButton; cancelButton }
            }
        }
        .padding(10)
        .liquidGlassSurface(radius: 16, tint: Color.white.opacity(0.05))
    }

    private var confirmButton: some View {
        Button {
            let snapshots: [LampSnapshot]? = captureMode ? appState.captureCurrentState() : nil
            appState.saveUserScene(id: editingId, title: draftTitle, icon: draftIcon, color: draftColor, snapshots: snapshots)
            isEditing = false
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: captureMode ? 36 : 24)
                .contentShape(Rectangle())
        }
        .liquidGlassButtonStyle(prominent: true)
        .help("help.scene.save")
    }

    private var cancelButton: some View {
        Button { isEditing = false } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                // Was muted grey, which read as a disabled button.
                .foregroundStyle(LCPalette.ink)
                .frame(width: 34, height: captureMode ? 36 : 24)
                .contentShape(Rectangle())
        }
        .liquidGlassButtonStyle()
        .help("help.scene.cancel")
        .keyboardShortcut(.cancelAction)
    }

    private func modeButton(label: LocalizedStringKey, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? .white : LCTheme.muted)
            .frame(maxWidth: .infinity).frame(height: 28)
            .liquidGlassSurface(radius: 11, tint: selected ? LCTheme.accent.opacity(0.55) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func beginCreating() {
        editingId = nil; draftTitle = ""; draftIcon = "paintpalette.fill"
        draftColor = appState.groupColor; captureMode = false; isEditing = true
    }

    private func beginEditing(_ scene: UserLightScene) {
        editingId = scene.id; draftTitle = scene.title; draftIcon = scene.icon
        draftColor = scene.color; captureMode = scene.isCapture; isEditing = true
    }
}

private struct SceneChip: View {
    let title: String
    let icon: String
    let color: HSVColor
    var isCapture: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCapture ? LCTheme.accent : Color(hsv: color))
                    .frame(height: 13)
                if isCapture {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(LCTheme.accent)
                        .offset(x: 8, y: -4)
                }
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LCTheme.ink)
                .lineLimit(1)
        }
        .frame(width: 62)
        .frame(height: 52)
        .liquidGlassSurface(radius: 15, tint: (isCapture ? LCTheme.accent : Color(hsv: color)).opacity(0.10), interactive: true)
        .shadow(color: Color.black.opacity(0.10), radius: 4, y: 2)
    }
}

private struct GroupControlEntry: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.isGroupPanelExpanded || appState.selectedLampIds.count >= 2 {
            GroupControlPanel()
        } else {
            GroupCompactBar()
        }
    }
}

private struct GroupCompactBar: View {
    @EnvironmentObject private var appState: AppState
    private let muted = LCTheme.muted
    private let accent = LCTheme.accent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .liquidGlassSurface(radius: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text("lamps.group.title")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LCTheme.ink)
                Text(appState.selectedLampIds.isEmpty
                     ? NSLocalizedString("lamps.group.select.hint", comment: "")
                     : L10n.groupSelected(appState.selectedLampIds.count))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(muted)
            }

            Spacer()

            Button {
                appState.selectAllRGBLamps()
            } label: {
                Label("RGB", systemImage: "circle.hexagongrid.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .liquidGlassSurface(radius: 14, interactive: true)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                    appState.toggleGroupPanel()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(muted)
                    .frame(width: 30, height: 30)
                    .liquidGlassCircle(interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlassSurface(radius: 18)
    }
}

private struct GroupControlPanel: View {
    @EnvironmentObject private var appState: AppState
    private let ink = LCTheme.ink
    private let muted = LCTheme.muted
    private let accent = LCTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    ColorSwatch(color: appState.groupColor, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("lamps.group.scene.title")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ink)
                        Text(L10n.groupSelected(appState.selectedLampIds.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                    }
                }

                Spacer()

                Button {
                    appState.selectAllRGBLamps()
                } label: {
                    Text("RGB")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .liquidGlassSurface(radius: 13, interactive: true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)

                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        appState.isGroupPanelExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .liquidGlassCircle(interactive: true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(muted)
            }

            if appState.selectedLampIds.count < 2 {
                Text("lamps.group.scene.hint")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await appState.applyGroupColor() }
                } label: {
                    Label("lamps.apply.color", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .liquidGlassButtonStyle(prominent: true)
                .tint(accent)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(height: 36)
                .disabled(appState.selectedLampIds.isEmpty || appState.isBusy)
                .opacity(appState.selectedLampIds.isEmpty || appState.isBusy ? 0.5 : 1)

                Button {
                    Task { await appState.applyGroupPower(false) }
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .liquidGlassSurface(radius: 14, interactive: true)
                }
                .buttonStyle(.plain)
                .help("help.group.off")
                .foregroundStyle(muted)
                .disabled(appState.selectedLampIds.isEmpty || appState.isBusy)
            }

            ColorSpectrumPicker(color: Binding(
                get: { appState.groupColor },
                set: { appState.groupColor = $0.vivid() }
            ))
            .frame(height: 82)
            .opacity(appState.selectedLampIds.count >= 2 ? 1 : 0.42)
            .disabled(appState.selectedLampIds.count < 2)
        }
        .padding(14)
        .liquidGlassSurface(radius: 22)
    }
}

private struct LampRow: View {
    @EnvironmentObject private var appState: AppState
    let lamp: LampDevice
    @State private var showingFeedback = false

    private let ink = LCTheme.ink
    private let muted = LCTheme.muted
    private let accent = LCTheme.accent

    var body: some View {
        VStack(spacing: showsAdvancedControls ? 10 : 0) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        let success = await appState.toggle(lamp)
                        guard success else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingFeedback = true
                        }
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingFeedback = false
                        }
                    }
                } label: {
                    ZStack {
                        rowSummary
                        if showingFeedback {
                            VStack(spacing: 9) {
                                Spacer()
                                HStack(spacing: 9) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.green)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 9)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!lamp.online)
                .opacity(lamp.online ? 1 : 0.52)
                .help("lamps.toggle.power")

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        appState.toggleAdvancedControls(for: lamp)
                    }
                } label: {
                    Image(systemName: showsAdvancedControls ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(muted)
                        .frame(width: 30, height: 30)
                        .liquidGlassCircle(interactive: true)
                }
                .buttonStyle(.plain)
                .help(showsAdvancedControls ? "lamps.hide.options" : "lamps.show.options")
            }

            if showsAdvancedControls {
                advancedControls
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, LCSpacing.sm)
        .padding(.vertical, showsAdvancedControls ? LCSpacing.sm : LCSpacing.xs + 2)
        .background(alignment: .top) {
            if lamp.power {
                Rectangle()
                    .fill(displayColor ?? Color(red: 0.96, green: 0.77, blue: 0.26))
                    .frame(height: 2)
                    .clipShape(Capsule())
                    .shadow(color: (displayColor ?? Color.orange).opacity(0.55), radius: 4, y: 0)
                    .padding(.horizontal, LCSpacing.md)
            }
        }
        .lcCard(radius: LCRadius.card, tint: lamp.power ? Color.white.opacity(0.10) : nil)
        .overlay(
            RoundedRectangle(cornerRadius: LCRadius.card, style: .continuous)
                .strokeBorder(
                    appState.selectedLampIds.contains(lamp.id)
                        ? LCPalette.accent.opacity(0.85)
                        : Color.clear,
                    lineWidth: appState.selectedLampIds.contains(lamp.id) ? 1.5 : 0
                )
        )
        .animation(LCAnimation.standard, value: showsAdvancedControls)
    }

    private var showsAdvancedControls: Bool {
        appState.isAdvancedControlsExpanded(for: lamp)
    }

    private var rowSummary: some View {
        HStack(spacing: LCSpacing.sm) {
            ZStack {
                Image(systemName: lamp.power ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(lamp.power ? Color(red: 0.98, green: 0.72, blue: 0.20) : muted.opacity(0.70))
                    .lcBounceSymbol(value: lamp.power)
            }
            .frame(width: 32, height: 32)
            .lcCard(radius: 16, tint: lamp.power ? Color.yellow.opacity(0.18) : Color.white.opacity(0.05))

            VStack(alignment: .leading, spacing: 2) {
                Text(lamp.name)
                    .font(LCTypo.bodySemibold())
                    .foregroundStyle(ink)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    LCStatusDot(
                        color: lamp.online
                            ? (lamp.power ? Color.blue : LCPalette.muted)
                            : LCPalette.danger,
                        animated: false
                    )
                    .frame(width: 8, height: 8)
                    Text(compactStatus)
                        .font(LCTypo.micro())
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: LCSpacing.xs)

            if lamp.capabilities.colorCode != nil, let color = displayColor {
                ColorSwatch(fill: color, size: 20)
            }

            if let brightness = brightnessCapability {
                Text("\(brightnessPercentage(for: brightness))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(lamp.power ? ink : muted)
                    .frame(width: 40, alignment: .trailing)
            } else if let temperature = temperatureCapability {
                Text("\(temperaturePercentage(for: temperature))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(lamp.power ? ink : muted)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var advancedControls: some View {
        VStack(spacing: 9) {
            if appState.showsGroupControls {
                HStack(spacing: 8) {
                    Button {
                        appState.toggleSelection(lamp)
                    } label: {
                        Label(
                            appState.selectedLampIds.contains(lamp.id)
                                ? NSLocalizedString("lamps.in.group", comment: "")
                                : NSLocalizedString("lamps.add.to.group", comment: ""),
                            systemImage: appState.selectedLampIds.contains(lamp.id) ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appState.selectedLampIds.contains(lamp.id) ? accent : muted)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .liquidGlassSurface(radius: 14, interactive: true)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }

            if let brightness = brightnessCapability {
                HStack(spacing: 9) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(muted)
                        .frame(width: 14)
                        .help("help.brightness")

                    Slider(
                        value: Binding(
                            get: { Double(brightnessValue(for: brightness)) },
                            set: { appState.previewBrightness(lamp, value: Int($0)) }
                        ),
                        in: Double(brightness.min)...Double(brightness.max),
                        step: Double(brightness.step),
                        onEditingChanged: { editing in
                            if editing { appState.beginAdjusting(lamp); return }
                            Task { await appState.commitBrightness(lamp, value: brightnessValue(for: brightness)) }
                        }
                    )
                    .tint(Color(red: 0.96, green: 0.77, blue: 0.26))
                    .disabled(!lamp.online)

                    Text("\(brightnessPercentage(for: brightness))%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(muted)
                        .frame(width: 32, alignment: .trailing)
                }
            }

            if let temperature = temperatureCapability {
                HStack(spacing: 9) {
                    Image(systemName: "thermometer.sun")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(muted)
                        .frame(width: 14)
                        .help("help.temperature")

                    Slider(
                        value: Binding(
                            get: { Double(temperatureValue(for: temperature)) },
                            set: { appState.previewTemperature(lamp, value: Int($0)) }
                        ),
                        in: Double(temperature.min)...Double(temperature.max),
                        step: Double(temperature.step),
                        onEditingChanged: { editing in
                            if editing { appState.beginAdjusting(lamp); return }
                            Task { await appState.commitTemperature(lamp, value: temperatureValue(for: temperature)) }
                        }
                    )
                    .disabled(!lamp.online)

                    Text(temperatureLabel(for: temperature))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(muted)
                        .frame(width: 58, alignment: .trailing)
                }
            }

            if lamp.capabilities.colorCode != nil {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(width: 14)
                            .help("help.color")

                        ColorSwatch(fill: displayColor ?? Color(hsv: .warm), size: 22)

                        Spacer()

                        ForEach(HSVColor.quickColors, id: \.self) { color in
                            Button {
                                let hsv = color.withValue(currentColorValue)
                                appState.previewColor(lamp, color: hsv)
                                Task { await appState.commitColor(lamp, color: hsv) }
                            } label: {
                                Circle()
                                    .fill(Color(hsv: color))
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 0.8))
                                    .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.5))
                                    .overlay(
                                        Circle()
                                            .stroke(accent, lineWidth: 1.5)
                                            .frame(width: 22, height: 22)
                                            .opacity(isSelectedQuickColor(color) ? 1 : 0)
                                    )
                                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!lamp.online)
                            .help(L10n.quickColorName(color))
                        }
                    }

                    ColorSpectrumPicker(showsThumb: !lamp.isWhiteMode, color: Binding(
                        get: { lamp.color ?? .warm },
                        set: { newColor in
                            let hsv = newColor.withValue(currentColorValue)
                            appState.previewColor(lamp, color: hsv)
                        }
                    ), onBegin: {
                        appState.beginAdjusting(lamp)
                    }, onCommit: { finalColor in
                        let hsv = finalColor.withValue(currentColorValue)
                        Task { await appState.commitColor(lamp, color: hsv) }
                    })
                    .frame(height: 62)
                    .disabled(!lamp.online)
                    .opacity(lamp.online ? 1 : 0.45)
                }
            }
        }
    }

    /// What the lamp is emitting, for swatches and the glow line. In white mode this is the
    /// tint of the color temperature — never the stale hue/saturation the bulb still reports.
    private var displayColor: Color? {
        if lamp.isWhiteMode {
            guard let temperature = lamp.temperature, let capability = lamp.capabilities.temperature else { return nil }
            let kelvin = LampScale.kelvin(native: temperature, capability: capability)
            return Color(nsColor: StatusItemIcon.kelvinColor(kelvin))
        }
        return lamp.color.map { Color(hsv: $0) }
    }

    /// Only "white" has a persistent identity: it is a mode (color temperature), whereas
    /// the other quick colors are just presets of the color picker.
    private func isSelectedQuickColor(_ color: HSVColor) -> Bool {
        color == .white && lamp.isWhiteMode
    }

    private var compactStatus: String {
        if !lamp.online { return L10n.statusOffline }
        return lamp.power ? L10n.statusOn : L10n.statusOff
    }

    private var brightnessCapability: NumericCapability? {
        if let brightness = lamp.capabilities.brightness {
            return brightness
        }
        if lamp.capabilities.colorCode != nil {
            return NumericCapability(code: "colour_value", min: 10, max: 1000, step: 1)
        }
        return nil
    }

    private var temperatureCapability: NumericCapability? {
        lamp.capabilities.temperature
    }

    private func brightnessValue(for capability: NumericCapability) -> Int {
        if lamp.capabilities.brightness != nil {
            return min(capability.max, max(capability.min, lamp.brightness ?? capability.min))
        }
        if lamp.capabilities.colorCode != nil {
            return min(capability.max, max(capability.min, lamp.color?.v ?? HSVColor.defaultColorValue))
        }
        return capability.min
    }

    private func brightnessPercentage(for capability: NumericCapability) -> Int {
        Int(round(Double(brightnessValue(for: capability)) / Double(capability.max) * 100))
    }

    private func temperatureValue(for capability: NumericCapability) -> Int {
        min(capability.max, max(capability.min, lamp.temperature ?? capability.min))
    }

    private func temperaturePercentage(for capability: NumericCapability) -> Int {
        let range = max(1, capability.max - capability.min)
        return Int(round(Double(temperatureValue(for: capability) - capability.min) / Double(range) * 100))
    }

    private func temperatureLabel(for capability: NumericCapability) -> String {
        let kelvin = temperatureKelvin(for: capability)
        return "\(kelvin)K"
    }

    private func temperatureKelvin(for capability: NumericCapability) -> Int {
        let tempValue = temperatureValue(for: capability)
        // Ranges starting at 1000+ are already Kelvin (Yeelight 1700–6500 K, LIFX, …).
        if capability.min >= 1000 { return tempValue }
        // Otherwise map the vendor scale onto 2700–6500 K as a reasonable default.
        let minValue = capability.min
        let maxValue = capability.max
        let range = max(1, maxValue - minValue)
        let normalized = Double(tempValue - minValue) / Double(range)
        let kelvin = Int(round(2700.0 + normalized * (6500.0 - 2700.0)))
        return kelvin
    }

    private var currentColorValue: Int {
        if let colorValue = lamp.color?.v {
            return min(1000, max(10, colorValue))
        }
        if let brightness = lamp.capabilities.brightness, let value = lamp.brightness {
            let range = max(1, brightness.max - brightness.min)
            let normalized = Double(value - brightness.min) / Double(range)
            return min(1000, max(10, Int(round(normalized * 1000.0))))
        }
        return HSVColor.defaultColorValue
    }
}

private struct LampReorderDropDelegate: DropDelegate {
    let targetLamp: LampDevice
    @Binding var draggedLampID: String?
    let appState: AppState
    let canReorder: Bool

    func dropEntered(info: DropInfo) {
        guard canReorder,
              let draggedLampID,
              draggedLampID != targetLamp.id
        else { return }

        var updatedOrder = appState.lampOrderIds
        if updatedOrder.isEmpty {
            updatedOrder = appState.lamps.map(\.id)
        }

        guard let movingIndex = updatedOrder.firstIndex(of: draggedLampID),
              let dropIndex = updatedOrder.firstIndex(of: targetLamp.id) else { return }

        let item = updatedOrder.remove(at: movingIndex)
        let destination = movingIndex < dropIndex ? dropIndex - 1 : dropIndex
        updatedOrder.insert(item, at: max(0, destination))
        appState.updateLampOrder(updatedOrder)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedLampID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if draggedLampID == targetLamp.id {
            draggedLampID = nil
        }
    }
}

extension HSVColor {
    static let quickColors: [HSVColor] = [
        HSVColor.white,
        HSVColor(h: 0, s: 900, v: 1000),
        HSVColor(h: 38, s: 850, v: 1000),
        HSVColor(h: 120, s: 850, v: 850),
        HSVColor(h: 205, s: 900, v: 1000),
        HSVColor(h: 278, s: 760, v: 950)
    ]

    init(color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        let hue = Int(round(nsColor.hueComponent * 360.0))
        let saturation = Int(round(nsColor.saturationComponent * 1000.0))
        self.init(h: hue, s: saturation, v: HSVColor.defaultColorValue)
    }
}

extension Color {
    init(hsv: HSVColor) {
        self.init(
            hue: Double(hsv.h) / 360.0,
            saturation: Double(hsv.s) / 1000.0,
            brightness: Double(hsv.v) / 1000.0
        )
    }
}

private struct ColorSwatch: View {
    let fill: Color
    var size: CGFloat = 24

    init(color: HSVColor, size: CGFloat = 24) {
        self.fill = Color(hsv: color)
        self.size = size
    }

    init(fill: Color, size: CGFloat = 24) {
        self.fill = fill
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 2)
    }
}

private struct ColorSpectrumPicker: View {
    /// Hidden while the lamp is in white mode: the stored hue/saturation is not what the
    /// lamp shows, so a thumb on it would look like a color is selected.
    var showsThumb = true
    @Binding var color: HSVColor
    var onBegin: (() -> Void)? = nil
    var onCommit: ((HSVColor) -> Void)? = nil
    /// The thumb follows the pointer through this local value while dragging instead of
    /// round-tripping through the store, so nothing a bulb pushes back can make it jump.
    @State private var dragColor: HSVColor?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let shown = dragColor ?? color
            let x = CGFloat(shown.h) / 360.0 * size.width
            let y = CGFloat(shown.s) / 1000.0 * size.height

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .overlay(
                    LinearGradient(
                        colors: [.white, .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )

                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color(hsv: shown)))
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.black.opacity(0.22), radius: 5, x: 0, y: 2)
                    .offset(x: min(max(0, x), size.width) - 9, y: min(max(0, y), size.height) - 9)
                    .opacity(showsThumb ? 1 : 0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let picked = color(at: value.location, in: size)
                        if dragColor == nil { onBegin?() }
                        dragColor = picked
                        color = picked
                    }
                    .onEnded { value in
                        let finalColor = color(at: value.location, in: size)
                        color = finalColor
                        dragColor = nil
                        onCommit?(finalColor)
                    }
            )
        }
    }

    private func color(at point: CGPoint, in size: CGSize) -> HSVColor {
        guard size.width > 0, size.height > 0 else { return color }
        let clampedX = min(max(0, point.x), size.width)
        let clampedY = min(max(0, point.y), size.height)
        return HSVColor(
            h: Int(round(clampedX / size.width * 360.0)),
            s: Int(round(clampedY / size.height * 1000.0)),
            v: HSVColor.defaultColorValue
        )
    }
}
