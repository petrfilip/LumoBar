import Foundation

/// Pure conversions between the portable units used by adaptive lighting
/// (brightness in percent, temperature in Kelvin) and each lamp's native
/// capability range. `LightProvider.setBrightness` / `setTemperature` take the
/// native value, so callers holding percent / Kelvin must convert first.
enum LampScale {
    /// Kelvin range that vendor-relative scales (Tuya 0–1000, ...) are mapped onto.
    static let relativeKelvinRange: ClosedRange<Int> = 2700...6500

    /// How a temperature capability expresses colour temperature.
    enum TemperatureScale: Equatable {
        /// Native value is Kelvin (Yeelight, LIFX, WiZ, Govee, Nanoleaf).
        case kelvin
        /// Native value is mirek = 1 000 000 / K (Hue `ct`): higher is warmer.
        case mirek
        /// Opaque vendor scale, low = warm, high = cold (Tuya 0–1000).
        case relative
    }

    static func temperatureScale(of capability: NumericCapability) -> TemperatureScale {
        if capability.min >= 1000 { return .kelvin }
        if capability.code == "ct" { return .mirek }
        return .relative
    }

    // MARK: Brightness

    /// Percent (0–100, clamped) -> native value in `min...max`.
    static func nativeBrightness(percent: Int, capability: NumericCapability) -> Int {
        let p = Double(min(100, max(0, percent))) / 100.0
        let span = Double(max(0, capability.max - capability.min))
        return capability.min + Int((p * span).rounded())
    }

    /// Native value -> percent (0–100) of the capability range.
    static func brightnessPercent(native: Int, capability: NumericCapability) -> Int {
        let span = max(1, capability.max - capability.min)
        let clamped = min(capability.max, max(capability.min, native))
        return Int((Double(clamped - capability.min) / Double(span) * 100.0).rounded())
    }

    // MARK: Temperature

    /// Kelvin -> native value, always clamped to the capability range.
    static func nativeTemperature(kelvin: Int, capability: NumericCapability) -> Int {
        let lo = min(capability.min, capability.max)
        let hi = max(capability.min, capability.max)
        let raw: Int
        switch temperatureScale(of: capability) {
        case .kelvin:
            raw = kelvin
        case .mirek:
            raw = Int((1_000_000.0 / Double(max(1, kelvin))).rounded())
        case .relative:
            let range = relativeKelvinRange
            let k = min(range.upperBound, max(range.lowerBound, kelvin))
            let t = Double(k - range.lowerBound) / Double(range.upperBound - range.lowerBound)
            raw = capability.min + Int((t * Double(capability.max - capability.min)).rounded())
        }
        return min(hi, max(lo, raw))
    }

    /// The Kelvin span a temperature control covers, lowest (warmest) first. Hue's mirek runs
    /// the other way round, so the native min is its *coldest* end.
    static func kelvinRange(of capability: NumericCapability) -> ClosedRange<Int> {
        let a = kelvin(native: capability.min, capability: capability)
        let b = kelvin(native: capability.max, capability: capability)
        return min(a, b)...max(a, b)
    }

    /// Slider step in Kelvin: the vendor's own for Kelvin lamps, otherwise a fixed 50 K.
    static func kelvinStep(of capability: NumericCapability) -> Int {
        temperatureScale(of: capability) == .kelvin ? max(1, capability.step) : 50
    }

    /// Position on the warm -> cold axis, 0 % = warmest, 100 % = coldest, whatever the
    /// vendor's native direction is.
    static func warmToColdPercent(native: Int, capability: NumericCapability) -> Int {
        let range = kelvinRange(of: capability)
        let span = max(1, range.upperBound - range.lowerBound)
        let k = min(range.upperBound, max(range.lowerBound, kelvin(native: native, capability: capability)))
        return Int((Double(k - range.lowerBound) / Double(span) * 100.0).rounded())
    }

    /// Native value -> Kelvin, using the same rules as `nativeTemperature`.
    static func kelvin(native: Int, capability: NumericCapability) -> Int {
        let lo = min(capability.min, capability.max)
        let hi = max(capability.min, capability.max)
        let value = min(hi, max(lo, native))
        switch temperatureScale(of: capability) {
        case .kelvin:
            return value
        case .mirek:
            return Int((1_000_000.0 / Double(max(1, value))).rounded())
        case .relative:
            let span = max(1, capability.max - capability.min)
            let t = Double(value - capability.min) / Double(span)
            let range = relativeKelvinRange
            return range.lowerBound + Int((t * Double(range.upperBound - range.lowerBound)).rounded())
        }
    }
}
