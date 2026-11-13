import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Automations Settings

    var automationsSettings: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: Color.green.opacity(0.10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("automations.header")
                            .font(.system(size: 13, weight: .semibold))
                        Text("automations.header.detail")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(12)
                .liquidGlassSurface(radius: 16)

                if appState.automations.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.badge.xmark")
                            .foregroundStyle(muted)
                            .frame(width: 24, height: 24)
                        Text("automations.empty.message")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                        Spacer()
                    }
                    .padding(12)
                    .liquidGlassSurface(radius: 14)
                } else {
                    ForEach(appState.automations) { automation in
                        HStack(spacing: 10) {
                            Image(systemName: automation.action.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(automation.isEnabled ? accent : muted)
                                .frame(width: 28, height: 28)
                                .liquidGlassSurface(radius: 10, tint: automation.isEnabled ? accent.opacity(0.10) : nil)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(automation.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ink)
                                Text("\(automation.timeString) · \(automation.weekdaysLabel)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(muted)
                            }

                            Spacer()

                            Toggle("a11y.automation.enabled", isOn: Binding(
                                get: { automation.isEnabled },
                                set: { _ in appState.toggleAutomation(automation) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .scaleEffect(0.8)
                            .help("a11y.automation.enabled")

                            Button {
                                appState.deleteAutomation(automation)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.red)
                                    .frame(width: 26, height: 26)
                            }
                            .liquidGlassButtonStyle()
                            .help("help.automation.delete")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .liquidGlassSurface(radius: 14)
                    }
                }

                if isAddingAutomation {
                    AutomationEditor(isPresented: $isAddingAutomation) { automation in
                        appState.saveAutomation(automation)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !isAddingAutomation {
                    Button { isAddingAutomation = true } label: {
                        Label("automations.new", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .liquidGlassButtonStyle(prominent: true)
                    .disabled(appState.isBusy)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isAddingAutomation)
        }
    }
}

// MARK: - AutomationEditor

private struct AutomationEditor: View {
    @Binding var isPresented: Bool
    var onSave: (Automation) -> Void

    @State private var name = ""
    @State private var hour = 22
    @State private var minute = 0
    @State private var action: AutomationAction = .powerOffAll
    @State private var weekdays = Set<Int>()

    private let actions: [AutomationAction] = [
        .powerOffAll, .powerOnAll,
        .applyScenePreset(id: "focus"), .applyScenePreset(id: "relax"),
        .applyScenePreset(id: "neon"),  .applyScenePreset(id: "night"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            TextField("automation.name.placeholder", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .frame(height: 34)
                .liquidGlassSurface(radius: 12, tint: Color.white.opacity(0.06), interactive: true)

            HStack(spacing: 8) {
                Stepper(value: $hour, in: 0...23) {
                    Text(L10n.hourShort(hour))
                        .font(.system(size: 12, weight: .semibold).monospaced())
                        .frame(width: 52)
                }
                Stepper(value: $minute, in: 0...59, step: 5) {
                    Text(L10n.minuteShort(minute))
                        .font(.system(size: 12, weight: .semibold).monospaced())
                        .frame(width: 52)
                }
            }

            Picker("a11y.automation.action", selection: $action) {
                ForEach(actions, id: \.title) { a in
                    Label(a.title, systemImage: a.icon).tag(a)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .help("a11y.automation.action")
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .liquidGlassSurface(radius: 12, tint: Color.white.opacity(0.06))

            HStack(spacing: 6) {
                Text("automation.days")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LCPalette.muted)
                ForEach(1...7, id: \.self) { day in
                    Button {
                        if weekdays.contains(day) { weekdays.remove(day) }
                        else { weekdays.insert(day) }
                    } label: {
                        Text(L10n.dayLetters[safe: day - 1] ?? "")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(weekdays.contains(day) ? Color.white : LCPalette.muted)
                            .frame(width: 24, height: 24)
                            .liquidGlassCircle(tint: weekdays.contains(day) ? LCPalette.accent.opacity(0.50) : nil)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    let a = Automation(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? action.title : name.trimmingCharacters(in: .whitespacesAndNewlines),
                        hour: hour, minute: minute,
                        weekdays: weekdays, action: action
                    )
                    onSave(a)
                    isPresented = false
                } label: {
                    Label("automation.create", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .liquidGlassButtonStyle(prominent: true)

                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .liquidGlassButtonStyle()
                .help("app.close")
                .foregroundStyle(LCPalette.muted)
            }
        }
        .padding(12)
        .liquidGlassSurface(radius: 18, tint: Color.white.opacity(0.05))
    }
}
