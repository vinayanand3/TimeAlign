import Foundation

/// Turns a pasted log/ticket timestamp into an absolute instant.
/// Handles ISO 8601 (with Z or offset), Unix epoch (s, ms, us, ns), and common
/// human and log formats with an optional zone like "PDT", "IST", "UTC+5:30".
/// If the text carries no zone, `fallback` is used.
enum TimestampParser {
    struct Result {
        let date: Date
        let zoneNote: String
        /// What the text was read as, e.g. "ISO 8601" or "pattern yyyy-MM-dd HH:mm:ss".
        var format: String = ""
        /// Things a careful reader should know: other readings, assumed parts, clock changes.
        var warnings: [String] = []
    }

    static let abbreviations: [String: String] = [
        "UTC": "UTC", "GMT": "GMT", "Z": "UTC",
        "PST": "America/Los_Angeles", "PDT": "America/Los_Angeles",
        "MST": "America/Denver", "MDT": "America/Denver",
        "CST": "America/Chicago", "CDT": "America/Chicago",
        "EST": "America/New_York", "EDT": "America/New_York",
        "AKST": "America/Anchorage", "AKDT": "America/Anchorage", "HST": "Pacific/Honolulu",
        "IST": "Asia/Kolkata", "JST": "Asia/Tokyo", "KST": "Asia/Seoul",
        "HKT": "Asia/Hong_Kong", "SGT": "Asia/Singapore", "PKT": "Asia/Karachi",
        "CET": "Europe/Berlin", "CEST": "Europe/Berlin", "EET": "Europe/Athens", "EEST": "Europe/Athens",
        "WET": "Europe/Lisbon", "WEST": "Europe/Lisbon", "BST": "Europe/London", "MSK": "Europe/Moscow",
        "AEST": "Australia/Sydney", "AEDT": "Australia/Sydney", "AWST": "Australia/Perth",
        "NZST": "Pacific/Auckland", "NZDT": "Pacific/Auckland", "BRT": "America/Sao_Paulo",
        "SAST": "Africa/Johannesburg",
    ]

    /// Abbreviations that mean different zones in different places.
    static let ambiguous: [String: String] = [
        "IST": "India here; also Israel and Irish Standard Time",
        "CST": "US Central here; also China Standard Time",
        "BST": "British Summer Time here; also Bangladesh Standard Time",
    ]

