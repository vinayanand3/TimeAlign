import Foundation

struct CityEntry: Hashable {
    let name: String
    let subtitle: String
    let tzID: String
}

enum Cities {
    /// Zone shorthands people type instead of a city. Cities come from the bundled world list.
    static let shorthands: [CityEntry] = [
        .init(name: "UTC", subtitle: "Coordinated Universal Time", tzID: "UTC"),
        .init(name: "GMT", subtitle: "Greenwich Mean Time", tzID: "GMT"),
        .init(name: "PST / PDT", subtitle: "Pacific Time", tzID: "America/Los_Angeles"),
        .init(name: "MST / MDT", subtitle: "Mountain Time", tzID: "America/Denver"),
        .init(name: "CST / CDT", subtitle: "Central Time", tzID: "America/Chicago"),
        .init(name: "EST / EDT", subtitle: "Eastern Time", tzID: "America/New_York"),
        .init(name: "IST", subtitle: "India Standard Time", tzID: "Asia/Kolkata"),
        .init(name: "CET / CEST", subtitle: "Central European Time", tzID: "Europe/Berlin"),
        .init(name: "JST", subtitle: "Japan Standard Time", tzID: "Asia/Tokyo"),
    ]

    /// A searchable entry with its match keys folded once up front (case and diacritics).
    private struct Indexed {
        let entry: CityEntry
        let population: Int
        let name: String
        let aliases: [String]
        let subtitle: String
        /// Every key above plus the zone id as UTF-8, so one byte search rules out most entries.
        let haystack: [UInt8]
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func index(_ e: CityEntry, population: Int, aliases: [String] = []) -> Indexed {
        let name = fold(e.name), folded = aliases.map(fold), subtitle = fold(e.subtitle)
        return Indexed(entry: e, population: population, name: name, aliases: folded, subtitle: subtitle,
                       haystack: Array(([name, subtitle, fold(e.tzID)] + folded).joined(separator: "\u{1}").utf8))
    }

    /// Shorthands, then ~34k cities (GeoNames cities15000, pop >= 15k), then IANA zone names.
    private static let all: [Indexed] = {
        var out = shorthands.map { index($0, population: .max) }
        var seen = Set<String>()
        for line in loadWorldList().split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5 else { continue }
            let e = CityEntry(name: f[0], subtitle: f[1], tzID: f[2])
            seen.insert(fold(e.name) + "|" + e.tzID)
            out.append(index(e, population: Int(f[3]) ?? 0,
                             aliases: f[4].split(separator: ",").map(String.init)))
        }
        // Zone names cover places too small for the list and let "Europe/Lisbon" match.
        for id in TimeZone.knownTimeZoneIdentifiers {
            let city = id.split(separator: "/").last.map(String.init)?
                .replacingOccurrences(of: "_", with: " ") ?? id
            if seen.contains(fold(city) + "|" + id) { continue }
            out.append(index(CityEntry(name: city, subtitle: id, tzID: id), population: 0))
        }
        return out
    }()

    /// Parse the list off the main thread at launch so the first keystroke doesn't stall.
    static func preload() { DispatchQueue.global(qos: .utility).async { _ = all.count } }

    /// cities.tsv sits in the app's Resources; under `swift run` fall back to the source tree.
    private static func loadWorldList() -> String {
        let bundled = Bundle.main.url(forResource: "cities", withExtension: "tsv")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/cities.tsv")
        for url in [bundled, source].compactMap({ $0 }) {
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        }
        return ""
    }

    static func search(_ q: String) -> [CityEntry] {
        let query = fold(q.trimmingCharacters(in: .whitespaces))
        guard !query.isEmpty else { return [] }

        // Lower is better. Within a tier, bigger cities first.
        func tier(_ c: Indexed) -> Int? {
            if c.name == query { return 0 }
            if c.name.hasPrefix(query) { return 1 }
            if c.aliases.contains(where: { $0.hasPrefix(query) }) { return 2 }
            if c.name.contains(" " + query) || c.name.contains("-" + query) { return 2 }  // "delhi" -> New Delhi
            if c.name.contains(query) { return 3 }
            if c.subtitle.contains(query) { return 4 }                                    // "texas"
            return 5                                                                      // zone id: "europe/lis"
        }

        let needle = Array(query.utf8)
        var results: [(Int, Int, CityEntry)] = all.compactMap { c in
            // memmem: String.contains does full Unicode comparison and is ~10x slower across 34k cities
            let hit = c.haystack.withUnsafeBytes { h in
                needle.withUnsafeBytes { n in memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil }
            }
            guard hit else { return nil }
            return tier(c).map { ($0, c.population, c.entry) }
        }
        // Raw abbreviation (e.g. "BST", "AEST"), unless a shorthand above already covers it
        let shorthandHit = shorthands.contains { fold($0.name).contains(query) }
        if !shorthandHit, query.count <= 5, let tz = TimeZone(abbreviation: query.uppercased()) {
            results.append((0, .max, CityEntry(name: query.uppercased(), subtitle: tz.identifier, tzID: tz.identifier)))
        }

        var seen = Set<String>()
        return results
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 > $1.1 }
            .map(\.2)
            .filter { seen.insert($0.name + "|" + $0.subtitle).inserted }
            .prefix(8)
            .map { $0 }
    }
}
