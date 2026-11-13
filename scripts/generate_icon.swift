#!/usr/bin/env swift
// Generates AppIcon.icns for LumoBar from the "lightbulb.fill" SF Symbol.
// Usage: swift scripts/generate_icon.swift [output_dir]
// The output_dir defaults to Resources/. Run once; commit the resulting AppIcon.icns.
import AppKit

NSApplication.shared.setActivationPolicy(.prohibited)

let repoRoot = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
let outputDir: URL
if CommandLine.arguments.count > 1 {
    outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    outputDir = repoRoot.appendingPathComponent("Resources")
}
let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data {
    let sz = CGFloat(pixelSize)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8,
                        bytesPerRow: pixelSize * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!

    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    // Blue rounded-rectangle background
    NSColor(red: 0.0, green: 0.47, blue: 0.95, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: sz, height: sz),
                 xRadius: sz * 0.22, yRadius: sz * 0.22).fill()

    // White lightbulb SF Symbol
    let ptSize = sz * 0.46
    let cfg = NSImage.SymbolConfiguration(pointSize: ptSize, weight: .medium)
    if let sym = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(cfg) {
        let iconSz = sz * 0.60
        let x = (sz - iconSz) / 2
        let y = (sz - iconSz) / 2
        sym.draw(in: NSRect(x: x, y: y, width: iconSz, height: iconSz),
                 from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    NSGraphicsContext.restoreGraphicsState()

    let cgImg = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: cgImg)
    return rep.representation(using: .png, properties: [:])!
}

// (pointSize, retina)
let specs: [(Int, Bool)] = [
    (16, false), (16, true),
    (32, false), (32, true),
    (128, false), (128, true),
    (256, false), (256, true),
    (512, false), (512, true),
]

for (base, retina) in specs {
    let px = retina ? base * 2 : base
    let name = retina ? "icon_\(base)x\(base)@2x.png" : "icon_\(base)x\(base).png"
    let data = renderIcon(pixelSize: px)
    try! data.write(to: iconsetURL.appendingPathComponent(name))
    print("  \(name) (\(px)px)")
}

try! FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let icnsURL = outputDir.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try! task.run()
task.waitUntilExit()

try? FileManager.default.removeItem(at: iconsetURL)

if task.terminationStatus == 0 {
    print("AppIcon.icns → \(icnsURL.path)")
} else {
    print("iconutil failed (exit \(task.terminationStatus))")
    exit(1)
}
