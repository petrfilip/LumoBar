import AppKit
import SwiftUI

extension SettingsView {
    func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .padding(14)
        .liquidGlassSurface(radius: 22)
    }

    func formField(_ titleKey: LocalizedStringKey, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(titleKey, icon: icon)

            TextField(titleKey, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(ink)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 38)
                .liquidGlassSurface(radius: 13, tint: Color.white.opacity(0.08), interactive: true)
        }
    }

    func fieldLabel(_ titleKey: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(titleKey)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(muted)
    }

    func toggleRow(title: LocalizedStringKey, subtitle: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(muted)
            }
        }
        .toggleStyle(.switch)
        .tint(accent)
    }

    func infoRow(_ titleKey: LocalizedStringKey, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .liquidGlassSurface(radius: 10)

            Text(titleKey)
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted)
                .lineLimit(1)
        }
    }

    func hint(_ textKey: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(accent)
                .padding(.top, 1)
            Text(textKey)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
    }

    func hintText(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(accent)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
