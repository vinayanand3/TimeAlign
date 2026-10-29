import SwiftUI
import AppKit
import Carbon.HIToolbox

final class PanelState: ObservableObject {
    weak var panel: NSPanel?
    @Published var pinned: Bool = (UserDefaults.standard.object(forKey: "pinned") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(pinned, forKey: "pinned")
            panel?.level = pinned ? .floating : .normal
        }
    }

    /// Smallest legible panel: header, controls and about one row. The layout doesn't scale down,
    /// so below this it just gets cut off. (The content view fills the frame: fullSizeContentView.)
    static let minSize = NSSize(width: 380, height: 340)

    /// True when the panel came back at a size the user chose, so launch doesn't override it.
    var keepSavedSize = false
    private var lastRowsHeight: CGFloat?

    /// The city list's natural height changed (a city was added or removed): resize the panel so
    /// every row shows without scrolling, keeping the top edge put and staying on screen.
    /// `chrome` is everything in the panel except the scrolling rows.
    func rowsHeightChanged(_ rows: CGFloat, chrome: CGFloat) {
        guard let panel, rows > 0 else { return }
        defer { lastRowsHeight = rows }
        if lastRowsHeight == nil && keepSavedSize { return }
        guard rows != lastRowsHeight, let vis = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let content = NSRect(x: 0, y: 0, width: panel.frame.width, height: chrome + rows)
        let h = min(max(panel.frameRect(forContentRect: content).height, PanelState.minSize.height), vis.height)
        var f = panel.frame
        f.origin.y = max(f.maxY - h, vis.minY)
        f.size.height = h
        panel.setFrame(f, display: true)
    }
}

/// Borderless floating panel that can still take keyboard focus (for the search box).
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }   // Esc hides
}

/// Plain AppKit entry point. A SwiftUI `App` needs at least one Scene, and the placeholder
/// `Settings` scene showed up as an empty window at launch.
@main
enum TimeAlignMain {
    static let delegate = AppDelegate()   // NSApp.delegate is weak, so keep a strong ref
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = TimeStore()
    let panelState = PanelState()
    var panel: FloatingPanel!
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var menuTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        buildMainMenu()
        Cities.preload()
        buildPanel()
        buildStatusItem()
        registerHotKey()
        showPanel()
    }

    /// Never visible (accessory app), but text fields need it for Cmd-C/V/X/A/Z.
    private func buildMainMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "TimeAlign", action: nil, keyEquivalent: ""))
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: Panel

    private func buildPanel() {
        let host = NSHostingController(rootView:
            RootView().environmentObject(store).environmentObject(panelState))
        host.sizingOptions = []   // the user sizes the panel; PanelState refits height when cities change

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 655),
            // Borderless: RootView draws the rounded glass itself, so there is no system frame
            // (a transparent titled window still drew its border and a band along the top).
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // the system shadow is a rectangle around the clear window; the glass casts its own
        // Not movable by background: that hijacks the day-track drags. The header is the handle.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = panelState.pinned ? .floating : .normal
        panel.contentViewController = host
        panel.delegate = self
        panelState.panel = panel

        // Assigning the hosting controller leaves the panel 0x0 (its view has no frame yet).
        // Give it a real size first so a fresh launch doesn't start as a sliver.
        panel.setContentSize(NSSize(width: 460, height: 655))
        panelState.keepSavedSize = panel.setFrameUsingName("TimeAlignPanel")
        if !panelState.keepSavedSize { panel.center() }
        panel.setFrameAutosaveName("TimeAlignPanel")
    }

    /// Pull the panel fully onto its screen at a usable size (e.g. a saved frame from a
    /// since-removed display, or one saved below the minimum).
    private func keepOnScreen() {
        guard let vis = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = panel.frame
        f.size.width = min(max(f.width, PanelState.minSize.width), vis.width)
        f.size.height = min(max(f.height, PanelState.minSize.height), vis.height)
        f.origin.x = min(max(f.minX, vis.minX), vis.maxX - f.width)
        f.origin.y = min(max(f.minY, vis.minY), vis.maxY - f.height)
        if f != panel.frame { panel.setFrame(f, display: true) }
    }

    /// Enforce the minimum on every drag. `contentMinSize` alone doesn't hold: the SwiftUI hosting
    /// controller overwrites the window's min size when it lays out.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, PanelState.minSize.width),
               height: max(frameSize.height, PanelState.minSize.height))
    }

    func showPanel() {
        keepOnScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func togglePanel() {
        if panel.isVisible && panel.isKeyWindow { panel.orderOut(nil) } else { showPanel() }
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "globe.americas", accessibilityDescription: "TimeAlign")
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusTitle()
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.updateStatusTitle() }
        RunLoop.main.add(t, forMode: .common)
        menuTimer = t
    }

    /// Shows UTC time next to the icon so a glance is enough for log triage.
    private func updateStatusTitle() {
        let utc = TimeZone(identifier: "UTC")!
        statusItem.button?.title = " " + Fmt.time(Date(), utc, true) + "Z"
    }

    @objc private func statusClicked() {
        guard let e = NSApp.currentEvent else { return togglePanel() }
        if e.type == .rightMouseUp {
            let m = NSMenu()
            m.addItem(withTitle: "Show / Hide (\u{2325}\u{2318}T)", action: #selector(togglePanel), keyEquivalent: "").target = self
            m.addItem(.separator())
            m.addItem(withTitle: "Quit TimeAlign", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = m
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePanel()
        }
    }

    // MARK: Global hotkey ⌥⌘T

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.togglePanel() }
            return noErr
        }, 1, &spec, selfPtr, nil)

        let id = EventHotKeyID(signature: OSType(0x54414C4E), id: 1) // 'TALN'
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(optionKey | cmdKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
