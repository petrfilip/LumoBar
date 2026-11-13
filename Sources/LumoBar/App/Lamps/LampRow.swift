import SwiftUI
import AppKit

/// A row is a pure function of its value inputs, so `.equatable()` lets SwiftUI skip it when
/// none changed (every `AppState` publish used to re-render all rows). `appState` is only
/// used to perform actions and is deliberately not observed: it is one stable object, so it
/// takes no part in `==`.
struct LampRow: View, Equatable {
    let appState: AppState
    let lamp: LampDevice
    let isSelected: Bool
    let isExpanded: Bool
    let showsGroupControls: Bool
    @State private var showingFeedback = false

    static func == (lhs: LampRow, rhs: LampRow) -> Bool {
        lhs.lamp == rhs.lamp
            && lhs.isSelected == rhs.isSelected
            && lhs.isExpanded == rhs.isExpanded
            && lhs.showsGroupControls == rhs.showsGroupControls
            && lhs.appState === rhs.appState
    }

    private let ink = LCPalette.ink
    private let muted = LCPalette.muted
    private let accent = LCPalette.accent

    var body: some View {
        VStack(spacing: showsAdvancedControls ? 10 : 0) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        let success = await appState.toggle(lamp)
                        guard success else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingFeedback = true
                        }
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingFeedback = false
                        }
                    }
                } label: {
                    ZStack {
                        rowSummary
                        if showingFeedback {
                            VStack(spacing: 9) {
                                Spacer()
                                HStack(spacing: 9) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.green)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 9)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!lamp.online)
                .opacity(lamp.online ? 1 : 0.52)
                .help("lamps.toggle.power")

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        appState.toggleAdvancedControls(for: lamp)
                    }
                } label: {
                    Image(systemName: showsAdvancedControls ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(muted)
                        .frame(width: 30, height: 30)
                        .liquidGlassCircle(interactive: true)
                }
                .buttonStyle(.plain)
                .help(showsAdvancedControls ? "lamps.hide.options" : "lamps.show.options")
            }

            if showsAdvancedControls {
                advancedControls
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, LCSpacing.sm)
        .padding(.vertical, showsAdvancedControls ? LCSpacing.sm : LCSpacing.xs + 2)
        .background(alignment: .top) {
            if lamp.power {
                Rectangle()
                    .fill(displayColor ?? Color(red: 0.96, green: 0.77, blue: 0.26))
                    .frame(height: 2)
                    .clipShape(Capsule())
                    .shadow(color: (displayColor ?? Color.orange).opacity(0.55), radius: 4, y: 0)
                    .padding(.horizontal, LCSpacing.md)
            }
        }
        .lcCard(radius: LCRadius.card, tint: lamp.power ? Color.white.opacity(0.10) : nil)
        .overlay(
            RoundedRectangle(cornerRadius: LCRadius.card, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? LCPalette.accent.opacity(0.85)
                        : Color.clear,
                    lineWidth: isSelected ? 1.5 : 0
                )
        )
        .animation(LCAnimation.standard, value: showsAdvancedControls)
    }

    private var showsAdvancedControls: Bool {
        isExpanded
    }

    private var rowSummary: some View {
        HStack(spacing: LCSpacing.sm) {
            ZStack {
                Image(systemName: lamp.power ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(lamp.power ? Color(red: 0.98, green: 0.72, blue: 0.20) : muted.opacity(0.70))
                    .lcBounceSymbol(value: lamp.power)
            }
            .frame(width: 32, height: 32)
            .lcCard(radius: 16, tint: lamp.power ? Color.yellow.opacity(0.18) : Color.white.opacity(0.05))

            VStack(alignment: .leading, spacing: 2) {
                Text(lamp.name)
                    .font(LCTypo.bodySemibold())
                    .foregroundStyle(ink)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    LCStatusDot(
                        color: lamp.online
                            ? (lamp.power ? Color.blue : LCPalette.muted)
                            : LCPalette.danger,
                        animated: false
                    )
                    .frame(width: 8, height: 8)
                    Text(compactStatus)
                        .font(LCTypo.micro())
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: LCSpacing.xs)

            if lamp.capabilities.colorCode != nil, let color = displayColor {
                ColorSwatch(fill: color, size: 20)
            }

            if let brightness = brightnessCapability {
                Text("\(brightnessPercentage(for: brightness))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(lamp.power ? ink : muted)
                    .frame(width: 40, alignment: .trailing)
            } else if let temperature = temperatureCapability {
                Text("\(temperaturePercentage(for: temperature))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(lamp.power ? ink : muted)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var advancedControls: some View {
        VStack(spacing: 9) {
            if showsGroupControls {
                HStack(spacing: 8) {
                    Button {
                        appState.toggleSelection(lamp)
                    } label: {
                        Label(
                            isSelected
                                ? NSLocalizedString("lamps.in.group", comment: "")
                                : NSLocalizedString("lamps.add.to.group", comment: ""),
                            systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : muted)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .liquidGlassSurface(radius: 14, interactive: true)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }

            if let brightness = brightnessCapability {
                HStack(spacing: 9) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(muted)
                        .frame(width: 14)
                        .help("help.brightness")

                    Slider(
                        value: Binding(
                            get: { Double(brightnessValue(for: brightness)) },
                            set: { appState.previewBrightness(lamp, value: Int($0)) }
                        ),
                        in: Double(brightness.min)...Double(brightness.max),
                        step: Double(brightness.step),
                        onEditingChanged: { editing in
                            if editing { appState.beginAdjusting(lamp); return }
                            Task { await appState.commitBrightness(lamp, value: brightnessValue(for: brightness)) }
                        }
                    )
                    .tint(Color(red: 0.96, green: 0.77, blue: 0.26))
                    .disabled(!lamp.online)

                    Text("\(brightnessPercentage(for: brightness))%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(muted)
                        .frame(width: 32, alignment: .trailing)
                }
            }

            if let temperature = temperatureCapability {
                HStack(spacing: 9) {
                    Image(systemName: "thermometer.sun")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(muted)
                        .frame(width: 14)
                        .help("help.temperature")

                    // The slider works in Kelvin (warm left, cold right for every provider) and
                    // converts to the lamp's native scale, which is inverted for Hue mirek.
                    let kelvinRange = LampScale.kelvinRange(of: temperature)
                    Slider(
                        value: Binding(
                            get: { Double(temperatureKelvin(for: temperature)) },
                            set: { appState.previewTemperature(lamp, value: LampScale.nativeTemperature(kelvin: Int($0.rounded()), capability: temperature)) }
                        ),
                        in: Double(kelvinRange.lowerBound)...Double(kelvinRange.upperBound),
                        step: Double(LampScale.kelvinStep(of: temperature)),
                        onEditingChanged: { editing in
                            if editing { appState.beginAdjusting(lamp); return }
                            Task { await appState.commitTemperature(lamp, value: temperatureValue(for: temperature)) }
                        }
                    )
                    .disabled(!lamp.online)

                    Text(temperatureLabel(for: temperature))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(muted)
                        .frame(width: 58, alignment: .trailing)
                }
            }

            if lamp.capabilities.colorCode != nil {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(width: 14)
                            .help("help.color")

                        ColorSwatch(fill: displayColor ?? Color(hsv: .warm), size: 22)

                        Spacer()

                        ForEach(HSVColor.quickColors, id: \.self) { color in
                            Button {
                                let hsv = color.withValue(currentColorValue)
                                appState.previewColor(lamp, color: hsv)
                                Task { await appState.commitColor(lamp, color: hsv) }
                            } label: {
                                Circle()
                                    .fill(Color(hsv: color))
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 0.8))
                                    .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.5))
                                    .overlay(
                                        Circle()
                                            .stroke(accent, lineWidth: 1.5)
                                            .frame(width: 22, height: 22)
                                            .opacity(isSelectedQuickColor(color) ? 1 : 0)
                                    )
                                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!lamp.online)
                            .help(L10n.quickColorName(color))
                        }
                    }

                    ColorSpectrumPicker(showsThumb: !lamp.isWhiteMode, color: Binding(
                        get: { lamp.color ?? .warm },
                        set: { newColor in
                            let hsv = newColor.withValue(currentColorValue)
                            appState.previewColor(lamp, color: hsv)
                        }
                    ), onBegin: {
                        appState.beginAdjusting(lamp)
                    }, onCommit: { finalColor in
                        let hsv = finalColor.withValue(currentColorValue)
                        Task { await appState.commitColor(lamp, color: hsv) }
                    })
                    .frame(height: 62)
                    .disabled(!lamp.online)
                    .opacity(lamp.online ? 1 : 0.45)
                }
            }
        }
    }

    /// What the lamp is emitting, for swatches and the glow line. In white mode this is the
    /// tint of the color temperature — never the stale hue/saturation the bulb still reports.
    private var displayColor: Color? {
        if lamp.isWhiteMode {
            guard let temperature = lamp.temperature, let capability = lamp.capabilities.temperature else { return nil }
            let kelvin = LampScale.kelvin(native: temperature, capability: capability)
            return Color(nsColor: StatusItemIcon.kelvinColor(kelvin))
        }
        return lamp.color.map { Color(hsv: $0) }
    }

    /// Only "white" has a persistent identity: it is a mode (color temperature), whereas
    /// the other quick colors are just presets of the color picker.
    private func isSelectedQuickColor(_ color: HSVColor) -> Bool {
        color == .white && lamp.isWhiteMode
    }

    private var compactStatus: String {
        if !lamp.online { return L10n.statusOffline }
        return lamp.power ? L10n.statusOn : L10n.statusOff
    }

    private var brightnessCapability: NumericCapability? {
        if let brightness = lamp.capabilities.brightness {
            return brightness
        }
        if lamp.capabilities.colorCode != nil {
            return NumericCapability(code: "colour_value", min: 10, max: 1000, step: 1)
        }
        return nil
    }

    private var temperatureCapability: NumericCapability? {
        lamp.capabilities.temperature
    }

    private func brightnessValue(for capability: NumericCapability) -> Int {
        if lamp.capabilities.brightness != nil {
            return min(capability.max, max(capability.min, lamp.brightness ?? capability.min))
        }
        if lamp.capabilities.colorCode != nil {
            return min(capability.max, max(capability.min, lamp.color?.v ?? HSVColor.defaultColorValue))
        }
        return capability.min
    }

    private func brightnessPercentage(for capability: NumericCapability) -> Int {
        Int(round(Double(brightnessValue(for: capability)) / Double(capability.max) * 100))
    }

    private func temperatureValue(for capability: NumericCapability) -> Int {
        min(capability.max, max(capability.min, lamp.temperature ?? capability.min))
    }

    private func temperaturePercentage(for capability: NumericCapability) -> Int {
        LampScale.warmToColdPercent(native: temperatureValue(for: capability), capability: capability)
    }

    private func temperatureLabel(for capability: NumericCapability) -> String {
        let kelvin = temperatureKelvin(for: capability)
        return "\(kelvin)K"
    }

    private func temperatureKelvin(for capability: NumericCapability) -> Int {
        LampScale.kelvin(native: temperatureValue(for: capability), capability: capability)
    }

    private var currentColorValue: Int {
        if let colorValue = lamp.color?.v {
            return min(1000, max(10, colorValue))
        }
        if let brightness = lamp.capabilities.brightness, let value = lamp.brightness {
            let range = max(1, brightness.max - brightness.min)
            let normalized = Double(value - brightness.min) / Double(range)
            return min(1000, max(10, Int(round(normalized * 1000.0))))
        }
        return HSVColor.defaultColorValue
    }
}
