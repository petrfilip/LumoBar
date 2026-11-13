import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Circadian Settings

    var circadianSettings_: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.and.horizon.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(radius: 12, tint: Color.orange.opacity(0.10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("circadian.header")
                            .font(.system(size: 13, weight: .semibold))
                        Text("circadian.detail")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("a11y.adaptive.enabled", isOn: Binding(
                        get: { appState.circadianSettings.isEnabled },
                        set: { v in Task { await appState.setAdaptiveLighting(enabled: v) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help("a11y.adaptive.enabled")
                }
                .padding(12)
                .liquidGlassSurface(radius: 16)

                HStack(spacing: 10) {
                    Toggle("circadian.brightness", isOn: circadianDraftBinding.applyBrightness)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle("circadian.temperature", isOn: circadianDraftBinding.applyTemperature)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .liquidGlassSurface(radius: 14)

                circadianSchedule

                HStack(spacing: 8) {
                    Button {
                        Task { await appState.applyCircadianNow() }
                    } label: {
                        Label("circadian.apply.now", systemImage: "sun.and.horizon")
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .liquidGlassButtonStyle(prominent: appState.circadianSettings.isEnabled)
                    // "Apply now" uses the saved schedule; Save applies the
                    // edited one immediately, so it waits for Save when dirty.
                    .disabled(!appState.circadianSettings.isEnabled || appState.isBusy || isCircadianDraftDirty)

                    Button {
                        saveCircadianDraft()
                    } label: {
                        Text("action.save")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 100, height: 38)
                    }
                    .liquidGlassButtonStyle(prominent: true)
                    .tint(accent)
                    .disabled(appState.isBusy)
                }
            }
        }
        // Unsaved edits are discarded when leaving the section: the running
        // service and the stored settings never see them.
        .onDisappear {
            circadianDraft = nil
            editingKeyframeId = nil
        }
    }

    // MARK: Adaptive lighting draft

    /// Edits to the schedule live here until Save; `nil` means no edits.
    var circadianDraftValue: CircadianSettings {
        circadianDraft ?? appState.circadianSettings
    }

    var circadianDraftBinding: Binding<CircadianSettings> {
        Binding(get: { circadianDraftValue }, set: { circadianDraft = $0 })
    }

    func mutateCircadianDraft(_ change: (inout CircadianSettings) -> Void) {
        var draft = circadianDraftValue
        change(&draft)
        circadianDraft = draft
    }

    var isCircadianDraftDirty: Bool {
        guard let draft = circadianDraft else { return false }
        return !draft.hasSameContent(as: appState.circadianSettings)
    }

    func saveCircadianDraft() {
        guard var draft = circadianDraft else {
            Task { await appState.saveCircadianSettings(appState.circadianSettings) }
            return
        }
        // The enable switch is not part of the draft (it saves on its own).
        draft.isEnabled = appState.circadianSettings.isEnabled
        Task {
            await appState.saveCircadianSettings(draft)
            if appState.circadianSettings == draft { circadianDraft = nil }
        }
    }

    // MARK: - Adaptive lighting schedule

    /// Time points of the adaptive curve. They used to be read-only rows, so
    /// nothing about the schedule could actually be configured.
    var circadianSchedule: some View {
        let settings = circadianDraftValue
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let current = settings.values(at: (now.hour ?? 0) * 60 + (now.minute ?? 0))

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("circadian.schedule")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(L10n.circadianNow(brightness: current.brightness, temperature: current.temperature))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 4)

            Text("circadian.schedule.hint")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            ForEach(settings.keyframes.sorted(by: { $0.minuteOfDay < $1.minuteOfDay })) { kf in
                circadianKeyframeRow(kf)
            }

            HStack(spacing: 8) {
                Button {
                    addCircadianKeyframe()
                } label: {
                    Label("circadian.keyframe.add", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .liquidGlassButtonStyle()
                .disabled(settings.keyframes.count >= 12)

                Button {
                    editingKeyframeId = nil
                    mutateCircadianDraft { $0.keyframes = CircadianSettings.defaultKeyframes }
                } label: {
                    Label("circadian.reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .liquidGlassButtonStyle()
            }
        }
    }

    func circadianKeyframeRow(_ kf: CircadianKeyframe) -> some View {
        let isEditing = editingKeyframeId == kf.id
        return VStack(spacing: 8) {
            Button {
                withAnimation(LCAnimation.standard) {
                    editingKeyframeId = isEditing ? nil : kf.id
                }
            } label: {
                HStack(spacing: 12) {
                    Text(L10n.clockTime(hour: kf.hour, minute: kf.minute))
                        .font(.system(size: 12, weight: .semibold).monospaced())
                        .foregroundStyle(accent)
                        .frame(width: 44, alignment: .leading)
                    Text(L10n.circadianKeyframeBrightness(kf.brightness))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LCPalette.muted)
                    Text(L10n.kelvin(kf.temperature))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LCPalette.muted)
                    Spacer()
                    Circle()
                        .fill(Color(nsColor: StatusItemIcon.kelvinColor(kf.temperature)))
                        .opacity(0.35 + 0.65 * Double(kf.brightness) / 100)
                        .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.5))
                        .frame(width: 12, height: 12)
                    Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("circadian.keyframe.edit")

            if isEditing, let binding = keyframeBinding(kf.id) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("circadian.keyframe.time")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                        Spacer()
                        DatePicker("circadian.keyframe.time", selection: keyframeTimeBinding(binding), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(width: 14)
                            .help("help.brightness")
                        Slider(value: Binding(
                            get: { Double(binding.wrappedValue.brightness) },
                            set: { binding.wrappedValue.brightness = Int($0.rounded()) }
                        ), in: 1...100)
                        Text(L10n.percent(binding.wrappedValue.brightness))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(muted)
                            .frame(width: 44, alignment: .trailing)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "thermometer.sun")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(width: 14)
                            .help("help.temperature")
                        Slider(value: Binding(
                            get: { Double(binding.wrappedValue.temperature) },
                            set: { binding.wrappedValue.temperature = Int(($0 / 100).rounded()) * 100 }
                        ), in: 1700...6500)
                        Text(L10n.kelvin(binding.wrappedValue.temperature))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(muted)
                            .frame(width: 44, alignment: .trailing)
                    }
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            editingKeyframeId = nil
                            mutateCircadianDraft { $0.keyframes.removeAll { $0.id == kf.id } }
                        } label: {
                            Label("circadian.keyframe.delete", systemImage: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LCPalette.danger)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                        }
                        .liquidGlassButtonStyle()
                        // The curve needs at least two points to interpolate.
                        .disabled(circadianDraftValue.keyframes.count <= 2)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlassSurface(radius: 12)
    }

    func keyframeBinding(_ id: UUID) -> Binding<CircadianKeyframe>? {
        guard circadianDraftValue.keyframes.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                circadianDraftValue.keyframes.first(where: { $0.id == id })
                    ?? CircadianKeyframe(hour: 0, minute: 0, brightness: 80, temperature: 4000)
            },
            set: { newValue in
                mutateCircadianDraft { draft in
                    if let index = draft.keyframes.firstIndex(where: { $0.id == id }) {
                        draft.keyframes[index] = newValue
                    }
                }
            }
        )
    }

    func keyframeTimeBinding(_ keyframe: Binding<CircadianKeyframe>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: keyframe.wrappedValue.hour,
                                      minute: keyframe.wrappedValue.minute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                keyframe.wrappedValue.hour = parts.hour ?? 0
                keyframe.wrappedValue.minute = parts.minute ?? 0
            }
        )
    }

    /// New point in the middle of the largest gap, with interpolated values.
    func addCircadianKeyframe() {
        let settings = circadianDraftValue
        let minutes = settings.keyframes.map(\.minuteOfDay).sorted()
        var target = 12 * 60
        if minutes.count >= 1 {
            var bestGap = -1
            for (index, start) in minutes.enumerated() {
                let end = index + 1 < minutes.count ? minutes[index + 1] : minutes[0] + 24 * 60
                if end - start > bestGap {
                    bestGap = end - start
                    target = (start + (end - start) / 2) % (24 * 60)
                }
            }
        }
        target = target / 15 * 15
        let values = settings.values(at: target)
        let keyframe = CircadianKeyframe(hour: target / 60, minute: target % 60,
                                         brightness: values.brightness, temperature: values.temperature)
        mutateCircadianDraft { $0.keyframes.append(keyframe) }
        editingKeyframeId = keyframe.id
    }
}
