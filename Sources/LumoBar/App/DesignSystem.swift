import SwiftUI
import AppKit

// MARK: - Spacing

/// 4pt baseline grid used across the redesign.
/// All paddings/gaps must reuse one of these constants — no magic numbers.
enum LCSpacing {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 8
    static let sm:  CGFloat = 12
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 20
}

// MARK: - Radius

enum LCRadius {
    static let button: CGFloat = 12
    static let card:   CGFloat = 16
    static let panel:  CGFloat = 20
    static let modal:  CGFloat = 24
}

// MARK: - Typography

/// All font sizes used by the redesign — SF Pro Text exclusively.
/// Use these instead of inline `.font(.system(size: ...))` calls to keep
/// vertical rhythm consistent.
enum LCTypo {
    static func title() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
    static func subtitle() -> Font {
        .system(size: 15, weight: .semibold, design: .default)
    }
    static func body() -> Font {
        .system(size: 13, weight: .regular, design: .default)
    }
    static func bodySemibold() -> Font {
        .system(size: 13, weight: .semibold, design: .default)
    }
    static func caption() -> Font {
        .system(size: 12, weight: .medium, design: .default)
    }
    static func micro() -> Font {
        .system(size: 11, weight: .medium, design: .default)
    }
    static func sectionHeader() -> Font {
        .system(size: 11, weight: .bold, design: .default)
    }
}

// MARK: - Animation

enum LCAnimation {
    /// Default for layout / size / opacity changes. Tight enough to feel snappy
    /// in a popover (bigger springs feel laggy here; the popover itself is small).
    static let standard: Animation = .spring(response: 0.28, dampingFraction: 0.86)
    /// Micro-interactions: hover, press, tab indicator.
    static let micro:    Animation = .spring(response: 0.18, dampingFraction: 0.90)
    /// Sharp, snappy spring for toggle state changes.
    static let snap:     Animation = .spring(response: 0.22, dampingFraction: 0.88)
    /// Plain fade.
    static let fade:     Animation = .easeOut(duration: 0.16)
}

// MARK: - Palette (semantic)

enum LCPalette {
    static var ink:        Color { Color.primary }
    static var muted:      Color { Color.secondary }
    static var accent:     Color { Color(nsColor: .controlAccentColor) }
    static var separator:  Color { Color(nsColor: .separatorColor).opacity(0.40) }
    static var success:    Color { Color.green.opacity(0.80) }
    static var danger:     Color { Color.red.opacity(0.80) }

    // Glass strokes
    static var strokeMid:  Color { Color.white.opacity(0.12) }
}

// MARK: - Background

/// The popover backdrop. A single base + soft accent halo. Quiet, no clutter.
///
/// PERF: minimal stack (no nested materials, no specular band overlay) so the
/// composer can rasterize this once and keep it. We previously used
/// `.drawingGroup()` here but it caches `.regularMaterial` poorly on macOS
/// 14/15 (text rendering inside the popover gets blurry shimmering).
struct LCBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)

            RadialGradient(
                colors: [
                    Color(nsColor: .controlAccentColor).opacity(0.10),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 280
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card / Chip / Button modifiers

/// Card surface — Level 1 elevation. Use on lamp rows, settings groups, etc.
///
/// PERF: on macOS < 26 we previously stacked `.regularMaterial` + tinted bg +
/// linear gradient specular overlay + linear gradient stroke border. With ~10
/// cards visible × 4 layers, that's ~40 GPU passes per frame. We now use a
/// simple `.regularMaterial` + flat tint + single solid stroke. The luxury
/// gradients stay on macOS 26+ where `.glassEffect` is GPU-accelerated.
private struct LCCardModifier: ViewModifier {
    var radius: CGFloat = LCRadius.card
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            if let tint {
                content
                    .glassEffect(.regular.tint(tint.opacity(0.30)), in: shape)
                    .contentShape(shape)
            } else {
                content
                    .glassEffect(.regular, in: shape)
                    .contentShape(shape)
            }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .background(
                    (tint ?? Color.white.opacity(0.03)),
                    in: shape
                )
                .overlay(
                    shape.strokeBorder(LCPalette.strokeMid, lineWidth: 0.5)
                )
                .contentShape(shape)
        }
    }
}

/// Chip surface — pill-shaped Level 2 element. For tags / inline pills.
private struct LCChipModifier: ViewModifier {
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)
        if #available(macOS 26.0, *) {
            if let tint {
                content
                    .glassEffect(.regular.tint(tint), in: shape)
                    .contentShape(shape)
            } else {
                content
                    .glassEffect(.regular, in: shape)
                    .contentShape(shape)
            }
        } else {
            // PERF: single material + flat tint + thin stroke.
            content
                .background(.thinMaterial, in: shape)
                .background((tint ?? Color.white.opacity(0.05)), in: shape)
                .overlay(
                    shape.strokeBorder(LCPalette.strokeMid, lineWidth: 0.5)
                )
                .contentShape(shape)
        }
    }
}

/// Hoverable wrapper: scale 1.02 + tinted glow on hover.
struct LCHoverable: ViewModifier {
    @State private var isHovering = false
    var glowTint: Color = LCPalette.accent
    var radius: CGFloat = LCRadius.card

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(glowTint.opacity(isHovering ? 0.45 : 0), lineWidth: 1)
                    .blur(radius: isHovering ? 0.8 : 0)
                    .allowsHitTesting(false)
            )
            .animation(LCAnimation.micro, value: isHovering)
            .onHover { hovering in isHovering = hovering }
    }
}

