import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - WiZ Settings

    var wizSettings: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: appState.wizSettings.isConfigured ? "checkmark.seal.fill" : "lightbulb.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appState.wizSettings.isConfigured ? Color.green : Color.cyan)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: appState.wizSettings.isConfigured ? Color.green.opacity(0.10) : Color.cyan.opacity(0.08))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.wizSettings.isConfigured
                             ? L10n.wizConnected(appState.wizSettings.devices.count)
                             : NSLocalizedString("wiz.connect", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                        Text("wiz.hint")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                    }
                    Spacer()
                }

                formField("wiz.ip.placeholder", text: $newWizHost, icon: "network")
                formField("device.name.placeholder", text: $newWizName, icon: "tag")

                Button {
                    Task {
                        // Keep what was typed when the add failed so it can be corrected.
                        if await appState.addWizDevice(host: newWizHost, name: newWizName) {
                            newWizHost = ""
                            newWizName = ""
                        }
                    }
                } label: {
                    Label("device.add.sync", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || newWizHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                hint("wiz.ip.hint")
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)

            if !appState.wizSettings.devices.isEmpty {
                VStack(spacing: 8) {
                    ForEach(appState.wizSettings.devices) { device in
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb.2.fill")
                                .foregroundStyle(Color.cyan)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text("\(device.host)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(muted)
                            }
                            Spacer()
                            Button {
                                Task { await appState.removeWizDevice(device) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.red)
                                    .frame(width: 28, height: 28)
                            }
                            .liquidGlassButtonStyle()
                            .help("help.device.remove")
                            .disabled(appState.isBusy)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .liquidGlassSurface(radius: 14)
                    }
                }
                .padding(12)
                .liquidGlassSurface(radius: 22)
            }
        }
    }
}
