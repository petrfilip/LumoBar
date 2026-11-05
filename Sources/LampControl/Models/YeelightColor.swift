import Foundation

extension HSVColor {
    /// Decodes Yeelight's `rgb` property (24-bit integer 0xRRGGBB) into the app's scale
    /// (h 0-360, s 0-1000). The brightness is a separate property on Yeelight, so the caller
    /// supplies `value` (v, 10-1000) instead of deriving it from the channels.
    static func fromYeelightRGB(_ rgb: Int, value: Int) -> HSVColor {
        let packed = min(0xFFFFFF, max(0, rgb))
        let r = Double((packed >> 16) & 0xFF) / 255.0
        let g = Double((packed >> 8) & 0xFF) / 255.0
        let b = Double(packed & 0xFF) / 255.0
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var hue = 0.0
        if delta > 0 {
            if maxC == r {
                hue = 60.0 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = 60.0 * ((b - r) / delta + 2)
            } else {
                hue = 60.0 * ((r - g) / delta + 4)
            }
            if hue < 0 { hue += 360 }
        }
        let saturation = maxC > 0 ? delta / maxC : 0
        return HSVColor(
            h: min(360, max(0, Int(hue.rounded()))),
            s: min(1000, max(0, Int((saturation * 1000).rounded()))),
            v: min(1000, max(10, value))
        )
    }
}
