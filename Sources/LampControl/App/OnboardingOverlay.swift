import SwiftUI

struct OnboardingOverlay: View {
    @EnvironmentObject private var appState: AppState
    @State private var stepIndex: Int = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "lightbulb.led",
            tint: .yellow,
            titleKey: "onboarding.step1.title",
            detailKey: "onboarding.step1.detail"
        ),
        OnboardingStep(
            icon: "wand.and.stars",
            tint: .pink,
            titleKey: "onboarding.step2.title",
            detailKey: "onboarding.step2.detail"
        ),
        OnboardingStep(
            icon: "keyboard",
            tint: .blue,
            titleKey: "onboarding.step3.title",
            detailKey: "onboarding.step3.detail"
        )
    ]

    var body: some View {
        ZStack {
            LCTheme.overlayScrim
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(LCAnimation.standard) {
                        appState.dismissOnboarding()
                    }
                }

            VStack(spacing: LCSpacing.md) {
                header

                stepView(steps[stepIndex])
                    .id(stepIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                dots

                actions
            }
            .padding(LCSpacing.lg)
            .frame(maxWidth: 340)
            .lcCard(radius: LCRadius.modal, tint: Color.white.opacity(0.05))
            .lcOverlayShadow()

            // Hidden escape-to-dismiss button
            Button("onboarding.close") { appState.dismissOnboarding() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: LCSpacing.sm) {
            LCIconBadge(systemName: "sparkles", size: 36, tint: LCPalette.accent, fontSize: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("onboarding.title")
                    .font(LCTypo.title())
                    .lcTrackedTitle()
                Text("onboarding.subtitle")
                    .font(LCTypo.micro())
                    .foregroundStyle(LCPalette.muted)
            }
            Spacer()
        }
    }

    // MARK: - Step body

    private func stepView(_ step: OnboardingStep) -> some View {
        VStack(spacing: LCSpacing.sm) {
            Image(systemName: step.icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(step.tint)
                .frame(width: 72, height: 72)
                .lcCard(radius: 36, tint: step.tint.opacity(0.18))

            Text(step.titleKey)
                .font(LCTypo.subtitle())
                .multilineTextAlignment(.center)

            Text(step.detailKey)
                .font(LCTypo.caption())
                .foregroundStyle(LCPalette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, LCSpacing.sm)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dots

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { idx in
                let active = idx == stepIndex
                Capsule()
                    .fill(active ? LCPalette.accent : LCPalette.muted.opacity(0.35))
                    .frame(width: active ? 18 : 6, height: 6)
                    .animation(LCAnimation.snap, value: stepIndex)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: LCSpacing.xs) {
            if stepIndex > 0 {
                Button {
                    withAnimation(LCAnimation.standard) {
                        stepIndex -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LCPalette.muted)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(LCGlassButtonStyle(prominent: false, radius: 19))
                .help("help.onboarding.back")
            }

            if stepIndex < steps.count - 1 {
                Button {
                    withAnimation(LCAnimation.standard) {
                        stepIndex += 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("onboarding.next")
                            .font(LCTypo.bodySemibold())
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(LCGlassButtonStyle(prominent: true, radius: 19))
            } else {
                Button {
                    appState.openOnboardingSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill").font(.system(size: 11, weight: .bold))
                        Text("onboarding.configure").font(LCTypo.bodySemibold())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(LCGlassButtonStyle(prominent: true, radius: 19))
            }

            Button {
                appState.dismissOnboarding()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LCPalette.muted)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(LCGlassButtonStyle(prominent: false, radius: 19))
            .help("onboarding.dismiss")
        }
    }
}

private struct OnboardingStep {
    let icon: String
    let tint: Color
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
}
