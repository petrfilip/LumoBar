import Foundation

/// Every UserDefaults key LumoBar writes itself (Sparkle's own keys are separate). One list, so
/// "Reset all settings" and the one-time import from LampControl cannot drift apart.
enum AppDefaultsKeys {
    static let onboardingDismissed = "LumoBar.onboarding.dismissed"
    static let roomsCollapsed = "LumoBar.rooms.collapsed"
    static let roomsMigrated = "LumoBar.rooms.migrated"
    static let scenePresetsSeeded = "LumoBar.scenes.presetsSeeded.v1"
    /// Set once the first-launch import from LampControl has run (see `LegacyImport`).
    static let legacyImportDone = "LumoBar.legacyImport.done"

    /// What "Reset all settings" removes when it cannot remove the whole defaults domain.
    /// The import marker is deliberately not here: a reset must not bring LampControl's data back.
    static let resettable = [onboardingDismissed, roomsCollapsed, roomsMigrated, scenePresetsSeeded]
}
