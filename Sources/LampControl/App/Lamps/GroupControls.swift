import SwiftUI

struct GroupControlEntry: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.isGroupPanelExpanded || appState.selectedLampIds.count >= 2 {
            GroupControlPanel()
        } else {
            GroupCompactBar()
        }
    }
}

struct GroupCompactBar: View {
    @EnvironmentObject private var appState: AppState
    private let muted = LCPalette.muted
    private let accent = LCPalette.accent

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
                    .foregroundStyle(LCPalette.ink)
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
            .lcIconLabel("a11y.group.expand")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlassSurface(radius: 18)
    }
}

struct GroupControlPanel: View {
    @EnvironmentObject private var appState: AppState
    private let ink = LCPalette.ink
    private let muted = LCPalette.muted
    private let accent = LCPalette.accent

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
                .lcIconLabel("a11y.group.collapse")
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
