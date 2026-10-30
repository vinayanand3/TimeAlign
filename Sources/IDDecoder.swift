import Foundation

/// Pulls the creation time out of IDs that carry one: UUID v1/v6/v7, ULID, Snowflake
/// (Discord, X/Twitter) and MongoDB ObjectId.
enum IDDecoder {
    struct Decoded: Equatable {
        let kind: String
        let date: Date
        let detail: String
    }

    /// Every reading that fits, most likely first. Empty if the text isn't a recognized ID.
    static func decode(_ raw: String, now: Date = Date()) -> [Decoded] {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = uuid(s) { return [u] }
        if let u = ulid(s) { return [u] }
        if let o = objectID(s) { return [o] }
        return snowflakes(s, now: now)
    }

    /// True when the text looks like an ID that holds no time (e.g. UUIDv4), with the reason.
    static func timeless(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard s.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil else { return nil }
        let v = s[s.index(s.startIndex, offsetBy: 14)]
        return ["1", "6", "7"].contains(v) ? nil : "UUID version \(v) holds no timestamp (only v1, v6 and v7 do)."
    }

    // MARK: UUID

    static func uuid(_ s: String) -> Decoded? {
        let lower = s.lowercased()
        guard lower.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil else { return nil }
        let hex = lower.replacingOccurrences(of: "-", with: "")
        let version = hex[hex.index(hex.startIndex, offsetBy: 12)]
        func field(_ from: Int, _ len: Int) -> UInt64 {
            let a = hex.index(hex.startIndex, offsetBy: from)
            return UInt64(hex[a..<hex.index(a, offsetBy: len)], radix: 16)!
        }
        // v1 and v6 count 100 ns ticks since the Gregorian calendar began (1582-10-15).
        let gregorianOffset: Double = 12_219_292_800
        switch version {
        case "7":
            let ms = field(0, 12)
            return Decoded(kind: "UUIDv7", date: Date(timeIntervalSince1970: Double(ms) / 1000),
                           detail: "First 48 bits: \(ms) ms since 1970")
        case "6":
            let ticks = field(0, 8) << 28 | field(8, 4) << 12 | field(13, 3)
            return Decoded(kind: "UUIDv6", date: Date(timeIntervalSince1970: Double(ticks) / 1e7 - gregorianOffset),
                           detail: "60-bit timestamp, 100 ns ticks since 1582")
        case "1":
            let ticks = field(13, 3) << 48 | field(8, 4) << 32 | field(0, 8)
            return Decoded(kind: "UUIDv1", date: Date(timeIntervalSince1970: Double(ticks) / 1e7 - gregorianOffset),
                           detail: "60-bit timestamp, 100 ns ticks since 1582; the last 12 hex digits are usually a MAC address")
        default:
            return nil
        }
    }

    // MARK: ULID

    static func ulid(_ s: String) -> Decoded? {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let upper = s.uppercased()
        guard upper.count == 26, upper.allSatisfy({ alphabet.contains($0) }) else { return nil }
        var ms: UInt64 = 0
        for c in upper.prefix(10) { ms = ms << 5 | UInt64(alphabet.firstIndex(of: c)!) }
        // The first character can only be 0-7 (48 bits); anything else isn't a ULID.
        guard ms < 1 << 48 else { return nil }
        return Decoded(kind: "ULID", date: Date(timeIntervalSince1970: Double(ms) / 1000),
                       detail: "First 10 characters: \(ms) ms since 1970")
    }

    // MARK: MongoDB ObjectId

    static func objectID(_ s: String) -> Decoded? {
        let lower = s.lowercased()
        guard lower.count == 24, lower.allSatisfy(\.isHexDigit), let secs = UInt32(lower.prefix(8), radix: 16) else { return nil }
        return Decoded(kind: "MongoDB ObjectId", date: Date(timeIntervalSince1970: Double(secs)),
                       detail: "First 4 bytes: \(secs) s since 1970")
    }

    // MARK: Snowflake

    static let snowflakeEpochs: [(name: String, ms: UInt64)] = [
        ("Discord", 1_420_070_400_000),
        ("X / Twitter", 1_288_834_974_657),
    ]

    /// 64-bit IDs whose top 42 bits are milliseconds since a service's own epoch.
    /// Only readings between the service's start and a day from now are kept.
    static func snowflakes(_ s: String, now: Date) -> [Decoded] {
        guard (15...20).contains(s.count), s.allSatisfy(\.isNumber), let id = UInt64(s) else { return [] }
        return snowflakeEpochs.compactMap { e in
            let ms = (id >> 22) + e.ms
            let d = Date(timeIntervalSince1970: Double(ms) / 1000)
            guard d.timeIntervalSince1970 * 1000 >= Double(e.ms), d < now.addingTimeInterval(86400) else { return nil }
            return Decoded(kind: "Snowflake (\(e.name))", date: d,
                           detail: "id >> 22 = \(id >> 22) ms since the \(e.name) epoch")
        }
    }
}
