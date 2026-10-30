import Foundation
import Testing
@testable import TimeAlign

private let utc = TimeZone(identifier: "UTC")!
private let la = TimeZone(identifier: "America/Los_Angeles")!
private let now = ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z")!
private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

@Suite struct ParserTests {
    @Test func epochUnits() throws {
        #expect(iso(try #require(TimestampParser.parse("1761739200", fallback: utc)).date) == "2025-10-29T12:00:00Z")
        let ms = try #require(TimestampParser.parse("1761739200123", fallback: utc))
        #expect(ms.format == "Unix epoch milliseconds")
        #expect(ms.warnings.contains { $0.contains("seconds it would be") })
        #expect(iso(try #require(TimestampParser.parse("1761739200123456", fallback: utc)).date) == "2025-10-29T12:00:00Z")
        #expect(iso(try #require(TimestampParser.parse("1761739200123456789", fallback: utc)).date) == "2025-10-29T12:00:00Z")
    }

    @Test func isoWithMicroseconds() throws {
        let r = try #require(TimestampParser.parse("2026-10-28T14:02:11.123456Z", fallback: la))
        #expect(r.date.timeIntervalSince1970 == 1_793_196_131.123)
        #expect(r.warnings.contains { $0.contains("dropped") })
    }

    @Test func zoneAnywhere() throws {
        let r = try #require(TimestampParser.parse("Wed Oct 28 14:15:00 PDT 2026", fallback: utc))
        #expect(iso(r.date) == "2026-10-28T21:15:00Z")
    }

    @Test func apacheAndSyslog() throws {
        let a = try #require(TimestampParser.parse("28/Oct/2026:14:02:11 -0700", fallback: utc))
        #expect(iso(a.date) == "2026-10-28T21:02:11Z")
        let s = try #require(TimestampParser.parse("Oct 28 14:02:11", fallback: utc, now: now))
        #expect(iso(s.date) == "2026-10-28T14:02:11Z")
    }

    @Test func warnings() throws {
        let noZone = try #require(TimestampParser.parse("2026-10-28 14:00", fallback: la))
        #expect(noZone.warnings.contains { $0.contains("No zone") })
        let dm = try #require(TimestampParser.parse("03/04/2026 10:00", fallback: utc))
        #expect(dm.warnings.contains { $0.contains("4 Mar") == false && $0.contains("day/month") })
        let ist = try #require(TimestampParser.parse("2026-10-28 14:00 IST", fallback: utc))
        #expect(ist.warnings.contains { $0.contains("ambiguous") })
        let gap = try #require(TimestampParser.parse("2026-03-08 02:30", fallback: la))
        #expect(gap.warnings.contains { $0.contains("doesn't exist") })
        let twice = try #require(TimestampParser.parse("2026-11-01 01:30", fallback: la))
        #expect(twice.warnings.contains { $0.contains("happens twice") })
        let normal = try #require(TimestampParser.parse("2026-11-02 01:30", fallback: la))
        #expect(!normal.warnings.contains { $0.contains("twice") || $0.contains("doesn't exist") })
    }
}

@Suite struct IDTests {
    @Test func uuidV7() throws {
        let d = try #require(IDDecoder.uuid("019a3a0a-7c00-7abc-8def-0123456789ab"))
        #expect(d.kind == "UUIDv7")
        #expect(d.date.timeIntervalSince1970 == Double(0x019a3a0a7c00) / 1000)
    }
    @Test func uuidV1() throws {
        // RFC 4122 example: 1998-02-04 22:13:53 UTC
        let d = try #require(IDDecoder.uuid("e6f9a2a0-9d9e-11d1-80b4-00c04fd430c8"))
        #expect(iso(d.date).hasPrefix("1998-02-0"))
    }
    @Test func uuidV4HasNoTime() {
        #expect(IDDecoder.timeless("9b2c6f1e-3a4d-4e5f-8a6b-7c8d9e0f1a2b") != nil)
    }
    @Test func ulid() throws {
        let d = try #require(IDDecoder.ulid("01ARYZ6S41TSV4RRFFQ69G5FAV"))
        #expect(d.date.timeIntervalSince1970 == 1_469_918_176.385)
    }
    @Test func objectID() throws {
        let d = try #require(IDDecoder.objectID("507f1f77bcf86cd799439011"))
        #expect(iso(d.date) == "2012-10-17T21:13:27Z")
    }
    @Test func snowflakes() {
        // Discord's documented example: 175928847299117063 is 2016-04-30 11:18:25.796 UTC
        let all = IDDecoder.snowflakes("175928847299117063", now: now)
        let discord = all.first { $0.kind.contains("Discord") }
        #expect(discord.map { $0.date.timeIntervalSince1970 } == 1_462_015_105.796)
    }
    @Test func inspectorPrefersEpochForPlausibleDigits() {
        guard case .found(let i) = Inspector.inspect("1761739200123", fallback: utc, now: now) else { Issue.record(); return }
        #expect(i.kind == "Unix epoch milliseconds")
        guard case .found(let s) = Inspector.inspect("175928847299117063", fallback: utc, now: now) else { Issue.record(); return }
        #expect(s.kind == "Snowflake (Discord)")
    }
}

