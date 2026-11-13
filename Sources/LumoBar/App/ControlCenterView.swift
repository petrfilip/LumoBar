import SwiftUI

struct ControlCenterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LCBackdrop()

            content
                .lcGlassGroup(spacing: LCSpacing.sm)

            if appState.isOnboardingPresented {
                OnboardingOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }
        }
        .frame(width: appState.preferredPopoverSize.width, height: appState.preferredPopoverSize.height)
        .foregroundStyle(LCPalette.ink)
        .animation(LCAnimation.standard, value: appState.isOnboardingPresented)
    }

    // MARK: - Layout

    private var content: some View {
        VStack(spacing: 0) {
            // Sticky chrome — opaque so scrolling content can't bleed through.
            // We layer a window-coloured fill UNDER the regular material so dark
            // mode does not stay translucent against the popover backdrop.
            VStack(spacing: LCSpacing.xs) {
                header
                    .padding(.horizontal, LCSpacing.lg)
                    .padding(.top, LCSpacing.md)
                    .padding(.bottom, LCSpacing.sm)
            }
            .background(
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Rectangle().fill(.regularMaterial)
                }
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LCPalette.separator)
                    .frame(height: 0.5)
            }
            .zIndex(1)

            // Scrollable content area gets all remaining vertical space.
            Group {
                switch appState.selectedTab {
                case .lamps:    LampsView()
                case .settings: SettingsView()
                }
            }
            .padding(.horizontal, LCSpacing.md)
            .padding(.top, LCSpacing.sm)
            .padding(.bottom, LCSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)
            .clipped()
            // The banner floats over the content instead of living in the header: inserting it
            // there grew the header and shoved every lamp row down (then back up when it
            // auto-dismissed), which read as the whole list flickering on each action.
            .overlay(alignment: .top) {
                if !appState.message.isEmpty {
                    messageBanner
                        .padding(.horizontal, LCSpacing.lg)
                        .padding(.top, LCSpacing.xs)
                        .transition(.opacity)
                }
            }
            .animation(LCAnimation.fade, value: appState.message.isEmpty)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: LCSpacing.sm) {
            LCIconBadge(systemName: "lightbulb.led",
                        size: 36,
                        tint: LCPalette.accent,
                        fontSize: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(LCTypo.title())
                    .lcTrackedTitle()
                    .foregroundStyle(LCPalette.ink)

                HStack(spacing: LCSpacing.xxs) {
                    LCStatusDot(color: appState.canSync ? Color.blue : LCPalette.muted,
                                animated: appState.isAutoSyncing)
                    Text(headerStatus)
                        .font(LCTypo.micro())
                        .foregroundStyle(LCPalette.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: LCSpacing.xs)

            // Adaptive lighting on/off — moved here from the tiny icon in
            // the lamps status bar, where it was easy to miss.
            circleIconButton(
                icon: appState.circadianSettings.isEnabled ? "sun.and.horizon.fill" : "sun.and.horizon",
                help: appState.circadianSettings.isEnabled ? "lamps.adaptive.disable" : "lamps.adaptive.enable",
                tint: appState.circadianSettings.isEnabled ? Color.orange : nil
            ) {
                Task { await appState.setAdaptiveLighting(enabled: !appState.circadianSettings.isEnabled) }
            }
            .disabled(appState.isBusy)

            circleIconButton(
                icon: appState.selectedTab == .settings ? "lightbulb.2" : "gearshape",
                help: appState.selectedTab == .settings ? "tab.lamps" : "settings.title"
            ) {
                appState.selectedTab = appState.selectedTab == .settings ? .lamps : .settings
            }

            // Closes the popover only; quitting lives in the status-item
            // right-click menu and in Settings → About.
            circleIconButton(icon: "xmark", help: "app.close") { appState.closePopover?() }
        }
        .frame(height: 56)
    }

    private var headerTitle: LocalizedStringKey {
        appState.selectedTab == .settings ? "settings.title" : "LumoBar"
    }

    private func circleIconButton(icon: String,
                                  help: LocalizedStringKey,
                                  tint: Color? = nil,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint ?? LCPalette.muted)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(LCGlassButtonStyle(prominent: false, radius: 16))
        .help(help)
    }

    // MARK: - Message banner

    private var messageBanner: some View {
        HStack(spacing: LCSpacing.xs) {
            Image(systemName: isErrorMessage ? "exclamationmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isErrorMessage ? LCPalette.danger : LCPalette.accent)
            Text(appState.message)
                .font(LCTypo.caption())
                .foregroundStyle(LCPalette.ink)
                .lineLimit(isErrorMessage ? 3 : 2)
            Spacer(minLength: 0)
            Button {
                appState.dismissMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LCPalette.muted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LCPressableButtonStyle())
            .lcIconLabel("banner.dismiss")
        }
        .padding(.horizontal, LCSpacing.sm)
        .padding(.vertical, LCSpacing.xs + 2)
        .lcCard(radius: LCRadius.button,
                tint: isErrorMessage
                    ? LCPalette.danger.opacity(0.12)
                    : LCPalette.accent.opacity(0.10))
    }

    // MARK: - Derived

    /// Connected providers (e.g. "Yeelight"). Used to say "Cloud active" for
    /// any provider — a leftover from the Tuya-only days, misleading for
    /// local-network vendors such as Yeelight or WiZ.
    private var headerStatus: String {
        let providers = appState.configuredProviderKinds
        guard !providers.isEmpty else { return NSLocalizedString("config.required", comment: "") }
        return providers.map(\.title).joined(separator: " · ")
    }

    /// Set explicitly by AppState (`showError`) — guessing from French/English
    /// keywords in the text broke as soon as messages were localized.
    private var isErrorMessage: Bool {
        appState.messageIsError
    }
}
