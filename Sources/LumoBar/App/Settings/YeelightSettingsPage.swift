import AppKit
import SwiftUI

extension SettingsView {
    var yeelightSettings: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: appState.yeelightSettings.isConfigured ? "checkmark.seal.fill" : "wifi")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appState.yeelightSettings.isConfigured ? Color.green : accent)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: appState.yeelightSettings.isConfigured ? Color.green.opacity(0.10) : Color.orange.opacity(0.08))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.yeelightSettings.isConfigured
                             ? L10n.yeeConnected(appState.yeelightSettings.bulbs.count)
                             : NSLocalizedString("yeelight.connect", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                        Text("yeelight.hint")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                    }

                    Spacer()
                }

                Button {
                    Task { await appState.searchYeelightBulbs() }
                } label: {
                    Label(
                        NSLocalizedString(appState.isSearchingYeelight ? "yeelight.search.searching" : "yeelight.search.button", comment: ""),
                        systemImage: "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || appState.isSearchingYeelight)
                .help("yeelight.search.help")

                if appState.yeelightSearchCompleted && appState.discoveredYeelightBulbs.isEmpty {
                    hint("yeelight.search.none")
                }

                formField("yeelight.ip.placeholder", text: $newYeelightHost, icon: "network")
                formField("device.name.placeholder", text: $newYeelightName, icon: "tag")

                Button {
                    Task {
                        // Keep what was typed when the add was rejected so it can be corrected.
                        if await appState.addYeelightBulb(host: newYeelightHost, name: newYeelightName) {
                            newYeelightHost = ""
                            newYeelightName = ""
                        }
                    }
                } label: {
                    Label("device.add.sync", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || newYeelightHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                hint("yeelight.ip.hint")
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)

            if !appState.discoveredYeelightBulbs.isEmpty {
                VStack(spacing: 8) {
                    ForEach(appState.discoveredYeelightBulbs) { found in
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb")
                                .foregroundStyle(accent)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(found.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(found.model.isEmpty ? found.address : "\(found.model) · \(found.address)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(muted)
                            }
                            Spacer()
                            if appState.isYeelightBulbAdded(found) {
                                Label("yeelight.search.added", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.green)
                            } else {
                                Button {
                                    Task { await appState.addDiscoveredYeelightBulb(found) }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(accent)
                                        .frame(width: 28, height: 28)
                                }
                                .liquidGlassButtonStyle()
                                .help("yeelight.search.add.help")
                                .disabled(appState.isBusy)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .liquidGlassSurface(radius: 14)
                    }
                }
                .padding(12)
                .liquidGlassSurface(radius: 22)
            }

            if !appState.yeelightSettings.bulbs.isEmpty {
                VStack(spacing: 8) {
                    ForEach(appState.yeelightSettings.bulbs) { bulb in
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb")
                                .foregroundStyle(accent)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bulb.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text("\(bulb.host):\(bulb.port)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(muted)
                            }
                            Spacer()
                            Button {
                                Task { await appState.removeYeelightBulb(bulb) }
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
