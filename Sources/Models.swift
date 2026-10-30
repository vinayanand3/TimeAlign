import Foundation

struct Place: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var subtitle: String
    var tzID: String
    var tz: TimeZone { TimeZone(identifier: tzID) ?? .current }
}

struct Overlap {
    let start: Date
    let end: Date
}

final class TimeStore: ObservableObject {
    @Published var places: [Place] { didSet { savePlaces() } }
    @Published var instant: Date = Date()
    @Published var isLive = true

    @Published var use24h: Bool = UserDefaults.standard.bool(forKey: "use24h") {
        didSet { UserDefaults.standard.set(use24h, forKey: "use24h") }
    }
    @Published var workStart: Int = (UserDefaults.standard.object(forKey: "workStart") as? Int) ?? 9 {
        didSet { UserDefaults.standard.set(workStart, forKey: "workStart") }
    }
    @Published var workEnd: Int = (UserDefaults.standard.object(forKey: "workEnd") as? Int) ?? 18 {
        didSet { UserDefaults.standard.set(workEnd, forKey: "workEnd") }
    }

    private let placesKey = "places.v1"
    private var timer: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: placesKey),
           let saved = try? JSONDecoder().decode([Place].self, from: data),
           !saved.isEmpty {
            places = saved
        } else {
            places = [
                Place(name: "UTC", subtitle: "Coordinated Universal Time", tzID: "UTC"),
                Place(name: "Pacific", subtitle: "Los Angeles, USA", tzID: "America/Los_Angeles"),
                Place(name: "Detroit", subtitle: "Michigan, USA", tzID: "America/Detroit"),
                Place(name: "Austin", subtitle: "Texas, USA", tzID: "America/Chicago"),
            ]
        }
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func savePlaces() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: placesKey)
        }
    }

    // MARK: Time control

    func tick() { if isLive { instant = Date() } }
    func goNow() { isLive = true; instant = Date() }
    func setInstant(_ d: Date) { isLive = false; instant = d }

    var home: TimeZone { places.first?.tz ?? .current }

    func secondsIntoDay(_ tz: TimeZone, _ d: Date) -> Double {
        let local = d.timeIntervalSince1970 + Double(tz.secondsFromGMT(for: d))
        var r = local.truncatingRemainder(dividingBy: 86400)
        if r < 0 { r += 86400 }
        return r
    }

    func minuteOfDay(_ tz: TimeZone, _ d: Date? = nil) -> Double {
        secondsIntoDay(tz, d ?? instant) / 60
    }

    func startOfLocalDay(_ tz: TimeZone, _ d: Date) -> Date {
        d.addingTimeInterval(-secondsIntoDay(tz, d))
    }

    /// Slider drag on a row: keep that row's local day, set its local time (snapped to 15 min).
    func setMinute(_ minute: Double, in tz: TimeZone) {
        let start = startOfLocalDay(tz, instant)
        let snapped = min(max((minute / 15).rounded() * 15, 0), 1425)
        setInstant(start.addingTimeInterval(snapped * 60))
    }

    /// Date picker: change the home zone's calendar date, keep its time of day.
    func setDay(_ day: Date) {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        guard let start = cal.date(from: comps) else { return }
        setInstant(start.addingTimeInterval(minuteOfDay(home) * 60))
    }

    var homeDayForPicker: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        let c = cal.dateComponents([.year, .month, .day], from: instant)
        return Calendar.current.date(from: c) ?? instant
    }

    /// Longest stretch of the home zone's current day where every place is inside working hours.
    var bestOverlap: Overlap? {
        guard !places.isEmpty, workEnd > workStart else { return nil }
        let dayStart = startOfLocalDay(home, instant)
        let lo = Double(workStart * 60), hi = Double(workEnd * 60)
        var best: Overlap?
        var runStart: Date?
        for step in 0...96 {
            let t = dayStart.addingTimeInterval(Double(step) * 900)
            let ok = step < 96 && places.allSatisfy { p in
                let m = minuteOfDay(p.tz, t)
                return m >= lo && m < hi
            }
            if ok {
                if runStart == nil { runStart = t }
            } else if let s = runStart {
                if best == nil || t.timeIntervalSince(s) > best!.end.timeIntervalSince(best!.start) {
                    best = Overlap(start: s, end: t)
                }
                runStart = nil
            }
        }
        return best
    }

    // MARK: Places

    func add(_ p: Place) {
        if places.contains(where: { $0.tzID == p.tzID && $0.name == p.name }) { return }
        places.append(p)
    }
    func remove(_ id: UUID) { places.removeAll { $0.id == id } }
    func move(_ id: UUID, by delta: Int) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < places.count else { return }
        places.swapAt(i, j)
    }
    func makeHome(_ id: UUID) {
        guard let i = places.firstIndex(where: { $0.id == id }), i > 0 else { return }
        let p = places.remove(at: i)
        places.insert(p, at: 0)
    }

    // MARK: Clipboard text

    func summaryText() -> String {
        places.map { p in
            "\(p.name): \(Fmt.time(instant, p.tz, use24h)) \(Fmt.abbr(p.tz, instant)), \(Fmt.day(instant, p.tz))"
        }.joined(separator: "\n")
    }

    func isoUTC() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: instant)
    }
}

// MARK: Formatting

enum Fmt {
    private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()   // Services and tests can format off the main thread

    static func formatter(_ pattern: String, _ tz: TimeZone) -> DateFormatter {
        let key = pattern + "|" + tz.identifier
        lock.lock(); defer { lock.unlock() }
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = pattern
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        cache[key] = f
        return f
    }

    static func time(_ d: Date, _ tz: TimeZone, _ h24: Bool) -> String {
        formatter(h24 ? "HH:mm" : "h:mm a", tz).string(from: d)
    }

    static func day(_ d: Date, _ tz: TimeZone) -> String {
        formatter("EEE, MMM d", tz).string(from: d)
    }

    static func abbr(_ tz: TimeZone, _ d: Date) -> String {
        // Foundation now reports TimeZone(identifier: "UTC") as "GMT"; it's the same zone, and UTC is what logs say.
        if tz.identifier == "UTC" || tz.identifier == "GMT" { return "UTC" }
        return tz.abbreviation(for: d) ?? ""
    }

    /// The zone's IANA name, with UTC spelled UTC.
    static func zoneName(_ tz: TimeZone) -> String { tz.identifier == "GMT" ? "UTC" : tz.identifier }

    static func hm(_ secs: Int) -> String {
        let a = abs(secs)
        let h = a / 3600, m = (a % 3600) / 60
        return m == 0 ? "\(h)" : "\(h):" + String(format: "%02d", m)
    }

    static func utcOffset(_ tz: TimeZone, _ d: Date) -> String {
        let s = tz.secondsFromGMT(for: d)
        return "UTC" + (s < 0 ? "\u{2212}" : "+") + hm(s)
    }

    static func relative(_ tz: TimeZone, to home: TimeZone, _ d: Date) -> String {
        let diff = tz.secondsFromGMT(for: d) - home.secondsFromGMT(for: d)
        if diff == 0 { return "same time" }
        return hm(diff) + "h " + (diff < 0 ? "behind" : "ahead")
    }

    static func hourLabel(_ h: Int, _ h24: Bool) -> String {
        if h24 { return String(format: "%02d:00", h) }
        let hr = h % 12 == 0 ? 12 : h % 12
        return "\(hr) \(h < 12 ? "am" : "pm")"
    }
}