    static let formats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
        "yyyy/MM/dd HH:mm:ss.SSS", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
        "yyyyMMdd'T'HHmmss", "yyyyMMddHHmmss",
        "MM/dd/yyyy h:mm:ss a", "MM/dd/yyyy h:mm a", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm",
        "M/d/yyyy h:mm a", "M/d/yy h:mm a", "M/d/yyyy, h:mm:ss a", "M/d/yyyy, h:mm a",
        "MMM d, yyyy h:mm a", "MMM d, yyyy 'at' h:mm a", "MMM d yyyy HH:mm", "MMM d, yyyy HH:mm",
        "EEE, d MMM yyyy HH:mm:ss", "EEE MMM d HH:mm:ss yyyy", "d MMM yyyy HH:mm:ss", "d MMM yyyy HH:mm",
        "dd/MMM/yyyy:HH:mm:ss", "dd-MMM-yyyy HH:mm:ss", "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm",
        "yyyy-MM-dd", "yyyyMMdd", "MMM d, yyyy", "d MMM yyyy",
    ]
    /// Syslog style: no year, so it takes the current one.
    static let yearless = ["MMM d HH:mm:ss.SSS", "MMM d HH:mm:ss", "EEE MMM d HH:mm:ss"]

    static func parse(_ raw: String, fallback: TimeZone, now: Date = Date()) -> Result? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()\"'"))
        guard !text.isEmpty else { return nil }

        if let r = parseEpoch(text) { return r }

        // Sub-millisecond digits: DateFormatter and ISO8601DateFormatter only read three.
        let hadExtraDigits = text.range(of: #"\d{2}:\d{2}:\d{2}[.,]\d{4,}"#, options: .regularExpression) != nil
        text = text.replacingOccurrences(of: #"(\d{2}:\d{2}:\d{2})[.,](\d{3})\d*"#, with: "$1.$2",
                                         options: .regularExpression)
        let precisionNote = hadExtraDigits ? ["Digits after milliseconds are dropped."] : []

        // ISO 8601 with zone
        let iso = ISO8601DateFormatter()
        for opts: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
        ] {
            iso.formatOptions = opts
            if let d = iso.date(from: text) {
                return Result(date: d, zoneNote: "ISO 8601", format: "ISO 8601 / RFC 3339", warnings: precisionNote)
            }
        }

        // Pull off the zone: a trailing offset, an abbreviation anywhere, or a trailing Z
        var zone = fallback
        var note = "assumed \(Fmt.abbr(fallback, now))"
        var explicitZone = true
        var warnings = precisionNote
        let offsetPattern = #"\s*(?:UTC|GMT)?\s*([+-])(\d{1,2}):?(\d{2})?$"#
        let words = text.split(separator: " ").map(String.init)
        if let r = text.range(of: offsetPattern, options: .regularExpression),
           text[..<r.lowerBound].contains(where: \.isNumber),
           text[..<r.lowerBound].contains(":") {
            let token = String(text[r])
            let m = try! NSRegularExpression(pattern: offsetPattern)
                .firstMatch(in: token, range: NSRange(token.startIndex..., in: token))!
            let sign = (token as NSString).substring(with: m.range(at: 1)) == "-" ? -1 : 1
            let h = Int((token as NSString).substring(with: m.range(at: 2))) ?? 0
            let mins = m.range(at: 3).location != NSNotFound
                ? Int((token as NSString).substring(with: m.range(at: 3))) ?? 0 : 0
            if let tz = TimeZone(secondsFromGMT: sign * (h * 3600 + mins * 60)) {
                zone = tz; note = "from offset"
                text = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        } else if let i = words.lastIndex(where: { $0 != "Z" && abbreviations[$0.uppercased()] != nil && $0 == $0.uppercased() }),
                  let tz = TimeZone(identifier: abbreviations[words[i]]!) {
            zone = tz; note = "from \(words[i])"
            if let a = ambiguous[words[i]] { warnings.append("\(words[i]) is ambiguous: read as \(a).") }
            text = words.enumerated().filter { $0.offset != i }.map(\.element).joined(separator: " ")
        } else if text.hasSuffix("Z") {
            zone = TimeZone(identifier: "UTC")!; note = "from Z"
            text.removeLast()
        } else {
            explicitZone = false
        }
        if !explicitZone { warnings.append("No zone in the text, so it was read as \(Fmt.zoneName(zone)) time.") }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        for fmt in formats {
            f.dateFormat = fmt
            guard let d = f.date(from: text) ?? skippedByClockChange(text, fmt, zone) else { continue }
            var w = warnings
            if fmt.hasPrefix("M/") || fmt.hasPrefix("MM/") { w += dayMonthWarning(text, d, fmt, zone) }
            if fmt.contains("yy h") && !fmt.contains("yyyy") { w.append("Two-digit year, read as \(year(d, zone)).") }
            if !fmt.contains("H") && !fmt.contains("h") { w.append("No time of day, so it is midnight.") }
            w += clockChangeWarnings(text, d, fmt, zone)
            return Result(date: d, zoneNote: note, format: "pattern \(fmt)", warnings: w)
        }
        for fmt in yearless {
            f.dateFormat = fmt
            f.defaultDate = now
            guard var d = f.date(from: text) else { continue }
            // A log line from "Dec 31" read on Jan 1 belongs to last year.
            if d.timeIntervalSince(now) > 86400 * 2, let prev = Calendar.current.date(byAdding: .year, value: -1, to: d) { d = prev }
            return Result(date: d, zoneNote: note, format: "pattern \(fmt) (syslog)",
                          warnings: warnings + ["No year in the text, so it was read as \(year(d, zone))."])
        }
        f.defaultDate = nil

        // Time only ("3:15 PM", "15:15") on today's date in that zone
        for fmt in ["h:mm a", "h:mma", "h:mm:ss a", "HH:mm", "HH:mm:ss"] {
            f.dateFormat = fmt
            if let t = f.date(from: text) {
                var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
                let tc = cal.dateComponents([.hour, .minute, .second], from: t)
                if let d = cal.date(bySettingHour: tc.hour ?? 0, minute: tc.minute ?? 0,
                                    second: tc.second ?? 0, of: now) {
                    return Result(date: d, zoneNote: note + ", today", format: "time only (\(fmt))",
                                  warnings: warnings + ["No date in the text, so it is today."])
                }
            }
        }

        // Last resort: Apple's natural-language date detector
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let m = det.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let d = m.date {
            return Result(date: d, zoneNote: "best guess", format: "natural language",
                          warnings: ["Read by the natural-language detector; check the result."])
        }
        return nil
    }

    // MARK: Epoch

    /// Digits only (optionally negative, optionally with a fraction): the digit count picks the unit.
    static func parseEpoch(_ text: String) -> Result? {
        guard text.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        let intPart = text.split(separator: ".").first!.filter(\.isNumber)
        guard let n = Double(text) else { return nil }
        let units: [(digits: ClosedRange<Int>, divisor: Double, name: String)] = [
            (9...11, 1, "seconds"), (13...13, 1e3, "milliseconds"),
            (16...16, 1e6, "microseconds"), (19...19, 1e9, "nanoseconds"),
        ]
        guard let u = units.first(where: { $0.digits.contains(intPart.count) }),
              u.divisor == 1 || !text.contains(".") else { return nil }
        let d = Date(timeIntervalSince1970: n / u.divisor)
        var w: [String] = []
        // The same digits in the neighboring units, so a wrong guess is easy to spot.
        for alt in units where alt.name != u.name && abs(log10(alt.divisor / u.divisor)).rounded() == 3 {
            let other = Date(timeIntervalSince1970: n / alt.divisor)
            w.append("Read as \(alt.name) it would be \(Fmt.formatter("MMM d, yyyy", TimeZone(identifier: "UTC")!).string(from: other)).")
        }
        if u.divisor == 1e9 { w.append("Nanoseconds are rounded to the nearest microsecond.") }
        return Result(date: d, zoneNote: "epoch \(u.name)", format: "Unix epoch \(u.name)", warnings: w)
    }

    // MARK: Warnings

    private static func year(_ d: Date, _ tz: TimeZone) -> String { Fmt.formatter("yyyy", tz).string(from: d) }

    /// "03/04/2026" is March 4 in the US and 3 April almost everywhere else.
    private static func dayMonthWarning(_ text: String, _ d: Date, _ fmt: String, _ zone: TimeZone) -> [String] {
        let parts = text.split(whereSeparator: { $0 == "/" || $0 == " " || $0 == "," }).prefix(2).compactMap { Int($0) }
        guard parts.count == 2, parts[0] <= 12, parts[1] <= 12, parts[0] != parts[1] else { return [] }
        let swapped = Fmt.formatter("d MMM", zone)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        var c = cal.dateComponents([.year, .hour, .minute, .second], from: d)
        c.month = parts[1]; c.day = parts[0]
        guard let alt = cal.date(from: c) else { return [] }
        return ["Read as month/day (US). As day/month it would be \(swapped.string(from: alt))."]
    }

    /// A wall-clock time the zone skips (02:30 on a spring-forward day): DateFormatter refuses it,
    /// so read it leniently, the way the clocks would (an hour later), and let the warning say so.
    private static func skippedByClockChange(_ text: String, _ fmt: String, _ zone: TimeZone) -> Date? {
        let probe = DateFormatter()
        probe.locale = Locale(identifier: "en_US_POSIX")
        probe.timeZone = TimeZone(identifier: "UTC")
        probe.dateFormat = fmt
        guard probe.date(from: text) != nil else { return nil }
        probe.timeZone = zone
        probe.isLenient = true
        return probe.date(from: text)
    }

    /// Local times that a clock change skips (spring forward) or repeats (fall back).
    private static func clockChangeWarnings(_ text: String, _ d: Date, _ fmt: String, _ zone: TimeZone) -> [String] {
        guard fmt.contains("H") || fmt.contains("h"), !zone.isDaylightSavingTimeFixed else { return [] }
        let f = Fmt.formatter(fmt, zone)
        func same(_ a: String) -> Bool { a.caseInsensitiveCompare(text) == .orderedSame }
        if !same(f.string(from: d)) {
            return ["That local time doesn't exist in \(Fmt.zoneName(zone)): the clocks skip it. Read as \(Fmt.time(d, zone, true)) \(Fmt.abbr(zone, d))."]
        }
        for other in [d.addingTimeInterval(-3600), d.addingTimeInterval(3600)] where same(f.string(from: other)) {
            let first = min(d, other)
            return ["That local time happens twice in \(Fmt.zoneName(zone)) (clocks go back). Read as the \(d == first ? "first" : "second") one, \(Fmt.abbr(zone, d))."]
        }
        return []
    }
}

private extension TimeZone {
    /// True for zones without daylight saving (UTC, fixed offsets).
    var isDaylightSavingTimeFixed: Bool { nextDaylightSavingTimeTransition == nil }
}
