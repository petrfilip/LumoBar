import SwiftUI
import AppKit

extension HSVColor {
    static let quickColors: [HSVColor] = [
        HSVColor.white,
        HSVColor(h: 0, s: 900, v: 1000),
        HSVColor(h: 38, s: 850, v: 1000),
        HSVColor(h: 120, s: 850, v: 850),
        HSVColor(h: 205, s: 900, v: 1000),
        HSVColor(h: 278, s: 760, v: 950)
    ]

    init(color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        let hue = Int(round(nsColor.hueComponent * 360.0))
        let saturation = Int(round(nsColor.saturationComponent * 1000.0))
        self.init(h: hue, s: saturation, v: HSVColor.defaultColorValue)
    }
}

extension Color {
    init(hsv: HSVColor) {
        self.init(
            hue: Double(hsv.h) / 360.0,
            saturation: Double(hsv.s) / 1000.0,
            brightness: Double(hsv.v) / 1000.0
        )
    }
}

struct ColorSwatch: View {
    let fill: Color
    var size: CGFloat = 24

    init(color: HSVColor, size: CGFloat = 24) {
        self.fill = Color(hsv: color)
        self.size = size
    }

    init(fill: Color, size: CGFloat = 24) {
        self.fill = fill
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 2)
    }
}

struct ColorSpectrumPicker: View {
    /// Hidden while the lamp is in white mode: the stored hue/saturation is not what the
    /// lamp shows, so a thumb on it would look like a color is selected.
    var showsThumb = true
    @Binding var color: HSVColor
    var onBegin: (() -> Void)? = nil
    var onCommit: ((HSVColor) -> Void)? = nil
    /// The thumb follows the pointer through this local value while dragging instead of
    /// round-tripping through the store, so nothing a bulb pushes back can make it jump.
    @State private var dragColor: HSVColor?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let shown = dragColor ?? color
            let x = CGFloat(shown.h) / 360.0 * size.width
            let y = CGFloat(shown.s) / 1000.0 * size.height

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .overlay(
                    LinearGradient(
                        colors: [.white, .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )

                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color(hsv: shown)))
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.black.opacity(0.22), radius: 5, x: 0, y: 2)
                    .offset(x: min(max(0, x), size.width) - 9, y: min(max(0, y), size.height) - 9)
                    .opacity(showsThumb ? 1 : 0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let picked = color(at: value.location, in: size)
                        if dragColor == nil { onBegin?() }
                        dragColor = picked
                        color = picked
                    }
                    .onEnded { value in
                        let finalColor = color(at: value.location, in: size)
                        color = finalColor
                        dragColor = nil
                        onCommit?(finalColor)
                    }
            )
        }
    }

    private func color(at point: CGPoint, in size: CGSize) -> HSVColor {
        guard size.width > 0, size.height > 0 else { return color }
        let clampedX = min(max(0, point.x), size.width)
        let clampedY = min(max(0, point.y), size.height)
        return HSVColor(
            h: Int(round(clampedX / size.width * 360.0)),
            s: Int(round(clampedY / size.height * 1000.0)),
            v: HSVColor.defaultColorValue
        )
    }
}
