import Foundation

extension LampDevice {
    /// True while the lamp emits white light chosen through its color temperature.
    ///
    /// Many bulbs (Yeelight, Tuya…) keep reporting the last hue/saturation while in white
    /// mode, so `color` alone must never be used to decide what is "selected": in white mode
    /// the UI shows the temperature, not a color.
    var isWhiteMode: Bool {
        workMode == "white" || workMode == "ct"
    }

    /// Neutral white (~4000 K) in the lamp's own temperature scale. Ranges starting at 1000+
    /// are Kelvin (Yeelight, LIFX, WiZ, Govee); others are vendor-relative scales where the
    /// midpoint is a neutral white.
    static func neutralWhite(for capability: NumericCapability) -> Int {
        let raw = capability.min >= 1000 ? 4000 : (capability.min + capability.max) / 2
        return min(capability.max, max(capability.min, raw))
    }

    /// Whether `color` is sent as a color temperature to this lamp rather than as RGB.
    func rendersAsWhite(_ color: HSVColor) -> Bool {
        color.isNearWhite && capabilities.temperature != nil
    }

    /// The lamp as it will look once `color` is applied: near-white colors go through color
    /// temperature on lamps that have one (see `AppState.applyColor`), so the optimistic state
    /// must be "white" too, otherwise the UI flips to color mode and back once the command or
    /// the bulb's push arrives.
    func previewingColor(_ color: HSVColor) -> LampDevice {
        guard rendersAsWhite(color), let temperature = capabilities.temperature else {
            return withColor(color)
        }
        var next = withTemperature(Self.neutralWhite(for: temperature))
        if let brightness = capabilities.brightness {
            next.brightness = Self.brightness(forColorValue: color.v, capability: brightness)
        }
        return next
    }

    /// Maps a color "value" (10…1000) onto a lamp's brightness scale.
    static func brightness(forColorValue value: Int, capability: NumericCapability) -> Int {
        let fraction = Double(min(1000, max(10, value))) / 1000.0
        return capability.min + Int((fraction * Double(capability.max - capability.min)).rounded())
    }
}
