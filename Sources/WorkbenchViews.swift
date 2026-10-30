import SwiftUI
import AppKit

/// What the workbench is holding. Lives as long as the app, so switching tabs (or a Services
/// request) never loses a paste.
final class Workbench: ObservableObject {
    enum Tool: String, CaseIterable { case inspect = "Inspect", logs = "Logs", cron = "Cron" }
    @Published var tool: Tool = .inspect
    @Published var inspectText = ""
    @Published var inspectZoneID = ""
    @Published var sources: [LogSource] = [] { didSet { rebuild() } }
    @Published var draft = ""
    @Published var draftZoneID = ""
    @Published var outputZoneID = "UTC"
    @Published var cronText = "0 9 * * 1-5"
    @Published var cronZoneID = "UTC"
    @Published private(set) var timeline = LogTimeline()

    private func rebuild() { timeline = LogTimeline.build(sources) }

    func addDraft(fallback: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sources.append(LogSource(name: "Source \(sources.count + 1)",
                                 zoneID: draftZoneID.isEmpty ? fallback : draftZoneID, text: text))
        draft = ""
    }
}

/// Zones the user already works with, plus UTC.
private func zoneChoices(_ store: TimeStore) -> [(id: String, name: String)] {
    var seen = Set<String>()
    var out: [(String, String)] = []
    for p in store.places where seen.insert(p.tzID).inserted { out.append((p.tzID, p.name)) }
    if seen.insert("UTC").inserted { out.append(("UTC", "UTC")) }
    return out
}

private struct ZonePicker: View {
    @EnvironmentObject var store: TimeStore
    @Binding var selection: String
    var width: CGFloat = 100
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(zoneChoices(store), id: \.id) { Text($0.name).tag($0.id) }
        }
        .labelsHidden()
        .frame(width: width)
        .onAppear { if selection.isEmpty { selection = store.places.first?.tzID ?? "UTC" } }
    }
}

