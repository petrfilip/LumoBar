import AppKit
import SwiftUI

extension SettingsView {
    var updatesSettings: some View {
        UpdateServiceObserver(service: appState.updateService) { service, bindable in
            updatesContent(service, bindable)
        }
    }

    func updatesContent(_ service: UpdateService, _ bindable: ObservedObject<UpdateService>.Wrapper) -> some View {
        VStack(spacing: 12) {
            if !service.isAvailable {
                hintText(NSLocalizedString("updates.unavailable", comment: ""))
            }

            settingsGroup {
                toggleRow(
                    title: "updates.auto.check",
                    subtitle: "updates.auto.check.detail",
                    isOn: bindable.automaticChecksEnabled
                )
                .disabled(!service.isAvailable)
                .opacity(service.isAvailable ? 1 : 0.5)

                toggleRow(
                    title: "updates.auto.install",
                    subtitle: "updates.auto.install.detail",
                    isOn: bindable.automaticDownloadsEnabled
                )
                .disabled(!service.automaticChecksEnabled)
                .opacity(service.automaticChecksEnabled ? 1 : 0.5)

                infoRow("updates.current.version", value: L10n.aboutVersionValue(version: service.currentVersion, build: service.currentBuild), icon: "number")
            }

            Button {
                service.checkForUpdates()
            } label: {
                Label("updates.check.now", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle(prominent: true)
            .tint(accent)
            .disabled(!service.canCheckForUpdates)
            .opacity(service.canCheckForUpdates ? 1 : 0.55)

            if let date = service.lastCheckedAt {
                hintText(L10n.updatesLastCheck(date.formatted(date: .abbreviated, time: .shortened)))
            }
        }
    }
}

/// Observes the update service directly: `AppState` only holds it, and a nested
/// `ObservableObject` does not forward its changes, so the page would not refresh on its own.
private struct UpdateServiceObserver<Content: View>: View {
    @ObservedObject var service: UpdateService
    @ViewBuilder let content: (UpdateService, ObservedObject<UpdateService>.Wrapper) -> Content

    var body: some View {
        content(service, $service)
    }
}
