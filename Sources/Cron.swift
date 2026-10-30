import Foundation

/// A standard five-field cron expression (minute hour day-of-month month day-of-week), or one of
/// the @hourly / @daily / @weekly / @monthly / @yearly shortcuts. Vixie cron rules: when both day
/// fields are restricted, a day matching either one runs.
struct CronExpression {
    struct Field {
        let values: [Int]      // sorted, every value the field allows
        let isAny: Bool        // written as * (or */1)
        let raw: String
    }
    let minute, hour, dom, month, dow: Field

    static let macros = [
        "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
        "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *",
    ]
    static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let dayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    enum ParseError: Error, CustomStringConvertible {
        case fieldCount(Int), bad(String, String)
        var description: String {
            switch self {
            case .fieldCount(let n): return "Expected 5 fields (minute hour day month weekday), found \(n)"
            case .bad(let field, let token): return "Can't read \"\(token)\" in the \(field) field"
            }
        }
    }

    init(_ text: String) throws {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = Self.macros[s.lowercased()] { s = m }
        let parts = s.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else { throw ParseError.fieldCount(parts.count) }
        minute = try Self.field(parts[0], "minute", 0...59)
        hour = try Self.field(parts[1], "hour", 0...23)
        dom = try Self.field(parts[2], "day of month", 1...31)
        month = try Self.field(parts[3], "month", 1...12, names: Self.monthNames, nameBase: 1)
        let d = try Self.field(parts[4], "weekday", 0...7, names: Self.dayNames, nameBase: 0)
        // 7 is Sunday too
        dow = Field(values: Array(Set(d.values.map { $0 % 7 })).sorted(), isAny: d.isAny, raw: d.raw)
    }

    private static func field(_ raw: String, _ name: String, _ range: ClosedRange<Int>,
                              names: [String] = [], nameBase: Int = 0) throws -> Field {
        func value(_ t: String) throws -> Int {
            if let i = names.firstIndex(of: t.uppercased()) { return i + nameBase }
            guard let n = Int(t), range.contains(n) else { throw ParseError.bad(name, t) }
            return n
        }
        var set = Set<Int>()
        for item in raw.split(separator: ",").map(String.init) {
            let stepParts = item.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard stepParts.count <= 2 else { throw ParseError.bad(name, item) }
            var step = 1
            if stepParts.count == 2 {
                guard let st = Int(stepParts[1]), st > 0 else { throw ParseError.bad(name, item) }
                step = st
            }
            let base = stepParts[0]
            var lo = range.lowerBound, hi = range.upperBound
            if base == "*" {
            } else if base.contains("-") {
                let b = base.split(separator: "-").map(String.init)
                guard b.count == 2 else { throw ParseError.bad(name, item) }
                lo = try value(b[0]); hi = try value(b[1])
                guard lo <= hi else { throw ParseError.bad(name, item) }
            } else {
                lo = try value(base)
                if stepParts.count == 1 { hi = lo }   // "5/15" means 5, 20, 35, 50
            }
            set.formUnion(stride(from: lo, through: hi, by: step))
        }
        guard !set.isEmpty else { throw ParseError.bad(name, raw) }
        let isAny = raw == "*" || raw == "*/1"
        return Field(values: set.sorted(), isAny: isAny, raw: raw)
    }

    // MARK: Next runs

    struct Run {
        let date: Date
        /// The cron zone skipped this wall-clock time (spring forward), so the job ran an hour off or not at all.
        var shifted = false
    }

    /// The next `count` runs after `after`, evaluated in `zone` (the zone the cron daemon runs in).
    func nextRuns(after: Date, count: Int, zone: TimeZone) -> [Run] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        var runs: [Run] = []
        var day = cal.startOfDay(for: after)
        // Eight years covers Feb 29 and every weekday/date combination.
        for _ in 0..<(366 * 8) {
            let c = cal.dateComponents([.year, .month, .day, .weekday], from: day)
            if month.values.contains(c.month!) && dayMatches(c.day!, c.weekday! - 1) {
                for h in hour.values {
                    for m in minute.values {
                        var dc = DateComponents(year: c.year, month: c.month, day: c.day, hour: h, minute: m)
                        dc.timeZone = zone
                        guard let d = cal.date(from: dc), d > after else { continue }
                        let got = cal.dateComponents([.hour, .minute], from: d)
                        if runs.last.map({ $0.date >= d }) == true { continue }   // fall-back repeat
                        runs.append(Run(date: d, shifted: got.hour != h || got.minute != m))
                        if runs.count == count { return runs }
                    }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return runs
    }

    private func dayMatches(_ d: Int, _ weekday: Int) -> Bool {
        switch (dom.isAny, dow.isAny) {
        case (true, true): return true
        case (false, true): return dom.values.contains(d)
        case (true, false): return dow.values.contains(weekday)
        case (false, false): return dom.values.contains(d) || dow.values.contains(weekday)
        }
    }

    // MARK: Plain English

    var description: String {
        let time = timeDescription
        var days: [String] = []
        if !dom.isAny { days.append("on " + (dom.values.count == 1 ? "day \(dom.values[0])" : "days \(list(dom))") + " of the month") }
        if !dow.isAny { days.append("on " + list(dow) { Self.weekdayName($0) }) }
        var s = time
        if !days.isEmpty { s += " " + days.joined(separator: " or ") }
        else if !hour.isAny && time.hasPrefix("At ") { s += " every day" }
        if !month.isAny { s += " in " + list(month) { Self.monthFull[$0 - 1] } }
        return s
    }

    private var timeDescription: String {
        let hm = { (h: Int, m: Int) in String(format: "%02d:%02d", h, m) }
        if minute.values.count == 1 && hour.values.count <= 6 && !hour.isAny {
            let times = hour.values.map { hm($0, minute.values[0]) }
            return "At " + join(times)
        }
        let mins: String
        if minute.isAny { mins = "Every minute" }
        else if let st = step(minute), minute.raw.hasPrefix("*") { mins = "Every \(st) minutes" }
        else if minute.values.count == 1 { mins = "At minute \(minute.values[0])" }
        else { mins = "At minutes \(list(minute))" }
        if hour.isAny { return minute.isAny || mins.hasPrefix("Every") ? mins : mins + " past every hour" }
        if let st = step(hour), hour.raw.hasPrefix("*") { return mins + " of every \(st) hours" }
        return mins + (hour.values.count == 1 ? " of hour \(hour.values[0])" : " of hours \(list(hour))")
    }

    private func step(_ f: Field) -> Int? {
        let p = f.raw.split(separator: "/")
        return p.count == 2 ? Int(p[1]) : nil
    }

    private static func weekdayName(_ d: Int) -> String { weekdayFull[d] }
    private static let weekdayFull = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let monthFull = ["January", "February", "March", "April", "May", "June", "July",
                                    "August", "September", "October", "November", "December"]

    /// "1 through 5" for a run, otherwise "1, 15 and 28".
    private func list(_ f: Field, _ name: (Int) -> String = { String($0) }) -> String {
        let v = f.values
        if v.count > 2, v.last! - v.first! == v.count - 1 { return "\(name(v.first!)) through \(name(v.last!))" }
        return join(v.map(name))
    }

    private func join(_ items: [String]) -> String {
        items.count <= 1 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}