struct WorkbenchView: View {
    @EnvironmentObject var bench: Workbench

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $bench.tool) {
                ForEach(Workbench.Tool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16).padding(.bottom, 10)

            switch bench.tool {
            case .inspect: InspectView()
            case .logs: LogsView()
            case .cron: CronView()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: Inspect

struct InspectView: View {
    @EnvironmentObject var store: TimeStore
    @EnvironmentObject var bench: Workbench
    @EnvironmentObject var panel: PanelState
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass").foregroundStyle(.secondary)
                TextField("Paste a timestamp, epoch, UUID, ULID or Snowflake", text: $bench.inspectText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .onExitCommand { bench.inspectText = "" }
                ZonePicker(selection: $bench.inspectZoneID, width: 96)
                    .help("Zone to assume when the text has none")
            }
            .padding(.horizontal, 12).frame(height: 32)
            .glass(Capsule())
            .padding(.horizontal, 16)

            ScrollView(.vertical) {
                VStack(spacing: 10) { content }
                    .padding(.horizontal, 10).padding(.bottom, 10)
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder private var content: some View {
        let fallback = TimeZone(identifier: bench.inspectZoneID) ?? store.home
        if bench.inspectText.trimmingCharacters(in: .whitespaces).isEmpty {
            resultCard(Inspection(kind: store.isLive ? "Now" : "Selected time", date: store.instant,
                                  details: ["Paste something above to decode it. Supports ISO 8601, epoch s/ms/\u{00B5}s/ns, log and syslog formats, UUID v1/v6/v7, ULID, Snowflake and MongoDB ObjectId."]))
        } else {
            switch Inspector.inspect(bench.inspectText, fallback: fallback) {
            case .found(let i): resultCard(i)
            case .failed(let why):
                Label(why, systemImage: "questionmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14).card()
            }
        }
    }

    private func resultCard(_ i: Inspection) -> some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(i.kind).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                    Spacer()
                    Text(relative(i.date)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(Fmt.formatter("EEE, MMM d, yyyy", store.home).string(from: i.date))
                    .font(.system(size: 13, weight: .medium))
                Text(Fmt.formatter(store.use24h ? "HH:mm:ss" : "h:mm:ss a", store.home).string(from: i.date) + " " + Fmt.abbr(store.home, i.date))
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                ForEach(i.details, id: \.self) {
                    Text($0).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(i.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(i.alternatives.enumerated()), id: \.offset) { _, a in
                    Text("Could also be \(a.kind): \(Fmt.formatter("MMM d, yyyy HH:mm", TimeZone(identifier: "UTC")!).string(from: a.date)) UTC")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button {
                    store.setInstant(i.date)
                    panel.tab = .zones
                } label: {
                    Label("Show on Zones", systemImage: "globe")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).card()

            VStack(spacing: 0) {
                ForEach(store.places) { p in
                    HStack {
                        Text(p.name).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(Fmt.time(i.date, p.tz, store.use24h)) \(Fmt.abbr(p.tz, i.date)) \u{00B7} \(Fmt.day(i.date, p.tz))")
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8).card()

            VStack(alignment: .leading, spacing: 0) {
                Text("COPY AS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                ForEach(Inspector.copyFormats(i.date, home: store.home), id: \.label) { f in
                    Button { copy(f.value); flash(f.label) } label: {
                        HStack(spacing: 8) {
                            Text(f.label).font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(width: 118, alignment: .leading)
                            Text(f.value).font(.system(size: 11, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Image(systemName: copied == f.label ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(copied == f.label ? Color.green : Color.secondary)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowStyle())
                    .help(f.value)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10).card()
        }
    }

    private func flash(_ label: String) {
        copied = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied == label { copied = nil } }
    }
}

func relative(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return abs(d.timeIntervalSinceNow) < 1 ? "now" : f.localizedString(for: d, relativeTo: Date())
}

// MARK: Logs

struct LogsView: View {
    @EnvironmentObject var store: TimeStore
    @EnvironmentObject var bench: Workbench
    @EnvironmentObject var panel: PanelState
    @State private var copied = false

    static let sourceColors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow]

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 10) {
                pasteCard
                if !bench.sources.isEmpty { timelineCard }
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if bench.draft.isEmpty {
                    Text("Paste log lines, alerts or chat messages from one system. Add more sources to merge them into one timeline.")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $bench.draft)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)   // the legacy scroller paints an opaque strip over the glass
            }
            .frame(height: bench.sources.isEmpty ? 120 : 64)
            HStack(spacing: 8) {
                Text("Zone if missing").font(.system(size: 11)).foregroundStyle(.secondary)
                ZonePicker(selection: $bench.draftZoneID, width: 110)
                Spacer()
                Button {
                    bench.addDraft(fallback: store.places.first?.tzID ?? "UTC")
                } label: {
                    Label(bench.sources.isEmpty ? "Build timeline" : "Add source", systemImage: "plus")
                }
                .disabled(bench.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            if !bench.sources.isEmpty {
                FlowChips(sources: bench.sources) { id in bench.sources.removeAll { $0.id == id } }
            }
        }
        .padding(12).card()
    }

    private var timelineCard: some View {
        let t = bench.timeline
        let tz = TimeZone(identifier: bench.outputZoneID) ?? .init(identifier: "UTC")!
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(t.events.count) events" + (t.events.count > 1 ? " over \(LogTimeline.duration(t.span))" : ""))
                        .font(.system(size: 13, weight: .semibold))
                    if t.skipped > 0 {
                        Text("\(t.skipped) line\(t.skipped == 1 ? "" : "s") before the first timestamp skipped")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ZonePicker(selection: $bench.outputZoneID, width: 90).help("Show times in this zone")
                Menu {
                    Button("Copy as Markdown table") { copy(t.markdown(tz, sources: bench.sources)); flash() }
                    Button("Copy as normalized log") { copy(t.normalized(tz, sources: bench.sources)); flash() }
                    Divider()
                    Button("Clear timeline", role: .destructive) { bench.sources = [] }
                } label: {
                    Image(systemName: copied ? "checkmark" : "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 30, height: 30)
                .glass(Circle(), interactive: true)
            }
            let biggest = (1..<max(t.events.count, 1)).compactMap { t.gap($0) }.max() ?? 0
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(t.events.enumerated()), id: \.element.id) { i, e in
                    if let g = t.gap(i), g >= 1 {
                        gapMarker(g, isBiggest: g == biggest && t.events.count > 2)
                    }
                    if i == 0 || Fmt.day(e.date, tz) != Fmt.day(t.events[i - 1].date, tz) {
                        Text(Fmt.formatter("EEEE, MMM d, yyyy", tz).string(from: e.date) + " (\(Fmt.abbr(tz, e.date)))")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.top, i == 0 ? 0 : 6).padding(.bottom, 2)
                    }
                    eventRow(e, tz: tz, millis: t.hasMillis)
                }
            }
        }
        .padding(12).card()
    }

    private func gapMarker(_ g: TimeInterval, isBiggest: Bool) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1, height: 10).padding(.leading, 34)
            Text("+" + LogTimeline.duration(g) + (isBiggest ? "  longest gap" : ""))
                .font(.system(size: 10, weight: isBiggest ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isBiggest ? Color.orange : Color.secondary)
        }
    }

    private func eventRow(_ e: LogEvent, tz: TimeZone, millis: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Fmt.formatter(millis ? "HH:mm:ss.SSS" : "HH:mm:ss", tz).string(from: e.date))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: millis ? 92 : 64, alignment: .leading)
            Circle().fill(Self.sourceColors[e.source % Self.sourceColors.count]).frame(width: 7, height: 7)
                .help(bench.sources.indices.contains(e.source) ? bench.sources[e.source].name : "")
            VStack(alignment: .leading, spacing: 1) {
                Text(e.message.isEmpty ? "(no message)" : e.message)
                    .font(.system(size: 11, design: .monospaced)).lineLimit(3)
                    .textSelection(.enabled)
                if !e.extra.isEmpty {
                    Text("+\(e.extra.count) more line\(e.extra.count == 1 ? "" : "s")")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .help(e.extra.joined(separator: "\n"))
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Show on Zones") { store.setInstant(e.date); panel.tab = .zones }
            Button("Inspect this time") {
                bench.inspectText = Inspector.copyFormats(e.date, home: store.home)[0].value
                bench.tool = .inspect
            }
            Button("Copy line") { copy(Fmt.formatter("yyyy-MM-dd HH:mm:ss", tz).string(from: e.date) + " " + e.message) }
        }
    }

    private func flash() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

/// The added sources as removable chips: color, name, zone and how many lines.
private struct FlowChips: View {
    let sources: [LogSource]
    let remove: (UUID) -> Void
    private func lineCount(_ s: LogSource) -> Int { s.text.split(whereSeparator: \.isNewline).count }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 5) {
                        Circle().fill(LogsView.sourceColors[i % LogsView.sourceColors.count]).frame(width: 7, height: 7)
                        Text("\(s.name) \u{00B7} \(Fmt.abbr(s.zone, Date())) \u{00B7} \(lineCount(s)) line\(lineCount(s) == 1 ? "" : "s")")
                            .font(.system(size: 11))
                        Button { remove(s.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9).frame(height: 24)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
        }
        .scrollIndicators(.never)
    }
}

// MARK: Cron

struct CronView: View {
    @EnvironmentObject var store: TimeStore
    @EnvironmentObject var bench: Workbench

    static let examples = [
        ("Every 15 minutes", "*/15 * * * *"), ("Weekdays at 9:00", "0 9 * * 1-5"),
        ("Nightly at 2:30", "30 2 * * *"), ("First of the month", "0 0 1 * *"), ("Hourly", "@hourly"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
                TextField("Cron expression, e.g. 0 9 * * 1-5", text: $bench.cronText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                Menu {
                    ForEach(Self.examples, id: \.1) { e in Button("\(e.0)   \(e.1)") { bench.cronText = e.1 } }
                } label: { Image(systemName: "list.bullet") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                .help("Examples")
            }
            .padding(.horizontal, 12).frame(height: 32)
            .glass(Capsule())
            .padding(.horizontal, 16)

            ScrollView(.vertical) {
                VStack(spacing: 10) { content }
                    .padding(.horizontal, 10).padding(.bottom, 10)
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder private var content: some View {
        let zone = TimeZone(identifier: bench.cronZoneID) ?? TimeZone(identifier: "UTC")!
        switch Result(catching: { try CronExpression(bench.cronText) }) {
        case .failure(let e):
            Label(String(describing: e), systemImage: "exclamationmark.triangle")
                .font(.system(size: 12)).foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14).card()
        case .success(let cron):
            let runs = cron.nextRuns(after: Date(), count: 10, zone: zone)
            VStack(alignment: .leading, spacing: 8) {
                Text(cron.description).font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    Text("Cron daemon runs in").font(.system(size: 11)).foregroundStyle(.secondary)
                    ZonePicker(selection: $bench.cronZoneID, width: 110)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14).card()

            if runs.isEmpty {
                Text("This schedule never runs in the next eight years.")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14).card()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("NEXT \(runs.count) RUNS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(Array(runs.enumerated()), id: \.offset) { i, r in
                    runRow(r, first: runs[0], zone: zone)
                    if i < runs.count - 1 { Divider().opacity(0.5) }
                }
                if runs.contains(where: { r in store.places.contains { drift($0.tz, r, runs[0], zone) != 0 } }) {
                    Text("Orange: a clock change moved the run for that place, compared with the first run.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 6)
                }
            }
            .padding(12).card()
        }
    }

    /// How much a clock change moved this run in `tz` relative to the first run (seconds).
    private func drift(_ tz: TimeZone, _ r: CronExpression.Run, _ first: CronExpression.Run, _ zone: TimeZone) -> Int {
        (tz.secondsFromGMT(for: r.date) - zone.secondsFromGMT(for: r.date))
            - (tz.secondsFromGMT(for: first.date) - zone.secondsFromGMT(for: first.date))
    }

    private func runRow(_ r: CronExpression.Run, first: CronExpression.Run, zone: TimeZone) -> some View {
        let others = store.places.filter { $0.tz != zone }
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Fmt.formatter("EEE, MMM d", zone).string(from: r.date) + "  " + Fmt.time(r.date, zone, store.use24h) + " " + Fmt.abbr(zone, r.date))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                Spacer()
                Text(relative(r.date)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if r.shifted {
                Label("That time doesn't exist that day in \(Fmt.zoneName(zone)) (clocks spring forward). Most cron daemons run it an hour later or skip it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            // Each other zone's local time; orange when a clock change moved it relative to the first run.
            let parts = others.map { p -> Text in
                let drift = drift(p.tz, r, first, zone)
                let t = Text("\(p.name) \(Fmt.time(r.date, p.tz, store.use24h))")
                return drift == 0 ? t.foregroundColor(.secondary)
                    : t.foregroundColor(.orange) + Text(" (\(drift > 0 ? "+" : "\u{2212}")\(Fmt.hm(drift))h)").foregroundColor(.orange)
            }
            if !parts.isEmpty {
                parts.dropFirst().reduce(parts[0]) { $0 + Text("  \u{00B7}  ").foregroundColor(.secondary) + $1 }
                    .font(.system(size: 11).monospacedDigit())
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: Shared

extension View {
    /// A frosted card inside the glass panel: light fill, hairline highlight on the edge.
    func card(hover: Bool = false) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            shape.fill(Color.primary.opacity(hover ? 0.07 : 0.04))
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }
}
