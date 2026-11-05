import SwiftUI

struct PremiumSettingsView: View {
    @EnvironmentObject private var appState: AppState
    let licenseState: LicenseState
    @State private var licenseKey: String = ""
    @State private var customerEmail: String = ""
    @State private var showingActivationForm = false

    var body: some View {
        VStack(spacing: LCSpacing.sm) {
            VStack(spacing: LCSpacing.sm) {
                header
                infoRow("premium.lamps",
                        value: licenseState.entitlements.maxLamps.map { "\($0) max" } ?? NSLocalizedString("premium.lamps.unlimited", comment: ""),
                        icon: "lightbulb.2")
                premiumFeatureRow("premium.groups",        isEnabled: licenseState.entitlements.canUseGroups)
                premiumFeatureRow("premium.custom.scenes", isEnabled: licenseState.entitlements.canUseCustomScenes)
                premiumFeatureRow("premium.quick.ambiances", isEnabled: licenseState.entitlements.canUseScenePresets)
            }
            .padding(LCSpacing.md)
            .lcCard(radius: LCRadius.panel)

            activationCard

            earlyAccessNote
        }
    }

    private var header: some View {
        HStack(spacing: LCSpacing.sm) {
            LCIconBadge(systemName: "crown.fill", size: 40, tint: .yellow, fontSize: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(licenseState.tier.title)
                    .font(LCTypo.subtitle())
                    .lcTrackedTitle()
                Text(licenseState.statusText)
                    .font(LCTypo.micro())
                    .foregroundStyle(LCPalette.muted)
            }

            Spacer()

            if licenseState.tier == .premium {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LCPalette.success)
            }
        }
    }

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("premium.license")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text(LicenseProviderConfig.providerName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LCTheme.muted)
            }

            if licenseState.tier == .premium {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("premium.active")
                                .font(.system(size: 12, weight: .semibold))

                            if let instanceName = licenseState.instanceName {
                                Text(instanceName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(LCTheme.muted)
                            } else {
                                Text(licenseState.maskedLicenseKey)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(LCTheme.muted)
                            }
                        }

                        Spacer()
                    }

                    if let instanceName = licenseState.instanceName {
                        Text("Instance: \(instanceName)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(LCTheme.muted)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await appState.validateLicense() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .frame(width: 36, height: 36)
                    }
                    .disabled(appState.isBusy)
                    .liquidGlassButtonStyle()
                    .help("help.license.refresh")

                    Button {
                        Task { await appState.deactivateLicense() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 36, height: 36)
                    }
                    .disabled(appState.isBusy)
                    .liquidGlassButtonStyle()
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("premium.license.hint")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LCTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("premium.license.key", text: $licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()

                    TextField("premium.license.email", text: $customerEmail)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, weight: .medium))
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await appState.activateLicense(licenseKey, email: customerEmail) }
                        licenseKey = ""
                        customerEmail = ""
                    } label: {
                        Label("premium.activate", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .disabled(appState.isBusy || licenseKey.isEmpty)
                    .liquidGlassButtonStyle(prominent: true)

                    Button {
                        Task { await appState.validateLicense() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .frame(width: 36, height: 36)
                    }
                    .disabled(appState.isBusy)
                    .liquidGlassButtonStyle()
                    .help("help.license.refresh")
                }
            }
        }
        .padding(LCSpacing.md)
        .lcCard(radius: LCRadius.panel)
    }

    private var earlyAccessNote: some View {
        Text("premium.early.access.hint")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(LCTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func infoRow(_ titleKey: LocalizedStringKey, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LCTheme.accent)
                .frame(width: 28, height: 28)
                .liquidGlassSurface(radius: 10)

            Text(titleKey)
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LCTheme.muted)
                .lineLimit(1)
        }
    }

    private func premiumFeatureRow(_ titleKey: LocalizedStringKey, isEnabled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isEnabled ? "checkmark.seal.fill" : "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.green : LCTheme.muted)
                .frame(width: 28, height: 28)
                .liquidGlassSurface(radius: 10, tint: isEnabled ? Color.green.opacity(0.08) : nil)

            Text(titleKey)
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Text(isEnabled ? "premium.active" : "premium.locked")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LCTheme.muted)
        }
    }
}