@Suite struct LogTests {
    @Test func mergesSourcesInDifferentZones() {
        let app = LogSource(name: "app", zoneID: "America/Los_Angeles", text: """
        2026-10-28 14:02:11,120 INFO deploy started
        2026-10-28 14:06:23 ERROR timeout
          at handler.swift:42
        """)
        let alerts = LogSource(name: "pager", zoneID: "UTC", text: """
        [2026-10-28T21:05:00Z] alert fired: p99 latency
        """)
        let t = LogTimeline.build([app, alerts], now: now)
        #expect(t.events.map(\.message) == ["INFO deploy started", "alert fired: p99 latency", "ERROR timeout"])
        #expect(t.events[2].extra == ["  at handler.swift:42"])
        #expect(LogTimeline.duration(t.gap(1)!) == "2m 48s")
        let md = t.markdown(utc, sources: [app, alerts])
        #expect(md.contains("| 2026-10-28 21:05:00.000 | +2m 48s | pager | alert fired: p99 latency |"))
    }

    @Test func timeOnlyLinesJoinTheIncidentDay() {
        let logs = LogSource(name: "app", zoneID: "UTC", text: "2026-10-20 21:00:00 deploy\n2026-10-20 21:30:00 done")
        let chat = LogSource(name: "slack", zoneID: "UTC", text: "9:07 PM Bob: rolling back")
        let t = LogTimeline.build([logs, chat], now: now)
        #expect(t.events.map(\.message) == ["deploy", "Bob: rolling back", "done"])
        #expect(iso(t.events[1].date) == "2026-10-20T21:07:00Z")
    }

    @Test func extractsCommonLogFormats() throws {
        let lines = [
            "127.0.0.1 - - [28/Oct/2026:14:02:11 -0700] \"GET / HTTP/1.1\" 200",
            "Oct  8 14:02:11 host sshd[42]: Accepted",
            "ts=1761739200 level=info msg=ok",
            "Alice  10:42 AM  rolling back",
        ]
        for l in lines { #expect(LogTimeline.extract(l, fallback: utc, now: now) != nil, "\(l)") }
        #expect(LogTimeline.extract("no time here", fallback: utc) == nil)
    }
}

@Suite struct CronTests {
    @Test func weekdaysAtNine() throws {
        let c = try CronExpression("0 9 * * 1-5")
        #expect(c.description == "At 09:00 on Monday through Friday")
        #expect(try CronExpression("30 2 * * *").description == "At 02:30 every day")
        // 2026-10-29 is a Thursday
        let runs = c.nextRuns(after: now, count: 3, zone: utc)
        #expect(runs.map { iso($0.date) } == ["2026-10-30T09:00:00Z", "2026-11-02T09:00:00Z", "2026-11-03T09:00:00Z"])
    }
    @Test func descriptions() throws {
        #expect(try CronExpression("*/15 * * * *").description == "Every 15 minutes")
        #expect(try CronExpression("@monthly").description == "At 00:00 on day 1 of the month")
        #expect(try CronExpression("30 * * * *").description == "At minute 30 past every hour")
        #expect(try CronExpression("0 0 1,15 * *").description == "At 00:00 on days 1 and 15 of the month")
    }
    @Test func errors() {
        #expect(throws: CronExpression.ParseError.self) { try CronExpression("61 * * * *") }
        #expect(throws: CronExpression.ParseError.self) { try CronExpression("* * *") }
    }
    @Test func springForwardIsFlagged() throws {
        let c = try CronExpression("30 2 * * *")
        let runs = c.nextRuns(after: ISO8601DateFormatter().date(from: "2026-03-07T12:00:00Z")!, count: 2, zone: la)
        #expect(runs[0].shifted == true)   // 2026-03-08 02:30 doesn't exist in LA
        #expect(runs[1].shifted == false)
    }
}
