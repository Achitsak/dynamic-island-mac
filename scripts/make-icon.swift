// Renders the app icon into an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // Squircle background with a deep wallpaper-like gradient.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let background = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.22, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.93, green: 0.30, blue: 0.62, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.30, alpha: 1),
    ])!.draw(in: background, angle: -60)

    // The island.
    let island = NSRect(x: 212 * s, y: 560 * s, width: 600 * s, height: 190 * s)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: 95 * s, yRadius: 95 * s).fill()

    // Album art.
    let art = NSRect(x: 262 * s, y: 600 * s, width: 110 * s, height: 110 * s)
    let artPath = NSBezierPath(roundedRect: art, xRadius: 26 * s, yRadius: 26 * s)
    NSGradient(colors: [
        NSColor(srgbRed: 1.0, green: 0.45, blue: 0.35, alpha: 1),
        NSColor(srgbRed: 0.95, green: 0.2, blue: 0.55, alpha: 1),
    ])!.draw(in: artPath, angle: -45)

    // Waveform.
    let heights: [CGFloat] = [50, 96, 70, 110, 60]
    let barWidth: CGFloat = 20 * s
    var x = 610 * s
    NSColor(srgbRed: 1.0, green: 0.55, blue: 0.5, alpha: 1).setFill()
    for h in heights {
        let bar = NSRect(x: x, y: 655 * s - h * s / 2, width: barWidth, height: h * s)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += 34 * s
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).write(to: URL(fileURLWithPath: "\(output)/\(name)"))
    }
}
print("ok")
