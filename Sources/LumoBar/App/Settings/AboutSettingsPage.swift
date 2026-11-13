import AppKit
import SwiftUI

extension SettingsView {
    var aboutSettings: some View {
        VStack(spacing: 12) {
            settingsGroup {
                infoRow("about.app",     value: "LumoBar", icon: "lightbulb.led")
                infoRow("about.version", value: L10n.aboutVersionValue(version: appState.updateService.currentVersion, build: appState.updateService.currentBuild), icon: "shippingbox")
                infoRow("about.storage", value: NSLocalizedString("about.storage.value", comment: ""), icon: "lock.square")
            }

            Button {
                appState.openConfigurationGuide()
            } label: {
                Label("about.config.guide", systemImage: "book")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle()

            Button {
                confirmAndResetAllSettings()
            } label: {
                Label("settings.reset.button", systemImage: "arrow.counterclockwise.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LCPalette.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle()

            Button {
                appState.quit()
            } label: {
                Label("app.quit", systemImage: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LCPalette.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle()
        }
    }

    /// A native modal alert: always reliably presented from the menu-bar
    /// popover (SwiftUI alerts/sheets attach to the popover window, which is
    /// fragile). The popover may close while the alert is up; that is fine.
    func confirmAndResetAllSettings() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = NSLocalizedString("settings.reset.confirm.title", comment: "")
        alert.informativeText = NSLocalizedString("settings.reset.confirm.message", comment: "")
        let reset = alert.addButton(withTitle: NSLocalizedString("settings.reset.confirm.action", comment: ""))
        reset.hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("settings.reset.confirm.cancel", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            appState.resetAllSettings()
        }
    }
}
