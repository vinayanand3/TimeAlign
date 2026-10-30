import Foundation

/// The workbench's "what is this string?" answer: a timestamp in any supported format or an ID
/// with a time inside it, what it was read as, and what to double-check.
struct Inspection {
    let kind: String
    let date: Date
    var details: [String] = []
    var warnings: [String] = []
    /// Other plausible readings of the same text.
    var alternatives: [(kind: String, date: Date)] = []
}

enum Inspector {
    enum Outcome {
        case found(Inspection)
        case failed(String)
    }

    static func inspect(_ raw: String, fallback: TimeZone, now: Date = Date()) -> Outcome {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failed("") }
        if let why = IDDecoder.timeless(text) { return .failed(why) }

        let ids = IDDecoder.decode(text, now: now)
        let parsed = TimestampParser.parse(text, fallback: fallback, now: now)

        if let p = parsed, ids.isEmpty || isPlausible(p.date, now) {
            return .found(Inspection(kind: p.format.isEmpty ? "Timestamp" : capitalized(p.format), date: p.date,
                                     details: ["Zone: \(p.zoneNote)"], warnings: p.warnings,
                                     alternatives: ids.map { ($0.kind, $0.date) }))
        }
        if let first = ids.first {
            var alts = ids.dropFirst().map { ($0.kind, $0.date) }
            if let p = parsed { alts.append((capitalized(p.format), p.date)) }
            var warnings: [String] = []
            if first.kind.hasPrefix("Snowflake") && ids.count > 1 {
                warnings.append("Discord and X use the same layout with different epochs; pick the service the ID came from.")
            }
            return .found(Inspection(kind: first.kind, date: first.date, details: [first.detail],
                                     warnings: warnings, alternatives: alts))
        }
        return .failed("Couldn't read that as a timestamp or an ID with a time in it")
    }

    private static func isPlausible(_ d: Date, _ now: Date) -> Bool {
        let years = d.timeIntervalSince(now) / (365.25 * 86400)
        return years > -40 && years < 30
    }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    // MARK: Copy as

    /// The instant spelled the ways engineers paste it: APIs, databases, chat apps and code.
    static func copyFormats(_ d: Date, home: TimeZone) -> [(label: String, value: String)] {
        let utc = TimeZone(identifier: "UTC")!
        let ms = (d.timeIntervalSince1970 * 1000).rounded()
        let secs = Int64((ms / 1000).rounded(.down))
        let hasMillis = ms.truncatingRemainder(dividingBy: 1000) != 0
        let iso = Fmt.formatter(hasMillis ? "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" : "yyyy-MM-dd'T'HH:mm:ss'Z'", utc).string(from: d)
        let rfc = Fmt.formatter(hasMillis ? "yyyy-MM-dd'T'HH:mm:ss.SSSxxx" : "yyyy-MM-dd'T'HH:mm:ssxxx", home).string(from: d)
        let sql = Fmt.formatter(hasMillis ? "yyyy-MM-dd HH:mm:ss.SSS" : "yyyy-MM-dd HH:mm:ss", utc).string(from: d)
        let c = Calendar.utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: Double(secs)))
        let micro = Int(ms - Double(secs) * 1000) * 1000
        let py = "datetime(\(c.year!), \(c.month!), \(c.day!), \(c.hour!), \(c.minute!), \(c.second!)"
            + (hasMillis ? ", \(micro)" : "") + ", tzinfo=timezone.utc)"
        let homeLabel = Fmt.abbr(home, d)
        return [
            ("ISO 8601 (UTC)", iso),
            ("RFC 3339 (\(homeLabel))", rfc),
            ("Epoch seconds", String(secs)),
            ("Epoch milliseconds", String(Int64(ms))),
            ("Epoch microseconds", String(Int64(ms) * 1000)),
            ("Epoch nanoseconds", String(Int64(ms) * 1_000_000)),
            ("SQL (UTC)", "'\(sql)'"),
            ("HTTP date (RFC 9110)", Fmt.formatter("EEE, dd MMM yyyy HH:mm:ss 'GMT'", utc).string(from: d)),
            ("Slack", "<!date^\(secs)^{date_short_pretty} {time}|\(Fmt.formatter("yyyy-MM-dd HH:mm", utc).string(from: d)) UTC>"),
            ("Discord", "<t:\(secs):F>"),
            ("Discord (relative)", "<t:\(secs):R>"),
            ("JavaScript", "new Date(\"\(iso)\")"),
            ("Python", py),
            ("Human (\(homeLabel))", Fmt.formatter("EEE, MMM d, yyyy h:mm a", home).string(from: d) + " " + homeLabel),
        ]
    }
}

extension Calendar {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
