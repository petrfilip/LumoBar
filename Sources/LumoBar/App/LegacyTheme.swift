import SwiftUI

// MARK: - Legacy glass surfaces (liquidGlass* helpers)
//
// LampsView / SettingsView / InlineEditorForm still use these surfaces extensively. The
// macOS 13-25 fallback is layered differently from `lcCard`, so they are kept as they are
// rather than migrated (which would change how the popover looks).

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
                tint: prominent ? LCPalette.accent.opacity(0.35) : Color.white.opacity(0.08),
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

/// The few colours the glass fallback and the onboarding scrim still need. Everything else
/// that used to live here was unused (colours now come from `LCPalette`).
enum LCTheme {
    static let surfaceTop = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let surfaceMiddle = Color(nsColor: .windowBackgroundColor)
    static let surfaceBottom = Color(nsColor: .separatorColor).opacity(0.08)
    static let strokeMiddle = Color(nsColor: .separatorColor).opacity(0.26)
    static let overlayScrim = Color.black.opacity(0.28)
}
