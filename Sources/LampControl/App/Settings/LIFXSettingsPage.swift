import AppKit
import SwiftUI

extension SettingsView {
    var lifxToken: Binding<String> {
        Binding(get: { lifxTokenDraft ?? appState.lifxSettings.token }, set: { lifxTokenDraft = $0 })
    }

    var lifxSettings: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: appState.lifxSettings.isConfigured ? "checkmark.seal.fill" : "network")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appState.lifxSettings.isConfigured ? Color.green : accent)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: appState.lifxSettings.isConfigured ? Color.green.opacity(0.10) : Color.blue.opacity(0.08))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.lifxSettings.isConfigured ? "lifx.connected" : "lifx.connect")
                            .font(.system(size: 13, weight: .semibold))
                        Text("lifx.token.hint")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                    }

                    Spacer()
                }

                SecureField(appState.lifxSettings.isConfigured ? "lifx.token.saved" : "lifx.token.placeholder", text: lifxToken)
                    .textFieldStyle(.plain)
                    .foregroundStyle(ink)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)

                Button {
                    Task {
                        if await appState.saveLifxSettingsAndSync(token: lifxToken.wrappedValue) { lifxTokenDraft = nil }
                    }
                } label: {
                    Label("lifx.save", systemImage: "bolt.badge.checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || lifxToken.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if appState.lifxSettings.isConfigured { disconnectButton(.lifx) }

                hint("lifx.hint")
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)
        }
    }
}
