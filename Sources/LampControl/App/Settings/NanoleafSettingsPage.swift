import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Nanoleaf Settings

    var nanoleafSettings: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: appState.nanoleafSettings.isConfigured ? "checkmark.seal.fill" : "triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appState.nanoleafSettings.isConfigured ? Color.green : Color.orange)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: appState.nanoleafSettings.isConfigured ? Color.green.opacity(0.10) : Color.orange.opacity(0.08))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.nanoleafSettings.isConfigured
                             ? L10n.nanoleafConnected(appState.nanoleafSettings.devices.count)
                             : NSLocalizedString("nanoleaf.connect", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                        Text("nanoleaf.hint")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                formField("nanoleaf.ip.placeholder", text: $newNanoleafHost, icon: "network")
                formField("device.name.placeholder", text: $newNanoleafName, icon: "tag")

                Button {
                    Task {
                        // Keep what was typed when the add failed so it can be corrected.
                        if await appState.addNanoleafDevice(host: newNanoleafHost, name: newNanoleafName) {
                            newNanoleafHost = ""
                            newNanoleafName = ""
                        }
                    }
                } label: {
                    Label("nanoleaf.pair.button", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || newNanoleafHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                hint("nanoleaf.ip.hint")
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)

            if !appState.nanoleafSettings.devices.isEmpty {
                VStack(spacing: 8) {
                    ForEach(appState.nanoleafSettings.devices) { device in
                        HStack(spacing: 10) {
                            Image(systemName: "triangle.fill")
                                .foregroundStyle(Color.orange)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text("\(device.host):\(device.port)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(muted)
                            }
                            Spacer()
                            Button {
                                Task { await appState.removeNanoleafDevice(device) }
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
