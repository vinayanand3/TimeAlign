// Renders the still layers for the App Preview video (1920x1080): the blue background with the
// icon, and one transparent PNG per caption. ffmpeg then layers the recorded panel and captions.
//   swift tools/make_preview_assets.swift <out dir> "<headline>|<subline>" ["<headline>|<subline>" ...]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: make_preview_assets.swift <out dir> \"head|sub\" ..."); exit(1) }
let out = URL(fileURLWithPath: args[1])
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon-1024.png"))!

func render(_ w: Int, _ h: Int, to name: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

// Same palette and layout as tools/make_screenshot.swift, scaled from 2880 to 1920 wide.
let accent = NSColor(red: 0.07, green: 0.42, blue: 0.75, alpha: 1)
let navy = NSColor(red: 0.08, green: 0.16, blue: 0.33, alpha: 1)
let left: CGFloat = 150, iconSize: CGFloat = 150, colWidth: CGFloat = 820

render(1920, 1080, to: "bg.png") {
    NSGradient(starting: accent, ending: navy)!.draw(in: NSRect(x: 0, y: 0, width: 1920, height: 1080), angle: -60)
    icon.draw(in: NSRect(x: left - iconSize * 0.1, y: 1080 - 180 - iconSize, width: iconSize, height: iconSize))
}

// Captions sit below the icon; each PNG covers the left column so it can be overlaid at (0, 0).
for (i, pair) in args.dropFirst(2).enumerated() {
    let parts = pair.split(separator: "|", maxSplits: 1).map(String.init)
    render(1920, 1080, to: "caption_\(i + 1).png") {
        let head = NSAttributedString(string: parts[0], attributes: [
            .font: NSFont.systemFont(ofSize: 88, weight: .bold), .foregroundColor: NSColor.white])
        let sub = NSAttributedString(string: parts.count > 1 ? parts[1] : "", attributes: [
            .font: NSFont.systemFont(ofSize: 40, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
        let opts: NSString.DrawingOptions = .usesLineFragmentOrigin
        let headH = head.boundingRect(with: NSSize(width: colWidth, height: 800), options: opts).height
        let subH = sub.boundingRect(with: NSSize(width: colWidth, height: 800), options: opts).height
        var y: CGFloat = 1080 - 180 - iconSize - 60
        head.draw(with: NSRect(x: left, y: y - headH, width: colWidth, height: headH), options: opts)
        y -= headH + 34
        sub.draw(with: NSRect(x: left, y: y - subH, width: colWidth, height: subH), options: opts)
    }
}
print("Wrote bg.png and \(args.count - 2) captions to \(out.path)")
