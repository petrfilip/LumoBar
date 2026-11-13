import AppKit
import SwiftUI

extension SettingsView {
    var goveeKey: Binding<String> {
        Binding(get: { goveeKeyDraft ?? appState.goveeSettings.apiKey }, set: { goveeKeyDraft = $0 })
    }

    var goveeSettings: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: appState.goveeSettings.isConfigured ? "checkmark.seal.fill" : "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appState.goveeSettings.isConfigured ? Color.green : accent)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: appState.goveeSettings.isConfigured ? Color.green.opacity(0.10) : Color.purple.opacity(0.08))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.goveeSettings.isConfigured ? "govee.connected" : "govee.connect")
                            .font(.system(size: 13, weight: .semibold))
                        Text("govee.hint")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                    }

                    Spacer()
                }

                SecureField(appState.goveeSettings.isConfigured ? "govee.apikey.saved" : "govee.apikey.placeholder", text: goveeKey)
                    .textFieldStyle(.plain)
                    .foregroundStyle(ink)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)

                Button {
                    Task {
                        if await appState.saveGoveeSettingsAndSync(apiKey: goveeKey.wrappedValue) { goveeKeyDraft = nil }
                    }
                } label: {
                    Label("govee.save", systemImage: "bolt.badge.checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || goveeKey.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if appState.goveeSettings.isConfigured { disconnectButton(.govee) }

                hint("govee.apikey.hint")
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)
        }
    }
}
