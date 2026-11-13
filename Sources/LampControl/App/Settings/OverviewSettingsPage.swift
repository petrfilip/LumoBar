import AppKit
import SwiftUI

extension SettingsView {
    var overview: some View {
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

    /// Overview status: any configured provider counts. (The Tuya-specific
    /// step summary used to sit here and reported "setup incomplete" to users
    /// of every other vendor; it now lives in the Tuya section.)
    var providersSummary: some View {
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

    /// Same look as `settingsLink`, with a "Restore" button instead of the chevron.
    var restoreScenesRow: some View {
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
                if confirmingSceneRestore {
                    Text(L10n.scenesRestoreConfirm)
                        .font(LCTypo.micro())
                        .foregroundStyle(ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("settings.scenes.restore.detail")
                        .font(LCTypo.micro())
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            if confirmingSceneRestore {
                VStack(spacing: 4) {
                    Button(L10n.scenesRestoreButton) {
                        confirmingSceneRestore = false
                        appState.restoreDefaultScenes()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .liquidGlassButtonStyle(prominent: true)

                    Button(L10n.cancel) { confirmingSceneRestore = false }
                        .font(.system(size: 11, weight: .semibold))
                        .liquidGlassButtonStyle()
                        .keyboardShortcut(.cancelAction)
                }
            } else {
                Button("settings.scenes.restore.button") {
                    confirmingSceneRestore = true
                }
                .font(.system(size: 11, weight: .semibold))
                .liquidGlassButtonStyle()
                .help("help.scenes.restore")
            }
        }
        .padding(.horizontal, LCSpacing.sm)
        .padding(.vertical, confirmingSceneRestore ? LCSpacing.xs : 0)
        .frame(minHeight: 60)
        .lcCard(radius: LCRadius.card, tint: Color.white.opacity(0.04))
    }

    /// Same look as `settingsLink`, with a switch instead of the chevron.
    var launchAtLoginRow: some View {
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

    func settingsLink(_ route: SettingsRoute, icon: String, title: String, subtitle: String, tint: Color) -> some View {
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
}
