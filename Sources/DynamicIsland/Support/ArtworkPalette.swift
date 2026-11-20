import AppKit
import SwiftUI

/// Picks a vivid, readable accent colour from album art (for the waveform).
enum ArtworkPalette {
    static func accent(for image: NSImage) -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }

        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .white }

        // Bucket pixels by hue, weighting vivid & bright ones, then average the winning bucket.
        let bucketCount = 12
        var weights = [CGFloat](repeating: 0, count: bucketCount)
        var sums = [(r: CGFloat, g: CGFloat, b: CGFloat)](repeating: (0, 0, 0), count: bucketCount)
        var totalWeight: CGFloat = 0

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]) / 255, g = CGFloat(pixels[i + 1]) / 255, b = CGFloat(pixels[i + 2]) / 255
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let weight = saturation * saturation * (0.25 + brightness)
            guard weight > 0.02 else { continue }
            let bucket = min(Int(hue * CGFloat(bucketCount)), bucketCount - 1)
            weights[bucket] += weight
            sums[bucket].r += r * weight
            sums[bucket].g += g * weight
            sums[bucket].b += b * weight
            totalWeight += weight
        }

        guard totalWeight > 1.5, let best = weights.indices.max(by: { weights[$0] < weights[$1] }) else {
            return Color(white: 0.92)  // Monochrome art.
        }
        let w = weights[best]
        let average = NSColor(srgbRed: sums[best].r / w, green: sums[best].g / w, blue: sums[best].b / w, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation, 0.35), 0.85)),
            brightness: Double(max(brightness, 0.82))
        )
    }
}
