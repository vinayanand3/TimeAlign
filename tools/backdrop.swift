// Shows an image in a plain window so the glass panel can be captured over it (App Store
// screenshots and preview recordings). Runs until killed.
//   swift tools/backdrop.swift <image> <x> <y> <width> <height>    (points, top-left origin)
import AppKit

let args = CommandLine.arguments
guard args.count == 6, let image = NSImage(contentsOfFile: args[1]) else {
    print("usage: backdrop.swift <image> <x> <y> <width> <height>"); exit(1)
}
let v = args[2...5].map { CGFloat(Double($0)!) }
let screen = NSScreen.screens[0].frame
let rect = NSRect(x: v[0], y: screen.height - v[1] - v[3], width: v[2], height: v[3])

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
let view = NSImageView(frame: NSRect(origin: .zero, size: rect.size))
view.image = image
view.imageScaling = .scaleAxesIndependently
window.contentView = view
window.hasShadow = false
// Above ordinary app windows (so it can be staged from any app) but below TimeAlign's floating panel.
window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
