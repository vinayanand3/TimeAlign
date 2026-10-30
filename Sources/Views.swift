import SwiftUI
import AppKit

enum Palette {
    static let accent = Color(red: 0.07, green: 0.42, blue: 0.75)
}

struct RootView: View {
    @EnvironmentObject var store: TimeStore
    @EnvironmentObject var panel: PanelState

    @State private var query = ""
    @State private var showBest = true
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if panel.tab == .workbench {
                WorkbenchView()
            } else {
                zones
            }
            footer
        }
        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        .background(GeometryReader { g in Color.clear.onAppear { rootHeight = g.size.height }
            .onChange(of: g.size.height) { rootHeight = $0 } })
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .top) { if panel.tab == .zones { searchResults } }
        .onChange(of: rowsHeight) { rows in
            // Next runloop turn, so the root and viewport heights from this layout pass are in.
            DispatchQueue.main.async { panel.rowsHeightChanged(rows, chrome: rootHeight - viewportHeight) }
        }
    }

    @ViewBuilder private var zones: some View {
            controls
            if showBest { bestBanner }
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(store.places) { p in
                        PlaceRow(place: p, isHome: p.id == store.places.first?.id)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 10)
                // Measured into @State: a preference set inside a macOS ScrollView doesn't reach outside it.
                .background(GeometryReader { g in Color.clear.onAppear { rowsHeight = g.size.height }
                    .onChange(of: g.size.height) { rowsHeight = $0 } })
            }
            .scrollIndicators(.never)   // a legacy scroller paints an opaque strip over the glass
            .background(GeometryReader { g in Color.clear.onAppear { viewportHeight = g.size.height }
                .onChange(of: g.size.height) { viewportHeight = $0 } })
            TimestampBar()
    }

    @State private var rowsHeight: CGFloat = 0
    @State private var rootHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.accent)
            Text("TimeAlign").font(.system(size: 16, weight: .semibold))
            TabSwitch(tab: $panel.tab).padding(.leading, 4)
            if !store.isLive && panel.tab == .zones {
                Text("scrubbing")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button { panel.pinned.toggle() } label: {
                Image(systemName: panel.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(IconButtonStyle())
            .help(panel.pinned ? "Floating above other windows" : "Normal window level")

            Menu {
                Toggle("24-hour clock", isOn: $store.use24h)
                Menu("Working hours") {
                    Picker("Start", selection: $store.workStart) {
                        ForEach(5..<13) { Text(Fmt.hourLabel($0, store.use24h)).tag($0) }
                    }
                    Picker("End", selection: $store.workEnd) {
                        ForEach(14..<23) { Text(Fmt.hourLabel($0, store.use24h)).tag($0) }
                    }
                }
                Divider()
                Button("Copy all times") { copy(store.summaryText()) }
                Button("Copy as ISO 8601 (UTC)") { copy(store.isoUTC()) }
                Button("Copy Unix epoch") { copy(String(Int(store.instant.timeIntervalSince1970))) }
                Divider()
                Button("Quit TimeAlign") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30, height: 30)
            .glass(Circle(), interactive: true)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .background(WindowDragArea())
    }

    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Add a city or time zone", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = Cities.search(query).first { add(first) } }
                    .onExitCommand { query = "" }
            }
            .padding(.horizontal, 12).frame(height: 32)
            .glass(Capsule())

            DatePicker("", selection: Binding(
                get: { store.homeDayForPicker },
                set: { store.setDay($0) }
            ), displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 96)
            .padding(.horizontal, 8).frame(height: 32)
            .glass(Capsule())

            nowButton.keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    @ViewBuilder private var nowButton: some View {
        let label = Label("Now", systemImage: "arrow.counterclockwise")
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 4).frame(height: 24)
        if #available(macOS 26, *) {
            Button { store.goNow() } label: { label }
                .buttonStyle(.glassProminent).tint(Palette.accent).controlSize(.large)
        } else {
            Button { store.goNow() } label: {
                label.padding(.horizontal, 10).frame(height: 32)
                    .background(Capsule().fill(Palette.accent)).foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var searchResults: some View {
        let results = Cities.search(query)
        if !results.isEmpty {
            VStack(spacing: 0) {
                ForEach(results, id: \.self) { c in
                    Button { add(c) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).font(.system(size: 13, weight: .semibold))
                                Text("\(c.subtitle) · \(Fmt.utcOffset(TimeZone(identifier: c.tzID)!, store.instant))")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.time(store.instant, TimeZone(identifier: c.tzID)!, store.use24h))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowStyle())
                }
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .frame(width: 300)
            .padding(.leading, 16)
            .padding(.top, 94)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func add(_ c: CityEntry) {
        store.add(Place(name: c.name, subtitle: c.subtitle, tzID: c.tzID))
        query = ""
    }

    // MARK: Best time

    private var bestBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let o = store.bestOverlap {
                    Button {
                        store.setInstant(o.start)
                    } label: {
                        Text("Best time: \(Fmt.time(o.start, store.home, store.use24h)) \u{2013} \(Fmt.time(o.end, store.home, store.use24h))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to the start of the overlap")
                    Text("Works for all \(store.places.count) places (\(Fmt.abbr(store.home, store.instant)), \(Fmt.hourLabel(store.workStart, store.use24h))\u{2013}\(Fmt.hourLabel(store.workEnd, store.use24h)) local)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("No shared working hours")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)
                    Text("Try widening working hours in the \u{2026} menu")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { showBest = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.accent.opacity(0.12)))
        .padding(.horizontal, 10)
    }

    private var footer: some View {
        HStack {
            Text(panel.tab == .zones ? store.places.map { $0.name }.joined(separator: " \u{00B7} ")
                 : "Times shown in \(store.places.first?.name ?? "UTC") (home)")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text("\u{2325}\u{2318}T to show/hide").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

/// Zones / Workbench, as a small glass capsule with the selected half filled in.
struct TabSwitch: View {
    @Binding var tab: PanelState.Tab
    var body: some View {
        HStack(spacing: 2) {
            item(.zones, "Zones", "globe", "1")
            item(.workbench, "Workbench", "wrench.and.screwdriver", "2")
        }
        .padding(2)
        .glass(Capsule())
    }

    private func item(_ t: PanelState.Tab, _ title: String, _ icon: String, _ key: KeyEquivalent) -> some View {
        Button { tab = t } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9).frame(height: 24)
                .background(Capsule().fill(tab == t ? Palette.accent : Color.clear))
                .foregroundStyle(tab == t ? Color.white : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help("\(title) (\u{2318}\(String(key.character)))")
    }
}

// MARK: Row

struct PlaceRow: View {
    @EnvironmentObject var store: TimeStore
    let place: Place
    let isHome: Bool
    @State private var hovering = false

    var body: some View {
        let tz = place.tz
        let d = store.instant
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text(place.name).font(.system(size: 18, weight: .bold))
                    if isHome {
                        Image(systemName: "house.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(Fmt.time(d, tz, store.use24h))
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .onTapGesture(count: 2) { copy(Fmt.time(d, tz, store.use24h) + " " + Fmt.abbr(tz, d)) }
                    .help("Double-click to copy")
            }
            HStack {
                Text("\(place.subtitle) | \(Fmt.abbr(tz, d))")
                    .lineLimit(1)
                Spacer()
                Text(isHome
                     ? "\(Fmt.utcOffset(tz, d)) | \(Fmt.day(d, tz))"
                     : "\(Fmt.utcOffset(tz, d)) | \(Fmt.relative(tz, to: store.home, d)) | \(Fmt.day(d, tz))")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)

            DayTrack(minute: store.minuteOfDay(tz),
                     workStart: store.workStart, workEnd: store.workEnd,
                     emphasized: hovering) { m in
                store.setMinute(m, in: tz)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { store.remove(place.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).padding(7)
            }
        }
        .card(hover: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            if !isHome { Button("Make home zone (offsets relative to this)") { store.makeHome(place.id) } }
            Button("Move up") { store.move(place.id, by: -1) }
            Button("Move down") { store.move(place.id, by: 1) }
            Button("Copy \(place.name) time") {
                copy("\(Fmt.time(d, tz, store.use24h)) \(Fmt.abbr(tz, d)), \(Fmt.day(d, tz))")
            }
            Divider()
            Button("Remove", role: .destructive) { store.remove(place.id) }
        }
    }
}

/// Drags the window from wherever it sits (the header), so the rest of the panel keeps its own drags.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The day/night bar with a draggable knob. Position = local time of day in that row's zone.
struct DayTrack: View {
    let minute: Double
    let workStart: Int
    let workEnd: Int
    let emphasized: Bool
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = CGFloat(minute / 1440) * w
            let ws = CGFloat(workStart) / 24 * w, we = CGFloat(workEnd) / 24 * w
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(stops: Self.sky, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 12)
                // working hours: a bright outline over that stretch of sky
                Capsule()
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: we - ws, height: 12)
                    .offset(x: ws)
                // glass knob with a sun or moon for that zone's local time
                Image(systemName: isDaytime ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDaytime ? Color.orange : Color.indigo)
                    .frame(width: 28, height: 28)
                    .glass(Circle(), interactive: true)
                    .overlay(Circle().strokeBorder(Palette.accent, lineWidth: emphasized ? 1.5 : 0))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .offset(x: x - 14)
            }
            .frame(height: 28)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let clamped = min(max(v.location.x, 0), w)
                onChange(Double(clamped / w) * 1440)
            })
        }
        .frame(height: 30)
    }

    private var isDaytime: Bool { minute >= 6.5 * 60 && minute < 18.5 * 60 }

    /// A day's sky from midnight to midnight: night, sunrise, morning blue, noon gold, dusk, night.
    private static let sky: [Gradient.Stop] = {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
        let night = c(18, 36, 72)
        return [
            .init(color: night, location: 0),
            .init(color: night, location: 0.21),
            .init(color: c(240, 153, 123), location: 0.27),   // sunrise
            .init(color: c(133, 183, 235), location: 0.35),   // morning
            .init(color: c(250, 199, 117), location: 0.52),   // noon
            .init(color: c(133, 183, 235), location: 0.68),   // afternoon
            .init(color: c(212, 83, 126), location: 0.77),    // dusk
            .init(color: c(60, 52, 137), location: 0.82),
            .init(color: night, location: 0.88),
            .init(color: night, location: 1),
        ]
    }()
}

extension View {
    /// Liquid Glass on macOS 26 and later, a translucent material on older systems.
    @ViewBuilder func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else if let tint {
            background(tint, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

// MARK: Timestamp paste bar

struct TimestampBar: View {
    @EnvironmentObject var store: TimeStore
    @EnvironmentObject var bench: Workbench
    @EnvironmentObject var panel: PanelState
    @State private var text = ""
    @State private var status = ""
    @State private var ok = true
    @State private var assumeID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor").foregroundStyle(.secondary)
                TextField("Paste a timestamp (log, ticket, epoch) and press \u{21A9}", text: $text)
                    .textFieldStyle(.plain)
                    .onSubmit(apply)
                Picker("", selection: $assumeID) {
                    ForEach(store.places) { p in Text(p.name).tag(p.tzID) }
                }
                .labelsHidden()
                .frame(width: 100)
                .help("Zone to assume when the timestamp has none")
            }
            .padding(.horizontal, 12).frame(height: 32)
            .glass(Capsule())

            if !status.isEmpty {
                HStack(spacing: 6) {
                    Text(status).font(.system(size: 11)).foregroundStyle(ok ? Color.secondary : Color.red)
                    Button("Details") {
                        bench.inspectText = text
                        bench.inspectZoneID = assumeID
                        bench.tool = .inspect
                        panel.tab = .workbench
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                    .help("Format, warnings and copy-as in the Workbench")
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 10)
        .onAppear { if assumeID.isEmpty { assumeID = store.places.first?.tzID ?? "UTC" } }
    }

    private func apply() {
        let fallback = TimeZone(identifier: assumeID) ?? store.home
        if let r = TimestampParser.parse(text, fallback: fallback) {
            store.setInstant(r.date)
            ok = true
            status = "Showing \(Fmt.time(r.date, TimeZone(identifier: "UTC")!, true)) UTC \u{00B7} zone \(r.zoneNote)"
        } else {
            ok = false
            status = "Couldn't read that timestamp"
        }
    }
}

// MARK: Helpers

func copy(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .glass(Circle(), interactive: true)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Circle())
    }
}

struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(pressed: configuration.isPressed) { configuration.label }
    }
}

private struct HoverHighlight<Content: View>: View {
    let pressed: Bool
    @ViewBuilder let content: Content
    @State private var hover = false
    var body: some View {
        content
            .background(hover || pressed ? Color.primary.opacity(0.07) : Color.clear)
            .onHover { hover = $0 }
    }
}
