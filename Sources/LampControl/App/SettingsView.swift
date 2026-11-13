import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var route: SettingsRoute = .overview
    @State private var newYeelightHost: String = ""
    @State private var newYeelightName: String = ""
    @State private var newNanoleafHost: String = ""
    @State private var newNanoleafName: String = ""
    @State private var newWizHost: String = ""
    @State private var newWizName: String = ""
    @State private var editingAutomation: Automation?
    @State private var isAddingAutomation = false
    @State private var editingRoomId: String?
    @State private var newRoomName: String = ""
    @State private var isCreatingRoom = false
    @State private var editingFocusMappingId: String?
    @State private var newFocusIdentifier: String = ""
    @State private var newFocusSceneId: UUID?
    @State private var isCreatingFocusMapping = false
    @State private var editingKeyframeId: UUID?
    /// Unsaved edits to the adaptive schedule; `nil` = nothing edited.
    @State private var circadianDraft: CircadianSettings?
    @State private var copiedFocusMode: String?

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
        VStack(spacing: 12) {
            settingsNavigationBar

            ScrollView {
                Group {
                    switch route {
                    case .overview:    overview
                    case .providers:   providersSettings
                    case .tuya:        tuyaSettings
                    case .hue:         hueSettings
                    case .lifx:        lifxSettings
                    case .govee:       goveeSettings
                    case .yeelight:    yeelightSettings
                    case .nanoleaf:    nanoleafSettings
                    case .wiz:         wizSettings
                    case .automations: automationsSettings
                    case .focus:       focusSettings
                    case .circadian:   circadianSettings_
                    case .devices:     devicesSettings
                    case .updates:     updatesSettings
                    case .premium:     PremiumSettingsView(licenseState: appState.licenseState)
                    case .about:       aboutSettings
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(ink)
    }

    private var settingsNavigationBar: some View {
        HStack(spacing: LCSpacing.sm) {
            if route != .overview {
                Button {
                    withAnimation(LCAnimation.snap) {
                        route = .overview
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(LCGlassButtonStyle(prominent: false, radius: 16))
                .help("settings.back")
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(route.title)
                    .font(LCTypo.subtitle())
                    .lcTrackedTitle()
                Text(route.subtitle(appState: appState))
                    .font(LCTypo.micro())
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(height: 44)
        .animation(LCAnimation.snap, value: route)
    }

    private var overview: some View {
        VStack(spacing: 12) {
            providersSummary

            VStack(spacing: 8) {
                settingsLink(
                    .providers,
                    icon: "square.grid.2x2",
                    title: NSLocalizedString("route.providers", comment: ""),
                    subtitle: L10n.providersSubtitle(
                        connected: appState.configuredProviderKinds.count,
                        upcoming: LightProviderKind.allCases.count - appState.configuredProviderKinds.count
                    ),
                    tint: Color.cyan.opacity(0.10)
                )

                settingsLink(
                    .automations,
                    icon: "clock.badge.checkmark.fill",
                    title: NSLocalizedString("route.automations", comment: ""),
                    subtitle: appState.automations.isEmpty
                        ? NSLocalizedString("automations.empty", comment: "")
                        : L10n.automationsActive(appState.automations.filter(\.isEnabled).count),
                    tint: Color.green.opacity(0.10)
                )

                settingsLink(
                    .focus,
                    icon: "target",
                    title: L10n.focusTitle,
                    subtitle: L10n.focusSubtitle,
                    tint: Color.indigo.opacity(0.10)
                )

                settingsLink(
                    .circadian,
                    icon: "sun.and.horizon.fill",
                    title: NSLocalizedString("route.circadian", comment: ""),
                    subtitle: appState.circadianSettings.isEnabled
                        ? NSLocalizedString("circadian.subtitle.active", comment: "")
                        : NSLocalizedString("circadian.subtitle.inactive", comment: ""),
                    tint: Color.orange.opacity(0.10)
                )

                settingsLink(
                    .devices,
                    icon: "lightbulb.2",
                    title: NSLocalizedString("route.devices", comment: ""),
                    subtitle: L10n.devicesSubtitle(
                        total: appState.lamps.count,
                        online: appState.lamps.filter(\.online).count
                    ),
                    tint: Color.blue.opacity(0.10)
                )

                restoreScenesRow

                launchAtLoginRow

                settingsLink(
                    .updates,
                    icon: "arrow.down.circle",
                    title: NSLocalizedString("route.updates", comment: ""),
                    subtitle: L10n.updatesSubtitle(
                        version: appState.updateService.currentVersion,
                        build: appState.updateService.currentBuild
                    ),
                    tint: Color.purple.opacity(0.10)
                )

                settingsLink(
                    .premium,
                    icon: "crown.fill",
                    title: NSLocalizedString("route.premium", comment: ""),
                    subtitle: "\(appState.licenseState.tier.title) - \(appState.licenseState.statusText)",
                    tint: Color.yellow.opacity(0.12)
                )

                settingsLink(
                    .about,
                    icon: "info.circle",
                    title: NSLocalizedString("route.about", comment: ""),
                    subtitle: NSLocalizedString("about.subtitle", comment: ""),
                    tint: Color.gray.opacity(0.10)
                )
            }
            .padding(LCSpacing.sm)
            .lcCard(radius: LCRadius.panel)
        }
    }

    private var providersSettings: some View {
        VStack(spacing: LCSpacing.xs) {
            LCSectionHeader(title: "settings.providers.section")
            ForEach(LightProviderKind.allCases, id: \.self) { provider in
                let isConfigured = appState.configuredProviderKinds.contains(provider)
                providerRow(provider, isConfigured: isConfigured)
            }
        }
        .padding(LCSpacing.sm)
        .lcCard(radius: LCRadius.panel)
    }

    private func providerRow(_ provider: LightProviderKind, isConfigured: Bool) -> some View {
        Button {
            withAnimation(LCAnimation.snap) {
                route = route(for: provider)
            }
        } label: {
            HStack(spacing: LCSpacing.sm) {
                Image(systemName: providerIcon(provider))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isConfigured ? Color.green.opacity(0.85) : (provider.isImplemented ? accent : muted))
                    .frame(width: 34, height: 34)
                    .lcCard(radius: 17, tint: isConfigured ? Color.green.opacity(0.15) : nil)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title)
                        .font(LCTypo.bodySemibold())
                    Text(providerSubtitle(provider, isConfigured: isConfigured))
                        .font(LCTypo.micro())
                        .foregroundStyle(muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, LCSpacing.sm)
            .padding(.vertical, LCSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(LCPressableButtonStyle())
        .lcCard(radius: LCRadius.card, tint: Color.white.opacity(0.03))
    }

    private func providerIcon(_ provider: LightProviderKind) -> String {
        switch provider {
        case .tuya:       "cloud.fill"
        case .philipsHue: "dot.radiowaves.left.and.right"
        case .lifx:       "network"
        case .yeelight:   "wifi"
        case .govee:      "sparkles"
        case .nanoleaf:   "triangle.fill"
        case .wiz:        "lightbulb.2.fill"
        }
    }

    private func providerSubtitle(_ provider: LightProviderKind, isConfigured: Bool) -> String {
        if isConfigured { return L10n.providerConnected }
        switch provider {
        case .tuya:       return L10n.providerTuya
        case .philipsHue: return L10n.providerHue
        case .lifx:       return L10n.providerLifx
        case .govee:      return L10n.providerGovee
        case .yeelight:   return L10n.providerYeelight
        case .nanoleaf:   return L10n.providerNanoleaf
        case .wiz:        return L10n.providerWiz
        }
    }

    private func route(for provider: LightProviderKind) -> SettingsRoute {
        switch provider {
        case .tuya:       .tuya
        case .philipsHue: .hue
        case .lifx:       .lifx
        case .govee:      .govee
        case .yeelight:   .yeelight
        case .nanoleaf:   .nanoleaf
        case .wiz:        .wiz
        }
    }

    private var hueSettings: some View {
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
                        Text(appState.hueSettings.bridgeIP.isEmpty ? "hue.bridge.detect.hint" : appState.hueSettings.bridgeIP)
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
                            appState.selectHueBridge(bridge)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: appState.hueSettings.bridgeID == bridge.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(appState.hueSettings.bridgeID == bridge.id ? Color.green : muted)
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
                formField("hue.bridge.ip", text: $appState.hueSettings.bridgeIP, icon: "network")

                Button {
                    Task { await appState.pairHueBridge() }
                } label: {
                    Label(appState.hueSettings.isConfigured ? "hue.reconnect" : "hue.connect.button", systemImage: "link")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || appState.hueSettings.bridgeIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                hint("hue.hint")
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)
        }
    }

    private var lifxSettings: some View {
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

                SecureField(appState.lifxSettings.isConfigured ? "lifx.token.saved" : "lifx.token.placeholder", text: $appState.lifxSettings.token)
                    .textFieldStyle(.plain)
                    .foregroundStyle(ink)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)

                Button {
                    Task { await appState.saveLifxSettingsAndSync() }
                } label: {
                    Label("lifx.save", systemImage: "bolt.badge.checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || appState.lifxSettings.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                hint("lifx.hint")
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)
        }
    }

    private var goveeSettings: some View {
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

                SecureField(appState.goveeSettings.isConfigured ? "govee.apikey.saved" : "govee.apikey.placeholder", text: $appState.goveeSettings.apiKey)
                    .textFieldStyle(.plain)
                    .foregroundStyle(ink)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)

                Button {
                    Task { await appState.saveGoveeSettingsAndSync() }
                } label: {
                    Label("govee.save", systemImage: "bolt.badge.checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(appState.isBusy || appState.goveeSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                hint("govee.apikey.hint")
            }
            .padding(14)
            .liquidGlassSurface(radius: 22)
        }
    }

    private var yeelightSettings: some View {
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

    // MARK: - Nanoleaf Settings

    private var nanoleafSettings: some View {
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
                        await appState.addNanoleafDevice(host: newNanoleafHost, name: newNanoleafName)
                        newNanoleafHost = ""
                        newNanoleafName = ""
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

    // MARK: - WiZ Settings

    private var wizSettings: some View {
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
                        await appState.addWizDevice(host: newWizHost, name: newWizName)
                        newWizHost = ""
                        newWizName = ""
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

    // MARK: - Automations Settings

    private var automationsSettings: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: Color.green.opacity(0.10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("automations.header")
                            .font(.system(size: 13, weight: .semibold))
                        Text("automations.header.detail")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(12)
                .liquidGlassSurface(radius: 16)

                if appState.automations.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.badge.xmark")
                            .foregroundStyle(muted)
                            .frame(width: 24, height: 24)
                        Text("automations.empty.message")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                        Spacer()
                    }
                    .padding(12)
                    .liquidGlassSurface(radius: 14)
                } else {
                    ForEach(appState.automations) { automation in
                        HStack(spacing: 10) {
                            Image(systemName: automation.action.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(automation.isEnabled ? accent : muted)
                                .frame(width: 28, height: 28)
                                .liquidGlassSurface(radius: 10, tint: automation.isEnabled ? accent.opacity(0.10) : nil)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(automation.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ink)
                                Text("\(automation.timeString) · \(automation.weekdaysLabel)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(muted)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { automation.isEnabled },
                                set: { _ in appState.toggleAutomation(automation) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .scaleEffect(0.8)

                            Button {
                                appState.deleteAutomation(automation)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.red)
                                    .frame(width: 26, height: 26)
                            }
                            .liquidGlassButtonStyle()
                            .help("help.automation.delete")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .liquidGlassSurface(radius: 14)
                    }
                }

                if isAddingAutomation {
                    AutomationEditor(isPresented: $isAddingAutomation) { automation in
                        appState.saveAutomation(automation)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !isAddingAutomation {
                    Button { isAddingAutomation = true } label: {
                        Label("automations.new", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .liquidGlassButtonStyle(prominent: appState.licenseState.entitlements.canUseAutomations)
                    .disabled(!appState.licenseState.entitlements.canUseAutomations || appState.isBusy)
                    .overlay {
                        if !appState.licenseState.entitlements.canUseAutomations {
                            HStack {
                                Spacer()
                                Label("Premium", systemImage: "crown.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.yellow)
                                    .padding(.trailing, 12)
                            }
                        }
                    }
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isAddingAutomation)
        }
    }

    // MARK: - Focus Mode Settings

    private var focusSettings: some View {
        VStack(spacing: 12) {
            // Premium gating
            if !appState.licenseState.entitlements.canUseFocusMappings {
                settingsGroup {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Color.yellow)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.focusTitle)
                                .font(.system(size: 12, weight: .semibold))
                            Text(L10n.focusPremiumMessage)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(muted)
                        }
                        Spacer()
                        Label("premium.locked", systemImage: "crown.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.yellow)
                    }
                    .padding(10)
                    .liquidGlassSurface(radius: 16)
                }
            } else {
                settingsGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.focusTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ink)
                            Spacer()
                            Button {
                                isCreatingFocusMapping = true
                                newFocusIdentifier = ""
                                newFocusSceneId = nil
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 26, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if appState.focusMappings.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "target")
                                    .foregroundStyle(muted)
                                    .frame(width: 24, height: 24)
                                Text(L10n.focusEmptyMessage)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(muted)
                                Spacer()
                            }
                            .padding(12)
                            .liquidGlassSurface(radius: 14)
                        } else {
                            ForEach(appState.focusMappings) { mapping in
                                HStack(spacing: 8) {
                                    Image(systemName: "target")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(accent)
                                        .frame(width: 20, height: 20)
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(mapping.focusDisplayName)
                                            .font(.system(size: 11, weight: .semibold))
                                        let sceneName = appState.userScenes.first(where: { $0.id == mapping.sceneId })?.title ?? "—"
                                        Text(sceneName)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(muted)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { mapping.isEnabled },
                                        set: { enabled in
                                            var updated = mapping
                                            updated.isEnabled = enabled
                                            appState.updateFocusMapping(updated)
                                        }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .tint(accent)
                                    
                                    Button {
                                        editingFocusMappingId = mapping.id
                                        newFocusIdentifier = mapping.focusIdentifier
                                        newFocusSceneId = mapping.sceneId
                                    } label: {
                                        Image(systemName: "pencil.circle")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(accent)
                                            .frame(width: 28, height: 28)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("help.focus.edit")

                                    Button {
                                        appState.removeFocusMapping(mapping.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.red)
                                            .frame(width: 28, height: 28)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("help.focus.delete")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .liquidGlassSurface(radius: 10)
                            }
                        }

                        // Create new mapping
                        if isCreatingFocusMapping {
                            VStack(spacing: 8) {
                                TextField(L10n.focusIdentifierPlaceholder, text: $newFocusIdentifier)
                                    .font(.system(size: 11, weight: .medium))
                                    .textFieldStyle(.roundedBorder)
                                
                                Picker(L10n.focusScenePlaceholder, selection: $newFocusSceneId) {
                                    Text("—").tag(UUID?.none)
                                    ForEach(appState.userScenes) { scene in
                                        Text(scene.title).tag(UUID?.some(scene.id))
                                    }
                                }
                                .font(.system(size: 11, weight: .medium))
                                
                                HStack(spacing: 8) {
                                    Button(L10n.save) {
                                        let trimmed = newFocusIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty, newFocusSceneId != nil else { return }
                                        let mapping = FocusMapping(focusIdentifier: trimmed, focusDisplayName: trimmed, sceneId: newFocusSceneId)
                                        appState.addFocusMapping(mapping)
                                        isCreatingFocusMapping = false
                                        newFocusIdentifier = ""
                                        newFocusSceneId = nil
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .liquidGlassButtonStyle(prominent: true)
                                    
                                    Button(L10n.cancel) {
                                        isCreatingFocusMapping = false
                                        newFocusIdentifier = ""
                                        newFocusSceneId = nil
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .liquidGlassButtonStyle()
                                }
                            }
                            .padding(10)
                            .liquidGlassSurface(radius: 14)
                        }

                        // Edit mapping
                        if let editingId = editingFocusMappingId, let idx = appState.focusMappings.firstIndex(where: { $0.id == editingId }) {
                            VStack(spacing: 8) {
                                TextField(L10n.focusIdentifierPlaceholder, text: $newFocusIdentifier)
                                    .font(.system(size: 11, weight: .medium))
                                    .textFieldStyle(.roundedBorder)
                                
                                Picker(L10n.focusScenePlaceholder, selection: $newFocusSceneId) {
                                    Text("—").tag(UUID?.none)
                                    ForEach(appState.userScenes) { scene in
                                        Text(scene.title).tag(UUID?.some(scene.id))
                                    }
                                }
                                .font(.system(size: 11, weight: .medium))
                                
                                HStack(spacing: 8) {
                                    Button(L10n.save) {
                                        let trimmed = newFocusIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty, newFocusSceneId != nil else { return }
                                        var updated = appState.focusMappings[idx]
                                        updated.focusIdentifier = trimmed
                                        updated.focusDisplayName = trimmed
                                        updated.sceneId = newFocusSceneId
                                        appState.updateFocusMapping(updated)
                                        editingFocusMappingId = nil
                                        newFocusIdentifier = ""
                                        newFocusSceneId = nil
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .liquidGlassButtonStyle(prominent: true)
                                    
                                    Button(L10n.cancel) {
                                        editingFocusMappingId = nil
                                        newFocusIdentifier = ""
                                        newFocusSceneId = nil
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .liquidGlassButtonStyle()
                                }
                            }
                            .padding(10)
                            .liquidGlassSurface(radius: 14)
                        }
                    }
                }

                focusAutomationGroup
            }
        }
    }

    /// Setup hint + the exact `lampcontrol://focus?mode=…` URLs to paste in a Shortcuts automation.
    private var focusAutomationGroup: some View {
        // Only modes that actually have a mapping get a URL — a URL for an
        // unmapped mode would silently do nothing.
        let builtInNames = Dictionary(
            appState.availableFocusModes.map { ($0.identifier.lowercased(), $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        let mappedRows: [(title: String, mode: String)] = appState.focusMappings
            .map(\.focusIdentifier)
            .filter { seen.insert($0.lowercased()).inserted }
            .map { (builtInNames[$0.lowercased()] ?? $0, $0) }
        let rows = mappedRows
            + [(NSLocalizedString("focus.automation.off", comment: ""), FocusAutomationURL.offMode)]

        return settingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("focus.automation.title")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)

                hint("focus.automation.hint")

                ForEach(rows, id: \.mode) { row in
                    focusURLRow(title: row.title, mode: row.mode)
                }
            }
        }
    }

    private func focusURLRow(title: String, mode: String) -> some View {
        let url = FocusAutomationURL.urlString(forMode: mode)
        let didCopy = copiedFocusMode == mode

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(url)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(muted)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                copiedFocusMode = mode
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if copiedFocusMode == mode { copiedFocusMode = nil }
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("focus.automation.copy.help")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .liquidGlassSurface(radius: 10)
    }

    // MARK: - Circadian Settings

    private var circadianSettings_: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.and.horizon.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: Color.orange.opacity(0.10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("circadian.header")
                            .font(.system(size: 13, weight: .semibold))
                        Text("circadian.detail")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appState.circadianSettings.isEnabled },
                        set: { v in Task { await appState.setAdaptiveLighting(enabled: v) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!appState.licenseState.entitlements.canUseAdaptiveLighting)
                }
                .padding(12)
                .liquidGlassSurface(radius: 16)

                HStack(spacing: 10) {
                    Toggle("circadian.brightness", isOn: circadianDraftBinding.applyBrightness)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle("circadian.temperature", isOn: circadianDraftBinding.applyTemperature)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .liquidGlassSurface(radius: 14)

                circadianSchedule

                HStack(spacing: 8) {
                    Button {
                        Task { await appState.applyCircadianNow() }
                    } label: {
                        Label("circadian.apply.now", systemImage: "sun.and.horizon")
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .liquidGlassButtonStyle(prominent: appState.circadianSettings.isEnabled)
                    // "Apply now" uses the saved schedule; Save applies the
                    // edited one immediately, so it waits for Save when dirty.
                    .disabled(!appState.circadianSettings.isEnabled || appState.isBusy || isCircadianDraftDirty)

                    Button {
                        saveCircadianDraft()
                    } label: {
                        Text("action.save")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 100, height: 38)
                    }
                    .liquidGlassButtonStyle(prominent: true)
                    .tint(accent)
                    .disabled(appState.isBusy)
                }
            }
        }
        // Unsaved edits are discarded when leaving the section: the running
        // service and the stored settings never see them.
        .onDisappear {
            circadianDraft = nil
            editingKeyframeId = nil
        }
    }

    // MARK: Adaptive lighting draft

    /// Edits to the schedule live here until Save; `nil` means no edits.
    private var circadianDraftValue: CircadianSettings {
        circadianDraft ?? appState.circadianSettings
    }

    private var circadianDraftBinding: Binding<CircadianSettings> {
        Binding(get: { circadianDraftValue }, set: { circadianDraft = $0 })
    }

    private func mutateCircadianDraft(_ change: (inout CircadianSettings) -> Void) {
        var draft = circadianDraftValue
        change(&draft)
        circadianDraft = draft
    }

    private var isCircadianDraftDirty: Bool {
        guard let draft = circadianDraft else { return false }
        return !draft.hasSameContent(as: appState.circadianSettings)
    }

    private func saveCircadianDraft() {
        guard var draft = circadianDraft else {
            Task { await appState.saveCircadianSettings(appState.circadianSettings) }
            return
        }
        // The enable switch is not part of the draft (it saves on its own).
        draft.isEnabled = appState.circadianSettings.isEnabled
        Task {
            await appState.saveCircadianSettings(draft)
            if appState.circadianSettings == draft { circadianDraft = nil }
        }
    }

    // MARK: - Adaptive lighting schedule

    /// Time points of the adaptive curve. They used to be read-only rows, so
    /// nothing about the schedule could actually be configured.
    private var circadianSchedule: some View {
        let settings = circadianDraftValue
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let current = settings.values(at: (now.hour ?? 0) * 60 + (now.minute ?? 0))

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("circadian.schedule")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(L10n.circadianNow(brightness: current.brightness, temperature: current.temperature))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 4)

            Text("circadian.schedule.hint")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            ForEach(settings.keyframes.sorted(by: { $0.minuteOfDay < $1.minuteOfDay })) { kf in
                circadianKeyframeRow(kf)
            }

            HStack(spacing: 8) {
                Button {
                    addCircadianKeyframe()
                } label: {
                    Label("circadian.keyframe.add", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .liquidGlassButtonStyle()
                .disabled(settings.keyframes.count >= 12)

                Button {
                    editingKeyframeId = nil
                    mutateCircadianDraft { $0.keyframes = CircadianSettings.defaultKeyframes }
                } label: {
                    Label("circadian.reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .liquidGlassButtonStyle()
            }
        }
    }

    private func circadianKeyframeRow(_ kf: CircadianKeyframe) -> some View {
        let isEditing = editingKeyframeId == kf.id
        return VStack(spacing: 8) {
            Button {
                withAnimation(LCAnimation.standard) {
                    editingKeyframeId = isEditing ? nil : kf.id
                }
            } label: {
                HStack(spacing: 12) {
                    Text(String(format: "%02d:%02d", kf.hour, kf.minute))
                        .font(.system(size: 12, weight: .semibold).monospaced())
                        .foregroundStyle(accent)
                        .frame(width: 44, alignment: .leading)
                    Text(L10n.circadianKeyframeBrightness(kf.brightness))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LCTheme.muted)
                    Text("\(kf.temperature) K")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LCTheme.muted)
                    Spacer()
                    Circle()
                        .fill(Color(nsColor: StatusItemIcon.kelvinColor(kf.temperature)))
                        .opacity(0.35 + 0.65 * Double(kf.brightness) / 100)
                        .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.5))
                        .frame(width: 12, height: 12)
                    Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("circadian.keyframe.edit")

            if isEditing, let binding = keyframeBinding(kf.id) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("circadian.keyframe.time")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                        Spacer()
                        DatePicker("", selection: keyframeTimeBinding(binding), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(width: 14)
                            .help("help.brightness")
                        Slider(value: Binding(
                            get: { Double(binding.wrappedValue.brightness) },
                            set: { binding.wrappedValue.brightness = Int($0.rounded()) }
                        ), in: 1...100)
                        Text("\(binding.wrappedValue.brightness) %")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(muted)
                            .frame(width: 44, alignment: .trailing)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "thermometer.sun")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(width: 14)
                            .help("help.temperature")
                        Slider(value: Binding(
                            get: { Double(binding.wrappedValue.temperature) },
                            set: { binding.wrappedValue.temperature = Int(($0 / 100).rounded()) * 100 }
                        ), in: 1700...6500)
                        Text("\(binding.wrappedValue.temperature) K")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(muted)
                            .frame(width: 44, alignment: .trailing)
                    }
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            editingKeyframeId = nil
                            mutateCircadianDraft { $0.keyframes.removeAll { $0.id == kf.id } }
                        } label: {
                            Label("circadian.keyframe.delete", systemImage: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LCPalette.danger)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                        }
                        .liquidGlassButtonStyle()
                        // The curve needs at least two points to interpolate.
                        .disabled(circadianDraftValue.keyframes.count <= 2)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlassSurface(radius: 12)
    }

    private func keyframeBinding(_ id: UUID) -> Binding<CircadianKeyframe>? {
        guard circadianDraftValue.keyframes.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                circadianDraftValue.keyframes.first(where: { $0.id == id })
                    ?? CircadianKeyframe(hour: 0, minute: 0, brightness: 80, temperature: 4000)
            },
            set: { newValue in
                mutateCircadianDraft { draft in
                    if let index = draft.keyframes.firstIndex(where: { $0.id == id }) {
                        draft.keyframes[index] = newValue
                    }
                }
            }
        )
    }

    private func keyframeTimeBinding(_ keyframe: Binding<CircadianKeyframe>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: keyframe.wrappedValue.hour,
                                      minute: keyframe.wrappedValue.minute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                keyframe.wrappedValue.hour = parts.hour ?? 0
                keyframe.wrappedValue.minute = parts.minute ?? 0
            }
        )
    }

    /// New point in the middle of the largest gap, with interpolated values.
    private func addCircadianKeyframe() {
        let settings = circadianDraftValue
        let minutes = settings.keyframes.map(\.minuteOfDay).sorted()
        var target = 12 * 60
        if minutes.count >= 1 {
            var bestGap = -1
            for (index, start) in minutes.enumerated() {
                let end = index + 1 < minutes.count ? minutes[index + 1] : minutes[0] + 24 * 60
                if end - start > bestGap {
                    bestGap = end - start
                    target = (start + (end - start) / 2) % (24 * 60)
                }
            }
        }
        target = target / 15 * 15
        let values = settings.values(at: target)
        let keyframe = CircadianKeyframe(hour: target / 60, minute: target % 60,
                                         brightness: values.brightness, temperature: values.temperature)
        mutateCircadianDraft { $0.keyframes.append(keyframe) }
        editingKeyframeId = keyframe.id
    }

    /// Overview status: any configured provider counts. (The Tuya-specific
    /// step summary used to sit here and reported "setup incomplete" to users
    /// of every other vendor; it now lives in the Tuya section.)
    private var providersSummary: some View {
        let connected = appState.configuredProviderKinds
        let isReady = !connected.isEmpty
        return Button {
            if !isReady { withAnimation(LCAnimation.snap) { route = .providers } }
        } label: {
            HStack(spacing: LCSpacing.sm) {
                Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isReady ? LCPalette.success : Color.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isReady ? "setup.complete" : "setup.incomplete")
                        .font(LCTypo.bodySemibold())
                        .foregroundStyle(LCPalette.ink)
                    Text(isReady
                         ? L10n.providersConnected(connected.map(\.title).joined(separator: ", "))
                         : NSLocalizedString("setup.providers.none", comment: ""))
                        .font(LCTypo.micro())
                        .foregroundStyle(LCPalette.muted)
                        .lineLimit(1)
                }

                Spacer()

                if !isReady {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LCPalette.muted)
                }
            }
            .padding(.horizontal, LCSpacing.sm)
            .padding(.vertical, LCSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: LCRadius.card, style: .continuous)
                    .fill(LCPalette.muted.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReady)
    }

    private var setupSummary: some View {
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

                Button(action: openConfigurationGuide) {
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

    /// Same look as `settingsLink`, with a "Restore" button instead of the chevron.
    private var restoreScenesRow: some View {
        HStack(spacing: LCSpacing.sm) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .lcCard(radius: 18, tint: Color.pink.opacity(0.10))

            VStack(alignment: .leading, spacing: 2) {
                Text("settings.scenes.restore.title")
                    .font(LCTypo.bodySemibold())
                    .foregroundStyle(ink)
                Text("settings.scenes.restore.detail")
                    .font(LCTypo.micro())
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }

            Spacer()

            Button("settings.scenes.restore.button") {
                appState.restoreDefaultScenes()
            }
            .font(.system(size: 11, weight: .semibold))
            .liquidGlassButtonStyle()
            .help("help.scenes.restore")
        }
        .padding(.horizontal, LCSpacing.sm)
        .frame(height: 60)
        .lcCard(radius: LCRadius.card, tint: Color.white.opacity(0.04))
    }

    /// Same look as `settingsLink`, with a switch instead of the chevron.
    private var launchAtLoginRow: some View {
        VStack(spacing: LCSpacing.xs) {
            HStack(spacing: LCSpacing.sm) {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .lcCard(radius: 18, tint: Color.mint.opacity(0.10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("login.item.title")
                        .font(LCTypo.bodySemibold())
                        .foregroundStyle(ink)
                    Text("login.item.detail")
                        .font(LCTypo.micro())
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("login.item.title", isOn: Binding(
                    get: { appState.isLaunchAtLoginOn },
                    set: { appState.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(accent)
            }
            .frame(height: 60)

            if appState.loginItemStatus == .requiresApproval {
                HStack(spacing: LCSpacing.sm) {
                    Text("login.item.approval.hint")
                        .font(LCTypo.micro())
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("login.item.open.settings") {
                        appState.openLoginItemsSettings()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .liquidGlassButtonStyle()
                }
                .padding(.bottom, LCSpacing.sm)
            }
        }
        .padding(.horizontal, LCSpacing.sm)
        .lcCard(radius: LCRadius.card, tint: Color.white.opacity(0.04))
        .onAppear { appState.refreshLoginItemStatus() }
    }

    private func settingsLink(_ route: SettingsRoute, icon: String, title: String, subtitle: String, tint: Color) -> some View {
        Button {
            withAnimation(LCAnimation.snap) {
                self.route = route
            }
        } label: {
            HStack(spacing: LCSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .lcCard(radius: 18, tint: tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LCTypo.bodySemibold())
                        .foregroundStyle(ink)
                    Text(subtitle)
                        .font(LCTypo.micro())
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, LCSpacing.sm)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(LCPressableButtonStyle())
        .lcCard(radius: LCRadius.card, tint: Color.white.opacity(0.04))
    }

    private var tuyaSettings: some View {
        VStack(spacing: 12) {
            setupSummary

            settingsGroup {
                formField("tuya.access.id", text: $appState.settings.accessId, icon: "key")
                secureField
                settingsPicker
                formField("tuya.endpoint", text: $appState.settings.endpoint, icon: "network")
                formField("tuya.uid", text: $appState.settings.uid, icon: "person.crop.circle")
            }

            HStack(spacing: 8) {
                Button {
                    Task { await appState.saveSettings() }
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
                    Task { await appState.saveSettingsAndSync() }
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

            hint("tuya.hint")
        }
    }

    private var secureField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("tuya.access.secret", icon: "lock")

            SecureField(appState.hasSecret ? "tuya.secret.placeholder" : "tuya.access.secret", text: $appState.settings.accessSecret)
                .textFieldStyle(.plain)
                .foregroundStyle(ink)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 38)
                .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)
        }
    }

    private var settingsPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("tuya.region", icon: "globe.europe.africa")

            Picker("tuya.region", selection: $appState.settings.region) {
                Text("Europe").tag(TuyaRegion.eu)
                Text("US West").tag(TuyaRegion.us)
                Text("US East").tag(TuyaRegion.usEast)
                Text("China").tag(TuyaRegion.cn)
                Text("India").tag(TuyaRegion.in)
                Text("Custom").tag(TuyaRegion.custom)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)
            .onChange(of: appState.settings.region) { _ in
                appState.settings.applyEndpoint(for: appState.settings.region)
            }
        }
    }

    private var devicesSettings: some View {
        VStack(spacing: 12) {
            settingsGroup {
                infoRow("devices.detected", value: "\(appState.lamps.count)", icon: "lightbulb.2")
                infoRow("devices.online",   value: "\(appState.lamps.filter(\.online).count)", icon: "wifi")
                infoRow("devices.sync",     value: syncSummary, icon: "arrow.triangle.2.circlepath")
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("devices.display.options")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ink)
                    
                    Toggle("devices.hide.offline", isOn: $appState.hideOfflineLamps)
                        .font(.system(size: 12, weight: .semibold))
                        .toggleStyle(.switch)
                        .tint(accent)
                }
            }

            Button {
                Task { await appState.syncLamps() }
            } label: {
                Label("devices.sync.now", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle(prominent: true)
            .tint(accent)
            .disabled(appState.isBusy || !appState.canSync)
            .opacity(appState.isBusy || !appState.canSync ? 0.55 : 1)

            hint(appState.canSync ? "devices.sync.hint" : "devices.sync.required.hint")

            // Room management section
            if !appState.licenseState.entitlements.canUseRooms {
                settingsGroup {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Color.yellow)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("devices.rooms.title")
                                .font(.system(size: 12, weight: .semibold))
                            Text("room.premium.message")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(muted)
                        }
                        Spacer()
                        Label("premium.locked", systemImage: "crown.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.yellow)
                    }
                    .padding(10)
                    .liquidGlassSurface(radius: 16)
                }
            } else {
                settingsGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("devices.rooms.title")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ink)
                            Spacer()
                            Button {
                                isCreatingRoom = true
                                newRoomName = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 26, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        // List rooms with edit/delete
                        ForEach(appState.rooms) { room in
                            HStack(spacing: 8) {
                                Image(systemName: "door.left.hand.open")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 20, height: 20)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(room.name)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(L10n.lampCount(room.lampIds.count))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(muted)
                                }

                                Spacer()

                                Button {
                                    editingRoomId = room.id
                                    newRoomName = room.name
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(accent)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("help.room.edit")

                                Button {
                                    var updated = room
                                    updated.lampIds = []
                                    if let idx = appState.rooms.firstIndex(where: { $0.id == room.id }) {
                                        appState.rooms.remove(at: idx)
                                        appState.persistRooms()
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.red)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("help.room.delete")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .liquidGlassSurface(radius: 10)
                        }

                        // Lamp assignment
                        if !appState.lamps.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("room.assign.lamps")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(muted)
                                
                                ForEach(appState.lamps) { lamp in
                                    HStack(spacing: 8) {
                                        Text(lamp.name)
                                            .font(.system(size: 11, weight: .medium))
                                        Spacer()
                                        let current = appState.roomForLamp(lamp.id)?.name ?? L10n.roomUnassigned
                                        Text(current)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(muted)

                                        Menu {
                                            Button(L10n.roomUnassigned) { appState.unassignLamp(lamp.id) }
                                            ForEach(appState.rooms) { room in
                                                Button(room.name) { appState.assignLamp(lamp.id, to: room.id) }
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(accent)
                                        }
                                        .menuStyle(BorderlessButtonMenuStyle())
                                        .help("help.room.assign")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .liquidGlassSurface(radius: 10)
                                }
                            }
                        }

                        if isCreatingRoom {
                            HStack(spacing: 8) {
                                TextField("room.name.placeholder", text: $newRoomName)
                                    .font(.system(size: 11, weight: .medium))
                                    .textFieldStyle(.roundedBorder)
                                
                                Button(L10n.save) {
                                    let trimmed = newRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    appState.rooms.append(Room(name: trimmed))
                                    appState.persistRooms()
                                    isCreatingRoom = false
                                    newRoomName = ""
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .liquidGlassButtonStyle(prominent: true)
                                
                                Button(L10n.cancel) {
                                    isCreatingRoom = false
                                    newRoomName = ""
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .liquidGlassButtonStyle()
                            }
                        }

                        if let editingId = editingRoomId, let idx = appState.rooms.firstIndex(where: { $0.id == editingId }) {
                            HStack(spacing: 8) {
                                TextField("room.name.placeholder", text: $newRoomName)
                                    .font(.system(size: 11, weight: .medium))
                                    .textFieldStyle(.roundedBorder)
                                
                                Button(L10n.save) {
                                    let trimmed = newRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    appState.rooms[idx].name = trimmed
                                    appState.persistRooms()
                                    editingRoomId = nil
                                    newRoomName = ""
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .liquidGlassButtonStyle(prominent: true)
                                
                                Button(L10n.cancel) {
                                    editingRoomId = nil
                                    newRoomName = ""
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .liquidGlassButtonStyle()
                            }
                        }
                    }
                }
            }
        }
    }

    private var updatesSettings: some View {
        VStack(spacing: 12) {
            if !appState.updateService.isAvailable {
                hintText(NSLocalizedString("updates.unavailable", comment: ""))
            }

            settingsGroup {
                toggleRow(
                    title: "updates.auto.check",
                    subtitle: "updates.auto.check.detail",
                    isOn: $appState.updateService.automaticChecksEnabled
                )
                .disabled(!appState.updateService.isAvailable)
                .opacity(appState.updateService.isAvailable ? 1 : 0.5)

                toggleRow(
                    title: "updates.auto.install",
                    subtitle: "updates.auto.install.detail",
                    isOn: $appState.updateService.automaticDownloadsEnabled
                )
                .disabled(!appState.updateService.automaticChecksEnabled)
                .opacity(appState.updateService.automaticChecksEnabled ? 1 : 0.5)

                infoRow("updates.current.version", value: "\(appState.updateService.currentVersion) (\(appState.updateService.currentBuild))", icon: "number")
            }

            Button {
                appState.updateService.checkForUpdates()
            } label: {
                Label("updates.check.now", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle(prominent: true)
            .tint(accent)
            .disabled(!appState.updateService.canCheckForUpdates)
            .opacity(appState.updateService.canCheckForUpdates ? 1 : 0.55)

            if let date = appState.updateService.lastCheckedAt {
                hintText(L10n.updatesLastCheck(date.formatted(date: .omitted, time: .shortened)))
            }
        }
    }

    private var aboutSettings: some View {
        VStack(spacing: 12) {
            settingsGroup {
                infoRow("about.app",     value: "LampControl", icon: "lightbulb.led")
                infoRow("about.version", value: "\(appState.updateService.currentVersion) build \(appState.updateService.currentBuild)", icon: "shippingbox")
                infoRow("about.storage", value: NSLocalizedString("about.storage.value", comment: ""), icon: "lock.square")
            }

            Button {
                openConfigurationGuide()
            } label: {
                Label("about.config.guide", systemImage: "book")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle()

            Button {
                confirmAndResetAllSettings()
            } label: {
                Label("settings.reset.button", systemImage: "arrow.counterclockwise.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LCPalette.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle()

            Button {
                appState.quit()
            } label: {
                Label("app.quit", systemImage: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LCPalette.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle()
        }
    }

    /// A native modal alert: always reliably presented from the menu-bar
    /// popover (SwiftUI alerts/sheets attach to the popover window, which is
    /// fragile). The popover may close while the alert is up; that is fine.
    private func confirmAndResetAllSettings() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = NSLocalizedString("settings.reset.confirm.title", comment: "")
        alert.informativeText = NSLocalizedString("settings.reset.confirm.message", comment: "")
        let reset = alert.addButton(withTitle: NSLocalizedString("settings.reset.confirm.action", comment: ""))
        reset.hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("settings.reset.confirm.cancel", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            appState.resetAllSettings()
        }
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .padding(14)
        .liquidGlassSurface(radius: 22)
    }

    private func formField(_ titleKey: LocalizedStringKey, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(titleKey, icon: icon)

            TextField(titleKey, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(ink)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 38)
                .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)
        }
    }

    private func fieldLabel(_ titleKey: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(titleKey)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(muted)
    }

    private func toggleRow(title: LocalizedStringKey, subtitle: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(muted)
            }
        }
        .toggleStyle(.switch)
        .tint(accent)
    }

    private func infoRow(_ titleKey: LocalizedStringKey, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .liquidGlassSurface(radius: 10)

            Text(titleKey)
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted)
                .lineLimit(1)
        }
    }

    private func hint(_ textKey: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(accent)
                .padding(.top, 1)
            Text(textKey)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
    }

    private func hintText(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(accent)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
    }

    private var syncSummary: String {
        guard let lastSyncDate = appState.lastSyncDate else { return L10n.syncNever }
        return lastSyncDate.formatted(date: .omitted, time: .shortened)
    }

    private var setupSteps: [SetupStep] {
        [
            SetupStep(title: "ID",     icon: "key.fill",              isComplete: !appState.settings.accessId.trimmed.isEmpty),
            SetupStep(title: "Secret", icon: "lock.fill",             isComplete: appState.hasSecret || !appState.settings.accessSecret.trimmed.isEmpty),
            SetupStep(title: "Region", icon: "globe.europe.africa.fill", isComplete: !appState.settings.endpoint.trimmed.isEmpty),
            SetupStep(title: "UID",    icon: "person.fill",           isComplete: !appState.settings.uid.trimmed.isEmpty)
        ]
    }

    private var completedSetupCount: Int { setupSteps.filter(\.isComplete).count }
    private var setupProgress: CGFloat  { CGFloat(completedSetupCount) / CGFloat(max(setupSteps.count, 1)) }
    private var isSetupComplete: Bool   { completedSetupCount == setupSteps.count }

    private func openConfigurationGuide() {
        guard let url = URL(string: "https://github.com/hugoinformatique/LampControl/blob/main/docs/CONFIGURATION.fr.md") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - AutomationEditor

private struct AutomationEditor: View {
    @Binding var isPresented: Bool
    var onSave: (Automation) -> Void

    @State private var name = ""
    @State private var hour = 22
    @State private var minute = 0
    @State private var action: AutomationAction = .powerOffAll
    @State private var weekdays = Set<Int>()

    private let actions: [AutomationAction] = [
        .powerOffAll, .powerOnAll,
        .applyScenePreset(id: "focus"), .applyScenePreset(id: "relax"),
        .applyScenePreset(id: "neon"),  .applyScenePreset(id: "night"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            TextField("automation.name.placeholder", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .frame(height: 34)
                .liquidGlassSurface(radius: 12, tint: Color.white.opacity(0.06), interactive: true)

            HStack(spacing: 8) {
                Stepper(value: $hour, in: 0...23) {
                    Text(String(format: "H %02d", hour))
                        .font(.system(size: 12, weight: .semibold).monospaced())
                        .frame(width: 52)
                }
                Stepper(value: $minute, in: 0...59, step: 5) {
                    Text(String(format: "M %02d", minute))
                        .font(.system(size: 12, weight: .semibold).monospaced())
                        .frame(width: 52)
                }
            }

            Picker("", selection: $action) {
                ForEach(actions, id: \.title) { a in
                    Label(a.title, systemImage: a.icon).tag(a)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .liquidGlassSurface(radius: 12, tint: Color.white.opacity(0.06))

            HStack(spacing: 6) {
                Text("automation.days")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LCTheme.muted)
                ForEach(1...7, id: \.self) { day in
                    Button {
                        if weekdays.contains(day) { weekdays.remove(day) }
                        else { weekdays.insert(day) }
                    } label: {
                        Text(L10n.dayLetters[safe: day - 1] ?? "")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(weekdays.contains(day) ? Color.white : LCTheme.muted)
                            .frame(width: 24, height: 24)
                            .liquidGlassCircle(tint: weekdays.contains(day) ? LCTheme.accent.opacity(0.50) : nil)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    let a = Automation(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? action.title : name.trimmingCharacters(in: .whitespacesAndNewlines),
                        hour: hour, minute: minute,
                        weekdays: weekdays, action: action
                    )
                    onSave(a)
                    isPresented = false
                } label: {
                    Label("automation.create", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .liquidGlassButtonStyle(prominent: true)

                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .liquidGlassButtonStyle()
                .help("app.close")
                .foregroundStyle(LCTheme.muted)
            }
        }
        .padding(12)
        .liquidGlassSurface(radius: 18, tint: Color.white.opacity(0.05))
    }
}

private enum SettingsRoute {
    case overview, providers, tuya, hue, lifx, govee, yeelight, nanoleaf, wiz
    case automations, focus, circadian, devices, updates, premium, about

    var title: String {
        switch self {
        case .overview:    NSLocalizedString("route.settings", comment: "")
        case .providers:   NSLocalizedString("route.providers", comment: "")
        case .tuya:        NSLocalizedString("route.tuya", comment: "")
        case .hue:         NSLocalizedString("route.hue", comment: "")
        case .lifx:        NSLocalizedString("route.lifx", comment: "")
        case .govee:       NSLocalizedString("route.govee", comment: "")
        case .yeelight:    NSLocalizedString("route.yeelight", comment: "")
        case .nanoleaf:    NSLocalizedString("route.nanoleaf", comment: "")
        case .wiz:         NSLocalizedString("route.wiz", comment: "")
        case .automations: NSLocalizedString("route.automations", comment: "")
        case .focus:       L10n.focusTitle
        case .circadian:   NSLocalizedString("route.circadian", comment: "")
        case .devices:     NSLocalizedString("route.devices", comment: "")
        case .updates:     NSLocalizedString("route.updates", comment: "")
        case .premium:     NSLocalizedString("route.premium", comment: "")
        case .about:       NSLocalizedString("route.about", comment: "")
        }
    }

    @MainActor
    func subtitle(appState: AppState) -> String {
        switch self {
        case .overview:
            appState.canSync ? L10n.routeSettingsActive : L10n.routeSettingsRequired
        case .providers:
            L10n.routeProvidersSubtitle
        case .tuya:
            L10n.routeTuyaSubtitle
        case .hue:
            appState.hueSettings.isConfigured ? L10n.routeHueConnected : L10n.routeHueDisconnected
        case .lifx:
            appState.lifxSettings.isConfigured ? L10n.routeLifxConnected : L10n.routeLifxDisconnected
        case .govee:
            appState.goveeSettings.isConfigured ? L10n.routeGoveeConnected : L10n.routeGoveeDisconnected
        case .yeelight:
            appState.yeelightSettings.isConfigured
                ? L10n.routeYeeConnected(appState.yeelightSettings.bulbs.count)
                : L10n.routeYeeNone
        case .nanoleaf:
            appState.nanoleafSettings.isConfigured
                ? L10n.routeNanoleafConnected(appState.nanoleafSettings.devices.count)
                : L10n.routeNanoleafNone
        case .wiz:
            appState.wizSettings.isConfigured
                ? L10n.routeWizConnected(appState.wizSettings.devices.count)
                : L10n.routeWizNone
        case .automations:
            appState.automations.isEmpty
                ? L10n.routeAutomationsNone
                : L10n.routeAutomationsActive(appState.automations.filter(\.isEnabled).count, appState.automations.count)
        case .focus:
            appState.focusMappings.isEmpty
                ? L10n.focusEmptyMessage
                : L10n.routeFocusActive(appState.focusMappings.filter(\.isEnabled).count)
        case .circadian:
            appState.circadianSettings.isEnabled
                ? L10n.routeCircadianActive(appState.circadianSettings.keyframes.count)
                : L10n.routeCircadianDisabled
        case .devices:
            L10n.routeDevices(appState.lamps.count)
        case .updates:
            L10n.routeUpdatesSubtitle
        case .premium:
            appState.licenseState.statusText
        case .about:
            L10n.routeAboutSubtitle
        }
    }
}

private struct SetupStep: Identifiable {
    let title: String
    let icon: String
    let isComplete: Bool
    var id: String { title }
}

private struct SetupStepPill: View {
    let step: SetupStep

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: step.isComplete ? "checkmark.circle.fill" : step.icon)
                .font(.system(size: 10, weight: .bold))
            Text(step.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(step.isComplete ? LCTheme.accent : LCTheme.muted)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .liquidGlassSurface(
            radius: 13,
            tint: step.isComplete ? Color.green.opacity(0.12) : Color.white.opacity(0.06)
        )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
