import SwiftUI

struct ScenePresetBar: View {
    @EnvironmentObject private var appState: AppState
    @State private var isEditing = false
    @State private var editingId: UUID?
    @State private var draftTitle = ""
    @State private var draftIcon = "paintpalette.fill"
    @State private var draftColor = HSVColor.warm
    @State private var captureMode = false
    /// Editing a capture scene keeps its stored snapshots unless the user opts in to this.
    @State private var recaptureState = false
    /// Scene waiting for the user to confirm its deletion (inline: alerts do not belong in a popover).
    @State private var pendingDeletion: UserLightScene?

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
                            Button("lamps.scene.delete", role: .destructive) { requestDeletion(of: scene) }
                        }
                    }

                    Button { beginCreating() } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("lamps.scene.button")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(LCPalette.accent)
                        .frame(width: 56).frame(height: 52)
                        .liquidGlassSurface(radius: 15, tint: LCPalette.accent.opacity(0.10), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)

            if let scene = pendingDeletion {
                deletionConfirmation(for: scene).transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isEditing {
                sceneEditor.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .liquidGlassSurface(radius: 18)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isEditing)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: pendingDeletion?.id)
        // A scene removed from elsewhere (or just now) must not stay open in the editor: saving
        // it again would bring it back (for a capture scene, re-capturing the lamps).
        .onReceive(appState.$userScenes) { scenes in
            if let editingId, isEditing, !scenes.contains(where: { $0.id == editingId }) {
                isEditing = false
                self.editingId = nil
            }
            if let pending = pendingDeletion, !scenes.contains(where: { $0.id == pending.id }) {
                pendingDeletion = nil
            }
        }
    }

    // MARK: - Deletion

    /// A captured scene cannot be recreated and a scene that automations use takes them down
    /// with it: those ask first. A plain colour scene is cheap to remake and goes right away.
    private func requestDeletion(of scene: UserLightScene) {
        if scene.isCapture || appState.sceneReferenceCount(scene) > 0 {
            pendingDeletion = scene
        } else {
            delete(scene)
        }
    }

    private func delete(_ scene: UserLightScene) {
        pendingDeletion = nil
        if editingId == scene.id {
            isEditing = false
            editingId = nil
        }
        appState.deleteUserScene(scene)
    }

    private func deletionConfirmation(for scene: UserLightScene) -> some View {
        VStack(spacing: 8) {
            Text(L10n.sceneDeleteConfirm(scene.title, isCapture: scene.isCapture,
                                         isUsed: appState.sceneReferenceCount(scene) > 0))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LCPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { delete(scene) } label: {
                    Text(L10n.sceneDeleteButton)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .contentShape(Rectangle())
                }
                .liquidGlassButtonStyle(prominent: true)
                .tint(.red)

                Button { pendingDeletion = nil } label: {
                    Text(L10n.cancel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LCPalette.ink)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .contentShape(Rectangle())
                }
                .liquidGlassButtonStyle()
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(10)
        .liquidGlassSurface(radius: 16, tint: Color.red.opacity(0.08))
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

                Picker("a11y.scene.icon", selection: $draftIcon) {
                    ForEach(iconChoices, id: \.self) { Image(systemName: $0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
                .help("a11y.scene.icon")
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
                        .foregroundStyle(LCPalette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.captureState(keepsStoredSnapshots ? (editedScene?.snapshots?.count ?? 0) : appState.lamps.count))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LCPalette.ink)
                        Text("lamps.capture.state.detail")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(LCPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(10)
                .liquidGlassSurface(radius: 12, tint: LCPalette.accent.opacity(0.06))

                if editingId != nil {
                    Toggle(isOn: $recaptureState) {
                        Text("lamps.scene.recapture")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LCPalette.ink)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
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
            let snapshots = SceneSnapshotChoice.snapshots(
                captureMode: captureMode,
                existing: editedScene?.snapshots,
                isEditing: editingId != nil,
                recapture: recaptureState,
                capture: { appState.captureCurrentState() })
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
            .foregroundStyle(selected ? .white : LCPalette.muted)
            .frame(maxWidth: .infinity).frame(height: 28)
            .liquidGlassSurface(radius: 11, tint: selected ? LCPalette.accent.opacity(0.55) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var editedScene: UserLightScene? {
        editingId.flatMap { id in appState.userScenes.first { $0.id == id } }
    }

    /// True while editing a capture scene without having asked to re-capture.
    private var keepsStoredSnapshots: Bool {
        editedScene?.snapshots != nil && !recaptureState
    }

    private func beginCreating() {
        editingId = nil; draftTitle = ""; draftIcon = "paintpalette.fill"
        draftColor = appState.groupColor; captureMode = false; recaptureState = false; isEditing = true
    }

    private func beginEditing(_ scene: UserLightScene) {
        editingId = scene.id; draftTitle = scene.title; draftIcon = scene.icon
        draftColor = scene.color; captureMode = scene.isCapture; recaptureState = false; isEditing = true
    }
}

struct SceneChip: View {
    let title: String
    let icon: String
    let color: HSVColor
    var isCapture: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCapture ? LCPalette.accent : Color(hsv: color))
                    .frame(height: 13)
                if isCapture {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(LCPalette.accent)
                        .offset(x: 8, y: -4)
                }
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LCPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 5)
        }
        .frame(width: 62)
        .frame(height: 52)
        .liquidGlassSurface(radius: 15, tint: (isCapture ? LCPalette.accent : Color(hsv: color)).opacity(0.10), interactive: true)
        .shadow(color: Color.black.opacity(0.10), radius: 4, y: 2)
    }
}
