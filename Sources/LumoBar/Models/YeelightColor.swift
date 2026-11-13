import Foundation

extension HSVColor {
    /// Decodes Yeelight's `rgb` property (24-bit integer 0xRRGGBB) into the app's scale
    /// (h 0-360, s 0-1000). The brightness is a separate property on Yeelight, so the caller
    /// supplies `value` (v, 10-1000) instead of deriving it from the channels.
    static func fromYeelightRGB(_ rgb: Int, value: Int) -> HSVColor {
        let packed = min(0xFFFFFF, max(0, rgb))
        return fromRGB(
            r: (packed >> 16) & 0xFF,
            g: (packed >> 8) & 0xFF,
            b: packed & 0xFF,
            value: min(1000, max(10, value))
        )
    }
}
