import AppKit
import SwiftUI

extension SettingsView {
    var providersSettings: some View {
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

    func providerRow(_ provider: LightProviderKind, isConfigured: Bool) -> some View {
        Button {
            withAnimation(LCAnimation.snap) {
                route = route(for: provider)
            }
        } label: {
            HStack(spacing: LCSpacing.sm) {
                Image(systemName: providerIcon(provider))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isConfigured ? Color.green.opacity(0.85) : accent)
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

    func providerIcon(_ provider: LightProviderKind) -> String {
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

    func providerSubtitle(_ provider: LightProviderKind, isConfigured: Bool) -> String {
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

    func route(for provider: LightProviderKind) -> SettingsRoute {
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

    func disconnectButton(_ kind: LightProviderKind) -> some View {
        Button(role: .destructive) {
            Task { await appState.disconnectProvider(kind) }
        } label: {
            Label("provider.disconnect", systemImage: "minus.circle")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .liquidGlassButtonStyle()
        .help("help.provider.disconnect")
        .disabled(appState.isBusy)
    }
}
