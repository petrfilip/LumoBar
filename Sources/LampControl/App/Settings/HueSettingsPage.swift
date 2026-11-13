import AppKit
import SwiftUI

extension SettingsView {
    var hueBridgeIP: Binding<String> {
        Binding(get: { hueBridgeIPDraft ?? appState.hueSettings.bridgeIP }, set: { hueBridgeIPDraft = $0 })
    }

    var hueBridgeID: String { hueBridgeIDDraft ?? appState.hueSettings.bridgeID }

    var hueSettings: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: appState.hueSettings.isConfigured ? "checkmark.seal.fill" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appState.hueSettings.isConfigured ? Color.green : accent)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: appState.hueSettings.isConfigured ? Color.green.opacity(0.10) : Color.blue.opacity(0.08))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.hueSettings.isConfigured ? "hue.connected" : "hue.connect")
                            .font(.system(size: 13, weight: .semibold))
                        Group {
                            if appState.hueSettings.bridgeIP.isEmpty {
                                Text("hue.bridge.detect.hint")
                            } else {
                                Text(verbatim: appState.hueSettings.bridgeIP)
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(muted)
                    }

                    Spacer()
                }

                Button {
                    Task { await appState.discoverHueBridges() }
                } label: {
                    Label("hue.bridge.detect.button", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy)
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)

            if !appState.discoveredHueBridges.isEmpty {
                VStack(spacing: 8) {
                    ForEach(appState.discoveredHueBridges) { bridge in
                        Button {
                            hueBridgeIDDraft = bridge.id
                            hueBridgeIPDraft = bridge.internalipaddress
                            appState.message = L10n.hueBridgeSelected
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: hueBridgeID == bridge.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(hueBridgeID == bridge.id ? Color.green : muted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bridge.id)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    Text(bridge.displayAddress)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(muted)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .liquidGlassSurface(radius: 14, interactive: true)
                    }
                }
                .padding(12)
                .liquidGlassSurface(radius: 22)
            }

            VStack(alignment: .leading, spacing: 10) {
                formField("hue.bridge.ip", text: hueBridgeIP, icon: "network")

                Button {
                    Task {
                        if await appState.pairHueBridge(bridgeID: hueBridgeID, bridgeIP: hueBridgeIP.wrappedValue) {
                            hueBridgeIPDraft = nil
                            hueBridgeIDDraft = nil
                        }
                    }
                } label: {
                    Label(appState.hueSettings.isConfigured ? "hue.reconnect" : "hue.connect.button", systemImage: "link")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || hueBridgeIP.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if appState.hueSettings.isConfigured { disconnectButton(.philipsHue) }

                hint("hue.hint")
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)
        }
    }
}
