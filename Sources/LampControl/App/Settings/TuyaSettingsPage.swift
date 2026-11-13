import AppKit
import SwiftUI

extension SettingsView {
    /// The Tuya form's values: the draft while editing, else what is saved.
    var tuya: Binding<TuyaSettings> {
        Binding(get: { tuyaDraft ?? appState.settings }, set: { tuyaDraft = $0 })
    }

    var setupSummary: some View {
        VStack(spacing: LCSpacing.sm) {
            HStack(spacing: LCSpacing.sm) {
                Image(systemName: isSetupComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSetupComplete ? LCPalette.success : Color.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isSetupComplete ? "setup.complete" : "setup.incomplete")
                        .font(LCTypo.bodySemibold())
                        .foregroundStyle(LCPalette.ink)
                    Text(isSetupComplete ? "setup.complete.detail" : "setup.incomplete.detail")
                        .font(LCTypo.micro())
                        .foregroundStyle(LCPalette.muted)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(completedSetupCount)/\(setupSteps.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(LCPalette.muted)

                Button(action: appState.openConfigurationGuide) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LCPalette.muted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LCPressableButtonStyle())
                .help("setup.guide")
            }

            HStack(spacing: 4) {
                ForEach(setupSteps) { step in
                    Capsule(style: .continuous)
                        .fill(step.isComplete ? LCPalette.accent : LCPalette.muted.opacity(0.18))
                        .frame(height: 3)
                }
            }
        }
        .padding(.horizontal, LCSpacing.sm)
        .padding(.vertical, LCSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: LCRadius.card, style: .continuous)
                .fill(LCPalette.muted.opacity(0.06))
        )
    }

    var tuyaSettings: some View {
        VStack(spacing: 12) {
            setupSummary

            settingsGroup {
                formField("tuya.access.id", text: tuya.accessId, icon: "key")
                secureField
                settingsPicker
                formField("tuya.endpoint", text: tuya.endpoint, icon: "network")
                formField("tuya.uid", text: tuya.uid, icon: "person.crop.circle")
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        if await appState.saveSettings(tuya.wrappedValue) { tuyaDraft = nil }
                    }
                } label: {
                    Label("tuya.save", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .liquidGlassButtonStyle(prominent: true)
                .tint(accent)
                .disabled(appState.isBusy)
                .opacity(appState.isBusy ? 0.55 : 1)

                Button {
                    Task {
                        if await appState.saveSettingsAndSync(tuya.wrappedValue) { tuyaDraft = nil }
                    }
                } label: {
                    Label("tuya.test", systemImage: "bolt.badge.checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSetupComplete ? Color.white : muted)
                        .frame(width: 108)
                        .frame(height: 38)
                }
                .liquidGlassButtonStyle(prominent: isSetupComplete)
                .tint(accent)
                .disabled(appState.isBusy || !isSetupComplete)
                .opacity(appState.isBusy || !isSetupComplete ? 0.55 : 1)
            }

            if appState.hasSecret { disconnectButton(.tuya) }

            hint("tuya.hint")
        }
    }

    var secureField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("tuya.access.secret", icon: "lock")

            SecureField(appState.hasSecret ? "tuya.secret.placeholder" : "tuya.access.secret", text: tuya.accessSecret)
                .textFieldStyle(.plain)
                .foregroundStyle(ink)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 38)
                .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)
        }
    }

    var settingsPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("tuya.region", icon: "globe.europe.africa")

            Picker("tuya.region", selection: tuya.region) {
                Text("tuya.region.eu").tag(TuyaRegion.eu)
                Text("tuya.region.us").tag(TuyaRegion.us)
                Text("tuya.region.usEast").tag(TuyaRegion.usEast)
                Text("tuya.region.cn").tag(TuyaRegion.cn)
                Text("tuya.region.in").tag(TuyaRegion.in)
                Text("tuya.region.custom").tag(TuyaRegion.custom)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)
            .onChange(of: tuya.wrappedValue.region) { region in
                tuya.wrappedValue.applyEndpoint(for: region)
            }
        }
    }

    var setupSteps: [SetupStep] {
        [
            SetupStep(title: "ID",     icon: "key.fill",              isComplete: !tuya.wrappedValue.accessId.trimmed.isEmpty),
            SetupStep(title: "Secret", icon: "lock.fill",             isComplete: appState.hasSecret || !tuya.wrappedValue.accessSecret.trimmed.isEmpty),
            SetupStep(title: "Region", icon: "globe.europe.africa.fill", isComplete: !tuya.wrappedValue.endpoint.trimmed.isEmpty),
            SetupStep(title: "UID",    icon: "person.fill",           isComplete: !tuya.wrappedValue.uid.trimmed.isEmpty)
        ]
    }

    var completedSetupCount: Int { setupSteps.filter(\.isComplete).count }
    var isSetupComplete: Bool   { completedSetupCount == setupSteps.count }
}

struct SetupStep: Identifiable {
    let title: String
    let icon: String
    let isComplete: Bool
    var id: String { title }
}
