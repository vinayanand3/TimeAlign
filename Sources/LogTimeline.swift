import Foundation

/// A pasted block of log lines (or chat messages, alerts...) from one system, with the zone to
/// assume for timestamps that don't carry one.
struct LogSource: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var zoneID: String
    var text: String
    var zone: TimeZone { TimeZone(identifier: zoneID) ?? TimeZone(identifier: "UTC")! }
}

struct LogEvent: Identifiable, Equatable {
    var id = UUID()
    let source: Int        // index into the sources
    let line: Int          // 1-based line number in that source
    var date: Date
    let message: String
    var extra: [String] = []   // following lines without a timestamp (stack traces, wrapped text)
    /// The line had a time but no date ("4:07 PM" in a chat export).
    var timeOnly = false
}

struct LogTimeline: Equatable {
    var events: [LogEvent] = []
    /// Lines before the first timestamp in their source, which can't be placed.
    var skipped = 0

    var span: TimeInterval { (events.last?.date ?? .distantPast).timeIntervalSince(events.first?.date ?? .distantPast) }
    var hasMillis: Bool { events.contains { ($0.date.timeIntervalSince1970 * 1000).rounded().truncatingRemainder(dividingBy: 1000) != 0 } }

    /// Every source's events in one list, oldest first (ties keep paste order).
    static func build(_ sources: [LogSource], now: Date = Date()) -> LogTimeline {
        var t = LogTimeline()
        for (si, s) in sources.enumerated() {
            var current: LogEvent?
            for (li, line) in s.text.components(separatedBy: .newlines).enumerated() {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                if let (date, message, timeOnly) = extract(line, fallback: s.zone, now: now) {
                    if let c = current { t.events.append(c) }
                    current = LogEvent(source: si, line: li + 1, date: date, message: message, timeOnly: timeOnly)
                } else if current != nil {
                    current!.extra.append(line)
                } else {
                    t.skipped += 1
                }
            }
            if let c = current { t.events.append(c) }
        }
        // Times without a date land on today; move them to the day the dated events happened on.
        let dated = t.events.filter { !$0.timeOnly }.map(\.date)
        if let lo = dated.min(), let hi = dated.max() {
            for i in t.events.indices where t.events[i].timeOnly {
                let d = t.events[i].date
                let distance = { (x: Date) in x < lo ? lo.timeIntervalSince(x) : x > hi ? x.timeIntervalSince(hi) : 0 }
                let days = (-400...1).min { distance(d.addingTimeInterval(Double($0) * 86400)) < distance(d.addingTimeInterval(Double($1) * 86400)) }!
                t.events[i].date = d.addingTimeInterval(Double(days) * 86400)
            }
        }
        t.events = t.events.enumerated().sorted { a, b in
            a.element.date != b.element.date ? a.element.date < b.element.date : a.offset < b.offset
        }.map(\.element)
        return t
    }

    // MARK: Finding the timestamp in a line

    private static let zoneSuffix: String = {
        let abbrs = TimestampParser.abbreviations.keys.filter { $0 != "Z" }.sorted { $0.count > $1.count }
        return #"(?:\s?Z\b|\s?(?:UTC|GMT)[+-]\d{1,2}(?::?\d{2})?\b|\s?[+-]\d{2}:?\d{2}\b|\s(?:"#
            + abbrs.joined(separator: "|") + #")\b)?"#
    }()
    private static let clock = #"\d{2}:\d{2}(?::\d{2}(?:[.,]\d{1,9})?)?"#

