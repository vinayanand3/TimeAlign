// Draws the TimeAlign app icon and writes Resources/AppIcon.icns.
//   swift tools/make_icon.swift
// Design: a clock face above the app's day/night bar and knob, on the app's blue.
import AppKit

let night = NSColor(red: 0.24, green: 0.36, blue: 0.56, alpha: 1)
let day = NSColor(red: 0.90, green: 0.82, blue: 0.58, alpha: 1)
let navy = NSColor(red: 0.08, green: 0.16, blue: 0.33, alpha: 1)
let accent = NSColor(red: 0.07, green: 0.42, blue: 0.75, alpha: 1)

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    let u = s / 1024   // design units: 1024 grid
    // Apple's macOS icon grid: 824pt rounded square centered, ~185pt corner radius.
    let tile = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(tilePath); ctx.setFillColor(navy.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [accent.cgColor, navy.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // Clock face
    let c = CGPoint(x: 512 * u, y: 575 * u), r = 215 * u
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * u), blur: 16 * u, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.restoreGState()

    // Hour ticks, longer at 12/3/6/9
    ctx.setLineCap(.round)
    for i in 0..<12 {
        let a = CGFloat(i) * .pi / 6, major = i % 3 == 0
        let outer = r - 28 * u, inner = outer - (major ? 34 : 16) * u
        ctx.setStrokeColor(navy.withAlphaComponent(major ? 0.85 : 0.35).cgColor)
        ctx.setLineWidth((major ? 14 : 9) * u)
        ctx.move(to: CGPoint(x: c.x + inner * sin(a), y: c.y + inner * cos(a)))
        ctx.addLine(to: CGPoint(x: c.x + outer * sin(a), y: c.y + outer * cos(a)))
        ctx.strokePath()
    }
    // Hands at 10:10
    func hand(_ angle: CGFloat, _ length: CGFloat, _ width: CGFloat, _ color: NSColor) {
        ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width * u)
        ctx.move(to: c)
        ctx.addLine(to: CGPoint(x: c.x + length * u * sin(angle), y: c.y + length * u * cos(angle)))
        ctx.strokePath()
    }
    hand(-.pi / 3 - .pi / 36, 110, 26, navy)    // hour, a little past 10
    hand(.pi / 3, 145, 18, navy)                 // minute, 10 past (stops short of the tick)
    ctx.setFillColor(accent.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - 22 * u, y: c.y - 22 * u, width: 44 * u, height: 44 * u))

    // Day/night bar: night, sand day in the middle, night again (as in the app's rows)
    let bar = CGRect(x: 232 * u, y: 238 * u, width: 560 * u, height: 54 * u)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 27 * u, cornerHeight: 27 * u, transform: nil)); ctx.clip()
    let dn = CGGradient(colorsSpace: nil, colors: [night, night, day, day, night, night].map(\.cgColor) as CFArray,
                        locations: [0, 0.28, 0.40, 0.66, 0.78, 1])!
    ctx.drawLinearGradient(dn, start: CGPoint(x: bar.minX, y: 0), end: CGPoint(x: bar.maxX, y: 0), options: [])
    ctx.restoreGState()
    // Faint outline so the night ends don't melt into the blue tile
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 27 * u, cornerHeight: 27 * u, transform: nil))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor); ctx.setLineWidth(5 * u); ctx.strokePath()
    // Knob
    let k = CGPoint(x: bar.minX + 0.58 * bar.width, y: bar.midY), kr = 46 * u
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5 * u), blur: 12 * u, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: k.x - kr, y: k.y - kr, width: 2 * kr, height: 2 * kr))
    ctx.restoreGState()
    ctx.restoreGState()
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(in: NSGraphicsContext.current!.cgContext, size: CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try! png(pt).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try! png(pt * 2).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
try! png(1024).write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and Resources/AppIcon-1024.png" : "iconutil failed")
