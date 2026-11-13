import Foundation

/// When the first-run overlay shows and what it says. Pure, so it can be tested.
enum OnboardingPolicy {
    /// Shown only to users with no provider connected who have not dismissed it. It must be
    /// evaluated after *every* provider's settings are loaded: judging earlier made a
    /// Yeelight-only user look "unconfigured" on each launch.
    static func shouldPresent(hasConfiguredProvider: Bool, dismissed: Bool) -> Bool {
        !hasConfiguredProvider && !dismissed
    }

    struct Step: Equatable {
        let icon: String
        let titleKey: String
        let detailKey: String
    }

    /// Provider-agnostic: pick a provider, connect it, sync.
    static let steps: [Step] = [
        Step(icon: "square.grid.2x2", titleKey: "onboarding.step1.title", detailKey: "onboarding.step1.detail"),
        Step(icon: "link", titleKey: "onboarding.step2.title", detailKey: "onboarding.step2.detail"),
        Step(icon: "arrow.triangle.2.circlepath", titleKey: "onboarding.step3.title", detailKey: "onboarding.step3.detail")
    ]
}

/// A Settings page another part of the app asks to be shown (see `AppState.requestedSettingsPage`).
enum SettingsPage: Equatable {
    case providers
}