    /// Most specific first: the first pattern that matches and parses wins. The last one is time only.
    static let patterns: [NSRegularExpression] = [
        #"\d{4}-\d{2}-\d{2}[T ]"# + clock + zoneSuffix,                                   // ISO-ish
        #"\d{4}/\d{2}/\d{2}[T ]"# + clock + zoneSuffix,
        #"\d{2}/[A-Z][a-z]{2}/\d{4}:\d{2}:\d{2}:\d{2} [+-]\d{4}"#,                        // Apache / nginx
        #"(?:[A-Z][a-z]{2},? )?\d{1,2} [A-Z][a-z]{2} \d{4} "# + clock + zoneSuffix,        // RFC 2822
        #"[A-Z][a-z]{2} [A-Z][a-z]{2} +\d{1,2} "# + clock + zoneSuffix + #" \d{4}"#,       // date(1)
        #"\d{1,2}/\d{1,2}/\d{2,4},? \d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp][Mm])?"# + zoneSuffix,
        #"[A-Z][a-z]{2} +\d{1,2} "# + clock + zoneSuffix,                                  // syslog
        #"(?<![\d.])1\d{9}(?:\d{3}|\d{6}|\d{9})?(?:\.\d+)?(?![\d])"#,                       // epoch
        #"\b\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp][Mm])?\b"# + zoneSuffix,                  // time only
    ].map { try! NSRegularExpression(pattern: $0) }

    /// The line's timestamp, the rest of the line with it cut out, and whether it had no date.
    static func extract(_ line: String, fallback: TimeZone, now: Date = Date()) -> (Date, String, Bool)? {
        let ns = line as NSString
        for (pi, re) in patterns.enumerated() {
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let stamp = ns.substring(with: m.range)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard let r = TimestampParser.parse(stamp, fallback: fallback, now: now) else { continue }
            let rest = ns.replacingCharacters(in: m.range, with: "")
                .replacingOccurrences(of: #"\[\s*\]|\(\s*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t-|:,;]>"))
            return (r.date, rest, pi == patterns.count - 1)
        }
        return nil
    }

    // MARK: Output

    func stamp(_ d: Date, _ tz: TimeZone) -> String {
        Fmt.formatter(hasMillis ? "yyyy-MM-dd HH:mm:ss.SSS" : "yyyy-MM-dd HH:mm:ss", tz).string(from: d)
    }

    /// Time since the previous event, or nil for the first one.
    func gap(_ i: Int) -> TimeInterval? {
        i > 0 ? events[i].date.timeIntervalSince(events[i - 1].date) : nil
    }

    /// One line per event in one zone and format, ready to paste back into a ticket or a file.
    func normalized(_ tz: TimeZone, sources: [LogSource]) -> String {
        events.map { e in
            ([stamp(e.date, tz) + " " + Fmt.abbr(tz, e.date) + "  [\(name(e, sources))] " + e.message]
             + e.extra.map { "    " + $0 }).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// A table for a postmortem: time, time since the previous event, source and event.
    func markdown(_ tz: TimeZone, sources: [LogSource]) -> String {
        func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|") }
        let zone = Fmt.abbr(tz, events.first?.date ?? Date())
        var lines = ["| Time (\(zone)) | Since previous | Source | Event |", "|---|---|---|---|"]
        for (i, e) in events.enumerated() {
            let g = gap(i).map { "+" + LogTimeline.duration($0) } ?? ""
            lines.append("| \(stamp(e.date, tz)) | \(g) | \(cell(name(e, sources))) | \(cell(e.message)) |")
        }
        if events.count > 1 {
            lines.append("")
            lines.append("\(events.count) events over \(LogTimeline.duration(span)).")
        }
        return lines.joined(separator: "\n")
    }

    private func name(_ e: LogEvent, _ sources: [LogSource]) -> String {
        sources.indices.contains(e.source) ? sources[e.source].name : "?"
    }

    /// "350ms", "42s", "4m 12s", "1h 02m", "3d 4h".
    static func duration(_ t: TimeInterval) -> String {
        let a = abs(t)
        if a < 1 { return a == 0 ? "0s" : "\(Int((a * 1000).rounded()))ms" }
        let s = Int(a.rounded(.down))
        switch s {
        case ..<60: return a.truncatingRemainder(dividingBy: 1) == 0 ? "\(s)s" : String(format: "%.1fs", a)
        case ..<3600: return "\(s / 60)m \(s % 60)s"
        case ..<86400: return "\(s / 3600)h " + String(format: "%02dm", (s % 3600) / 60)
        default: return "\(s / 86400)d \((s % 86400) / 3600)h"
        }
    }
}
