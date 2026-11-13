import AppKit

/// Menu-bar icon that reflects what the lamps are actually showing.
enum StatusItemIcon {
    /// Color a lamp currently emits: its hue in color mode, or the tint of its
    /// color temperature in white mode. `nil` when the lamp reports neither.
    static func tint(for lamp: LampDevice) -> NSColor? {
        if lamp.workMode != "white", lamp.capabilities.colorCode != nil, let color = lamp.color {
            // Brightness is ignored on purpose: a dimmed lamp should still read
            // as its color in the menu bar, not as a dark blob.
            return NSColor(
                calibratedHue: CGFloat(color.h) / 360.0,
                saturation: CGFloat(min(1000, max(0, color.s))) / 1000.0,
                brightness: 1.0,
                alpha: 1.0
            )
        }
        if let temperature = lamp.temperature, let capability = lamp.capabilities.temperature {
            return kelvinColor(LampScale.kelvin(native: temperature, capability: capability))
        }
        return nil
    }

    /// Filled bulb in `fill`, outlined in the menu bar's label color so that
    /// light fills (white, pale colors) stay visible on a light menu bar.
    static func image(fill: NSColor) -> NSImage? {
        guard let filled = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil),
              let outline = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil)
        else { return nil }

        let image = NSImage(size: outline.size, flipped: false) { rect in
            tinted(filled, with: fill).draw(in: rect)
            // labelColor resolves against the status bar's appearance at draw time.
            tinted(outline, with: .labelColor).draw(in: rect)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "LumoBar"
        return image
    }

    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// Approximate RGB of a black-body radiator (Tanner Helland's fit).
    static func kelvinColor(_ kelvin: Int) -> NSColor {
        let t = Double(min(40_000, max(1_000, kelvin))) / 100.0

        let red: Double = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green: Double = t <= 66
            ? 99.4708025861 * log(t) - 161.1195681661
            : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue: Double
        if t >= 66 {
            blue = 255
        } else if t <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(t - 10) - 305.0447927307
        }

        func channel(_ value: Double) -> CGFloat { CGFloat(min(255, max(0, value)) / 255.0) }
        return NSColor(calibratedRed: channel(red), green: channel(green), blue: channel(blue), alpha: 1.0)
    }
}
