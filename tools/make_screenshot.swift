// Composes a 2880x1800 Mac App Store screenshot: headline and icon on the left, a captured
// panel (screencapture -l <window>, with its shadow) on the right, on the icon's blue gradient.
//   swift tools/make_screenshot.swift <panel.png> <out.png> "<headline>" "<subline>"
import AppKit

let args = CommandLine.arguments
guard args.count == 5, let panel = NSImage(contentsOfFile: args[1]) else {
    print("usage: make_screenshot.swift <panel.png> <out.png> <headline> <subline>"); exit(1)
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon-1024.png"))!

let W = 2880, H = 1800
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)   // 1 point = 1 pixel
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: the icon's accent blue fading to navy
let accent = NSColor(red: 0.07, green: 0.42, blue: 0.75, alpha: 1)
let navy = NSColor(red: 0.08, green: 0.16, blue: 0.33, alpha: 1)
NSGradient(starting: accent, ending: navy)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)

// Panel, pixel for pixel (captures are @2x), centered vertically on the right
let px = panel.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? panel.size
let pr = NSRect(x: CGFloat(W) - px.width - 170, y: (CGFloat(H) - px.height) / 2, width: px.width, height: px.height)
panel.draw(in: pr)

// Left column: icon, headline, subline
let left: CGFloat = 230, colWidth = pr.minX - left - 120
let head = NSAttributedString(string: args[3], attributes: [
    .font: NSFont.systemFont(ofSize: 132, weight: .bold), .foregroundColor: NSColor.white])
let sub = NSAttributedString(string: args[4], attributes: [
    .font: NSFont.systemFont(ofSize: 60, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
let headH = head.boundingRect(with: NSSize(width: colWidth, height: 1000), options: .usesLineFragmentOrigin).height
let subH = sub.boundingRect(with: NSSize(width: colWidth, height: 1000), options: .usesLineFragmentOrigin).height
let iconSize: CGFloat = 230, gap1: CGFloat = 70, gap2: CGFloat = 50
let block = iconSize + gap1 + headH + gap2 + subH
var y = (CGFloat(H) + block) / 2   // top of the block, AppKit's origin is bottom-left
icon.draw(in: NSRect(x: left - iconSize * 0.1, y: y - iconSize, width: iconSize, height: iconSize))
y -= iconSize + gap1
head.draw(with: NSRect(x: left, y: y - headH, width: colWidth, height: headH), options: .usesLineFragmentOrigin)
y -= headH + gap2
sub.draw(with: NSRect(x: left, y: y - subH, width: colWidth, height: subH), options: .usesLineFragmentOrigin)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2]) (\(W)x\(H))")
