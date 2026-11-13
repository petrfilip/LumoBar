import Foundation

/// The single HSV <-> RGB conversion used by every provider (WiZ, Govee, Yeelight RGB).
/// App scale: h 0-360, s 0-1000, v 0-1000. Channels are 0-255. Both directions round to the
/// nearest integer (they used to truncate in one provider and round in another).
extension HSVColor {
    /// 8-bit RGB of this colour at its own saturation and value.
    var rgb: (r: Int, g: Int, b: Int) {
        let hue = Double(((h % 360) + 360) % 360) / 60.0
        let sat = min(1, max(0, Double(s) / 1000.0))
        let val = min(1, max(0, Double(v) / 1000.0))

        let sector = Int(hue)
        let f = hue - Double(sector)
        let p = val * (1 - sat)
        let q = val * (1 - f * sat)
        let t = val * (1 - (1 - f) * sat)

        let (r, g, b): (Double, Double, Double)
        switch sector % 6 {
        case 0: (r, g, b) = (val, t, p)
        case 1: (r, g, b) = (q, val, p)
        case 2: (r, g, b) = (p, val, t)
        case 3: (r, g, b) = (p, q, val)
        case 4: (r, g, b) = (t, p, val)
        default: (r, g, b) = (val, p, q)
        }

        func channel(_ x: Double) -> Int { min(255, max(0, Int((x * 255).rounded()))) }
        return (channel(r), channel(g), channel(b))
    }

    /// Converts 8-bit RGB to the app's scale. When `value` is given it is used as `v`
    /// (providers whose brightness is a separate property); otherwise `v` is the brightest
    /// channel, as in standard HSV.
    static func fromRGB(r: Int, g: Int, b: Int, value: Int? = nil) -> HSVColor {
        let rd = Double(min(255, max(0, r))) / 255.0
        let gd = Double(min(255, max(0, g))) / 255.0
        let bd = Double(min(255, max(0, b))) / 255.0
        let maxC = max(rd, gd, bd)
        let minC = min(rd, gd, bd)
        let delta = maxC - minC

        var hue = 0.0
        if delta > 0 {
            if maxC == rd {
                hue = 60.0 * ((gd - bd) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == gd {
                hue = 60.0 * ((bd - rd) / delta + 2)
            } else {
                hue = 60.0 * ((rd - gd) / delta + 4)
            }
            if hue < 0 { hue += 360 }
        }
        let saturation = maxC > 0 ? delta / maxC : 0
        return HSVColor(
            h: min(360, max(0, Int(hue.rounded()))),
            s: min(1000, max(0, Int((saturation * 1000).rounded()))),
            v: value ?? min(1000, max(0, Int((maxC * 1000).rounded())))
        )
    }
}
