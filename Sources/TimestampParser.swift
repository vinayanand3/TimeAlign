import Foundation

/// Turns a pasted log/ticket timestamp into an absolute instant.
/// Handles ISO 8601 (with Z or offset), Unix epoch (s or ms), and common
/// human formats with an optional trailing zone like "PDT", "IST", "UTC+5:30".
/// If the text carries no zone, `fallback` is used.
enum TimestampParser {
    struct Result {
        let date: Date
        let zoneNote: String
    }

    static let abbreviations: [String: String] = [
        "UTC": "UTC", "GMT": "GMT", "Z": "UTC",
        "PST": "America/Los_Angeles", "PDT": "America/Los_Angeles",
        "MST": "America/Denver", "MDT": "America/Denver",
        "CST": "America/Chicago", "CDT": "America/Chicago",
        "EST": "America/New_York", "EDT": "America/New_York",
        "IST": "Asia/Kolkata", "JST": "Asia/Tokyo", "KST": "Asia/Seoul",
        "CET": "Europe/Berlin", "CEST": "Europe/Berlin",
        "BST": "Europe/London", "SGT": "Asia/Singapore",
        "AEST": "Australia/Sydney", "AEDT": "Australia/Sydney",
    ]

    static func parse(_ raw: String, fallback: TimeZone) -> Result? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()\"'"))
        guard !text.isEmpty else { return nil }

        // Epoch seconds or milliseconds
        if text.allSatisfy(\.isNumber), let n = Double(text) {
            if text.count == 13 { return Result(date: Date(timeIntervalSince1970: n / 1000), zoneNote: "epoch ms") }
            if text.count == 10 { return Result(date: Date(timeIntervalSince1970: n), zoneNote: "epoch s") }
        }

        // ISO 8601 with zone
        let iso = ISO8601DateFormatter()
        for opts: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
        ] {
            iso.formatOptions = opts
            if let d = iso.date(from: text) { return Result(date: d, zoneNote: "ISO 8601") }
        }

        // Pull off a trailing zone token
        var zone = fallback
        var note = "assumed \(Fmt.abbr(fallback, Date()))"
        let offsetPattern = #"\s*(?:UTC|GMT)?\s*([+-])(\d{1,2}):?(\d{2})?$"#
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
        } else if let last = text.split(separator: " ").last,
                  let id = abbreviations[last.uppercased()],
                  let tz = TimeZone(identifier: id) {
            zone = tz; note = "from \(last.uppercased())"
            text = text.split(separator: " ").dropLast().joined(separator: " ")
        } else if text.hasSuffix("Z") {
            zone = TimeZone(identifier: "UTC")!; note = "from Z"
            text.removeLast()
        }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss,SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
            "MM/dd/yyyy h:mm:ss a", "MM/dd/yyyy h:mm a", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm",
            "M/d/yyyy h:mm a", "M/d/yy h:mm a", "M/d/yyyy, h:mm:ss a", "M/d/yyyy, h:mm a",
            "MMM d, yyyy h:mm a", "MMM d, yyyy 'at' h:mm a", "MMM d yyyy HH:mm", "MMM d, yyyy HH:mm",
            "EEE, d MMM yyyy HH:mm:ss", "EEE MMM d HH:mm:ss yyyy", "d MMM yyyy HH:mm",
            "dd-MMM-yyyy HH:mm:ss", "dd.MM.yyyy HH:mm",
        ]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: text) { return Result(date: d, zoneNote: note) }
        }

        // Time only ("3:15 PM", "15:15") on today's date in that zone
        for fmt in ["h:mm a", "h:mma", "HH:mm", "HH:mm:ss"] {
            f.dateFormat = fmt
            if let t = f.date(from: text) {
                var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
                let tc = cal.dateComponents([.hour, .minute, .second], from: t)
                if let d = cal.date(bySettingHour: tc.hour ?? 0, minute: tc.minute ?? 0,
                                    second: tc.second ?? 0, of: Date()) {
                    return Result(date: d, zoneNote: note + ", today")
                }
            }
        }

        // Last resort: Apple's natural-language date detector
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let m = det.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let d = m.date {
            return Result(date: d, zoneNote: "best guess")
        }
        return nil
    }
}
