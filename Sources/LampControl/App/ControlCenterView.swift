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
                .lineLimit(2)
            Spacer(minLength: 0)
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

// MARK: - Backwards-compatible LCTheme + liquidGlass helpers
//
// Existing LampsView / SettingsView / OnboardingOverlay still use these
// surfaces extensively. We keep them — they now layer on top of the
// new DesignSystem visuals and continue to work the same way.

extension View {
    /// Apply a Liquid Glass surface.
    /// - On macOS 26+ uses the real `.glassEffect` API.
    /// - On macOS 13–25 falls back to a layered translucent material.
    @ViewBuilder
    func liquidGlassSurface(radius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            self
                .modifier(NativeGlassEffectModifier(shape: shape, tint: tint, interactive: interactive))
                .contentShape(shape)
        } else {
            self
                .fallbackGlassSurface(radius: radius, tint: tint)
                .contentShape(shape)
        }
    }

    @ViewBuilder
    func liquidGlassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self
                .modifier(NativeGlassEffectModifier(shape: Circle(), tint: tint, interactive: interactive))
                .contentShape(Circle())
        } else {
            self
                .fallbackGlassSurface(radius: 999, tint: tint)
                .contentShape(Circle())
        }
    }

    fileprivate func fallbackGlassSurface(radius: CGFloat, tint: Color?) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .background(
                LinearGradient(
                    colors: [
                        LCTheme.surfaceTop,
                        (tint ?? LCTheme.surfaceMiddle).opacity(0.22),
                        LCTheme.surfaceBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: shape
            )
            .background(
                Group {
                    if let tint {
                        shape.fill(tint)
                    } else {
                        Color.clear
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                LCTheme.strokeMiddle,
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }

    @ViewBuilder
    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        self
            .buttonStyle(.plain)
            // Plain buttons only hit-test the label's opaque pixels; without this
            // a small glyph in a larger frame (e.g. the scene editor's ✕) only
            // reacted when clicking exactly on the glyph.
            .contentShape(RoundedRectangle(cornerRadius: prominent ? 18 : 13, style: .continuous))
            .liquidGlassSurface(
                radius: prominent ? 18 : 13,
                tint: prominent ? LCTheme.accent.opacity(0.35) : Color.white.opacity(0.08),
                interactive: true
            )
    }
}

@available(macOS 26.0, *)
private struct NativeGlassEffectModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if let tint, interactive {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else if let tint {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else if interactive {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

enum LCTheme {
    static let ink = Color.primary
    static let muted = Color.secondary
    static let accent = Color(nsColor: .controlAccentColor)
    static let softAccent = Color(nsColor: .separatorColor)

    static let backgroundTop = Color(nsColor: .windowBackgroundColor).opacity(0.96)
    static let backgroundMiddle = Color(nsColor: .controlBackgroundColor).opacity(0.90)
    static let backgroundBottom = Color(nsColor: .underPageBackgroundColor).opacity(0.92)
    static let glassHighlight = Color(nsColor: .highlightColor).opacity(0.26)
    static let sideHighlight = Color(nsColor: .highlightColor).opacity(0.18)
    static let backgroundShade = Color.black.opacity(0.05)

    static let surfaceTop = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let surfaceMiddle = Color(nsColor: .windowBackgroundColor)
    static let surfaceBottom = Color(nsColor: .separatorColor).opacity(0.08)
    static let strokeTop = Color(nsColor: .highlightColor).opacity(0.62)
    static let strokeMiddle = Color(nsColor: .separatorColor).opacity(0.26)
    static let strokeBottom = Color.black.opacity(0.06)
    static let overlayScrim = Color.black.opacity(0.28)

    static let success = Color.green.opacity(0.80)
    static let error = Color.red.opacity(0.80)
    static let errorSurface = Color.red.opacity(0.10)
    static let infoSurface = Color.blue.opacity(0.08)
}