/// Press wrapper for plain Buttons — scale 0.97 while pressed.
struct LCPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(LCAnimation.micro, value: configuration.isPressed)
    }
}

// MARK: - Glass Button Style (Quiet Glass)

/// Prominent / regular glass button. Glass surface + press micro-interaction.
///
/// PERF: hover ring removed by default. The previous version embedded
/// `LCHoverable` (a `@State`-tracking modifier) inside the style, so every
/// chip / glass button on screen re-rendered on every mouse move within the
/// popover. Re-enable per-instance via `.lcHoverable()` for a few CTA buttons
/// only — never on lists.
struct LCGlassButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var radius: CGFloat = LCRadius.button

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(LCCardModifier(
                radius: radius,
                tint: prominent ? LCPalette.accent.opacity(0.45) : Color.white.opacity(0.06)
            ))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(LCAnimation.micro, value: configuration.isPressed)
    }
}

// MARK: - View extensions

extension View {
    /// Apply the Quiet Glass card surface (Level 1).
    func lcCard(radius: CGFloat = LCRadius.card, tint: Color? = nil) -> some View {
        modifier(LCCardModifier(radius: radius, tint: tint))
    }

    /// Apply a pill-shaped chip surface.
    func lcChip(tint: Color? = nil) -> some View {
        modifier(LCChipModifier(tint: tint))
    }

    /// Apply hoverable feedback: scale + glow.
    func lcHoverable(glowTint: Color = LCPalette.accent, radius: CGFloat = LCRadius.card) -> some View {
        modifier(LCHoverable(glowTint: glowTint, radius: radius))
    }

    /// Wrap children in a glass-effect container on macOS 26+, otherwise pass-through.
    @ViewBuilder
    func lcGlassGroup(spacing: CGFloat = LCSpacing.sm) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// Names an icon-only control for VoiceOver and gives it a tooltip.
    func lcIconLabel(_ key: LocalizedStringKey) -> some View {
        self
            .accessibilityLabel(Text(key))
            .help(key)
    }

    /// Soft shadow used by overlays (for overlays and modals).
    func lcOverlayShadow() -> some View {
        shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 8)
    }

    /// Convenience for letter-spaced large titles.
    func lcTrackedTitle() -> some View {
        kerning(-0.2)
    }
}

// MARK: - Symbol effect helpers (macOS 14+ guard)

/// Apply a "bounce" symbol effect when supported (macOS 14+).
/// On macOS 13 this is a no-op.
struct LCBounceSymbol<V: Equatable>: ViewModifier {
    let value: V
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}

extension View {
    func lcBounceSymbol<V: Equatable>(value: V) -> some View {
        modifier(LCBounceSymbol(value: value))
    }
}

// MARK: - Reusable mini components

/// Iconic circle badge — used in headers and empty states.
struct LCIconBadge: View {
    let systemName: String
    var size: CGFloat = 36
    var tint: Color = LCPalette.accent
    var fontSize: CGFloat = 16

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .lcCard(radius: size / 2, tint: tint.opacity(0.18))
    }
}

/// Small pulsing status dot.
/// PERF: when `animated == false`, no animation modifier is attached at all, so
/// SwiftUI does not register a recurring tick on every visible dot.
struct LCStatusDot: View {
    var color: Color = LCPalette.accent
    var animated: Bool = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.85)).frame(width: 6, height: 6)
            if animated {
                PulsingRing(color: color)
            }
        }
        .frame(width: 12, height: 12)
    }
}

/// Isolated subview so the `repeatForever` animation is created only when the dot
/// is actually animated, and torn down cleanly when it disappears.
private struct PulsingRing: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.5), lineWidth: 1.5)
            .frame(width: 6, height: 6)
            .scaleEffect(animate ? 2.4 : 1.0)
            .opacity(animate ? 0 : 0.8)
            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: animate)
            .onAppear { animate = true }
    }
}

/// Section header used by Lamps room groups & Settings groups.
struct LCSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(LCTypo.sectionHeader())
            .tracking(0.5)
            .foregroundStyle(LCPalette.muted)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, LCSpacing.xs)
            .padding(.horizontal, LCSpacing.xs)
    }
}

/// Empty-state card used by Lamps view, Onboarding, etc.
struct LCEmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var cta: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: LCSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(LCPalette.muted)
                .frame(width: 56, height: 56)
                .lcCard(radius: 28, tint: LCPalette.accent.opacity(0.10))

            Text(title)
                .font(LCTypo.subtitle())
                .foregroundStyle(LCPalette.ink)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(LCTypo.caption())
                .foregroundStyle(LCPalette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let cta, let action {
                Button(action: action) {
                    Text(cta)
                        .font(LCTypo.bodySemibold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(LCGlassButtonStyle(prominent: true, radius: LCRadius.button))
                .padding(.top, LCSpacing.xs)
            }
        }
        .padding(LCSpacing.lg)
        .frame(maxWidth: .infinity)
        .lcCard(radius: LCRadius.panel)
    }
}
