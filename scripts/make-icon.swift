// Draws the app icon and writes Resources/AppIcon.icns and Resources/icon.png.
// Usage: swift scripts/make-icon.swift   (run from the repo root)
import Cocoa

func draw(_ s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 1024
    // macOS icon grid: 824pt tile centred on a 1024pt canvas.
    let tile = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let bg = NSBezierPath(roundedRect: tile, xRadius: 185 * u, yRadius: 185 * u)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 1), NSColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1)])!
        .draw(in: bg, angle: -90)
    let bars: [(CGFloat, NSColor)] = [(0.40, .systemGreen), (0.65, .systemOrange), (0.85, .systemRed)]
    let w = 120 * u, gap = 50 * u, h = 400 * u
    let x0 = tile.midX - (3 * w + 2 * gap) / 2, y0 = tile.midY - h / 2
    for (i, (level, color)) in bars.enumerated() {
        let x = x0 + CGFloat(i) * (w + gap)
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y0, width: w, height: h), xRadius: w / 2, yRadius: w / 2).fill()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y0, width: w, height: h * level), xRadius: w / 2, yRadius: w / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ s: CGFloat, to path: String) {
    try! draw(s).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let set = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    png(CGFloat(base), to: "\(set)/icon_\(base)x\(base).png")
    png(CGFloat(base * 2), to: "\(set)/icon_\(base)x\(base)@2x.png")
}
png(512, to: "Resources/icon.png")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(atPath: set)
