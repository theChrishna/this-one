// Draws the BarTidy app icon and writes Resources/AppIcon.icns.
// Usage (from the repo root): swift tools/make-icon.swift
import AppKit

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Draws the icon on a 1024×1024 canvas (Apple's macOS grid: 824pt body, 100pt margin).
func drawIcon(in ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Body: deep blue to indigo.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bg = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.33, green: 0.42, blue: 0.98, alpha: 1),
        CGColor(srgbRed: 0.20, green: 0.16, blue: 0.62, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // A menu bar pill across the middle.
    let bar = CGRect(x: 160, y: 412, width: 704, height: 200)
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.15))
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 100, cornerHeight: 100, transform: nil))
    ctx.fillPath()

    // Icons fading out to the left (the ones being tidied away).
    let y = bar.midY
    for (i, alpha) in [0.2, 0.36, 0.56].enumerated() {
        let x = 262.0 + Double(i) * 112
        ctx.setFillColor(CGColor(gray: 1, alpha: alpha))
        ctx.fillEllipse(in: CGRect(x: x - 34, y: y - 34, width: 68, height: 68))
    }
    // The separator.
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.92))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 584, y: y - 56, width: 20, height: 112), cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.fillPath()
    // Bold chevron pointing left: "show what's hidden".
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineWidth(36)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 762, y: y + 62))
    ctx.addLine(to: CGPoint(x: 698, y: y))
    ctx.addLine(to: CGPoint(x: 762, y: y - 62))
    ctx.strokePath()

    // Subtle top highlight.
    let shine = CGGradient(colorsSpace: space, colors: [
        CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = gc.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(in: ctx)
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try! png(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
