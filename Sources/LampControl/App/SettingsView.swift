import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State var route: SettingsRoute = .overview
    @State var newYeelightHost: String = ""
    @State var newYeelightName: String = ""
    @State var newNanoleafHost: String = ""
    @State var newNanoleafName: String = ""
    @State var newWizHost: String = ""
    @State var newWizName: String = ""
    @State var isAddingAutomation = false
    /// One editor per section: the create and the edit form can never be open together.
    @State var roomEditor: SectionEditor<String> = .none
    @State var roomDraftName: String = ""
    @State var focusEditor: SectionEditor<String> = .none
    @State var focusDraftIdentifier: String = ""
    @State var focusDraftSceneId: UUID?
    @State var editingKeyframeId: UUID?
    /// Unsaved edits to the adaptive schedule; `nil` = nothing edited.
    @State var circadianDraft: CircadianSettings?
    @State var copiedFocusMode: String?
    /// "Restore default scenes" asks first: it resets the user's edits to the built-in scenes.
    @State var confirmingSceneRestore = false
    // Credential forms edit a draft (`nil` = untouched) and only reach AppState when saved, so a
    // half-typed token never makes a provider look "configured".
    @State var hueBridgeIPDraft: String?
    @State var hueBridgeIDDraft: String?
    @State var lifxTokenDraft: String?
    @State var goveeKeyDraft: String?
    @State var tuyaDraft: TuyaSettings?

    let ink = LCPalette.ink
    let muted = LCPalette.muted
    let accent = LCPalette.accent

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                content
            }
        } else {
            content
        }
    }

    var content: some View {
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
                    case .about:       aboutSettings
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(ink)
        .onAppear(perform: openRequestedPage)
        .onChange(of: appState.requestedSettingsPage) { _ in openRequestedPage() }
    }

    /// Another part of the app (onboarding) asked for a specific page.
    func openRequestedPage() {
        guard let page = appState.requestedSettingsPage else { return }
        appState.requestedSettingsPage = nil
        switch page {
        case .providers: route = .providers
        }
    }

    var settingsNavigationBar: some View {
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
}

enum SettingsRoute {
    case overview, providers, tuya, hue, lifx, govee, yeelight, nanoleaf, wiz
    case automations, focus, circadian, devices, updates, about

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
        case .about:
            L10n.routeAboutSubtitle
        }
    }
}
