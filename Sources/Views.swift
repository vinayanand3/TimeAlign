import SwiftUI
import AppKit

enum Palette {
    static let night = Color(red: 0.24, green: 0.36, blue: 0.56)
    static let day = Color(red: 0.90, green: 0.82, blue: 0.58)
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
            controls
            Divider()
            if showBest { bestBanner; Divider() }
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(store.places) { p in
                        PlaceRow(place: p, isHome: p.id == store.places.first?.id)
                        Divider()
                    }
                }
                // Measured into @State: a preference set inside a macOS ScrollView doesn't reach outside it.
                .background(GeometryReader { g in Color.clear.onAppear { rowsHeight = g.size.height }
                    .onChange(of: g.size.height) { rowsHeight = $0 } })
            }
            .background(GeometryReader { g in Color.clear.onAppear { viewportHeight = g.size.height }
                .onChange(of: g.size.height) { viewportHeight = $0 } })
            TimestampBar()
            footer
        }
        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        .background(GeometryReader { g in Color.clear.onAppear { rootHeight = g.size.height }
            .onChange(of: g.size.height) { rootHeight = $0 } })
        .background(.regularMaterial)
        .overlay(alignment: .top) { searchResults }
        .onChange(of: rowsHeight) { rows in
            // Next runloop turn, so the root and viewport heights from this layout pass are in.
            DispatchQueue.main.async { panel.rowsHeightChanged(rows, chrome: rootHeight - viewportHeight) }
        }
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
            if !store.isLive {
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
            .frame(width: 30, height: 26)
            .background(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.35)))
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
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))

            DatePicker("", selection: Binding(
                get: { store.homeDayForPicker },
                set: { store.setDay($0) }
            ), displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(width: 110)

            Button { store.goNow() } label: {
                Label("Now", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
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
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Text(store.places.map { $0.name }.joined(separator: " \u{00B7} "))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text("\u{2325}\u{2318}T to show/hide").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
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
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { store.remove(place.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).padding(6)
            }
        }
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
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
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                // hour ticks every 6h
                ForEach([6, 12, 18], id: \.self) { h in
                    Rectangle().fill(Color.white.opacity(0.5))
                        .frame(width: 1, height: 8)
                        .offset(x: CGFloat(h) / 24 * w)
                }
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(emphasized ? Palette.accent : Color.black.opacity(0.15),
                                             lineWidth: emphasized ? 2.5 : 1))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .frame(width: 22, height: 22)
                    .offset(x: x - 11)
            }
            .frame(height: 22)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let clamped = min(max(v.location.x, 0), w)
                onChange(Double(clamped / w) * 1440)
            })
        }
        .frame(height: 24)
    }

    private var stops: [Gradient.Stop] {
        let s = Double(workStart) / 24, e = Double(workEnd) / 24, fade = 1.5 / 24
        return [
            .init(color: Palette.night, location: 0),
            .init(color: Palette.night, location: max(s - fade, 0)),
            .init(color: Palette.day, location: s),
            .init(color: Palette.day, location: e),
            .init(color: Palette.night, location: min(e + fade, 1)),
            .init(color: Palette.night, location: 1),
        ]
    }
}

// MARK: Timestamp paste bar

struct TimestampBar: View {
    @EnvironmentObject var store: TimeStore
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
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            if !status.isEmpty {
                Text(status).font(.system(size: 11)).foregroundStyle(ok ? Color.secondary : Color.red)
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
            .frame(width: 30, height: 26)
            .background(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.35)))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
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
