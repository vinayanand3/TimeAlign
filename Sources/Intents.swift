import AppIntents
import Foundation

// Shortcuts actions. SwiftPM doesn't run Xcode's App Intents metadata step, so build.sh runs
// appintentsmetadataprocessor itself and puts Metadata.appintents in the app's Resources.

enum TimestampFormat: String, AppEnum {
    case iso, rfc3339, epochSeconds, epochMillis, sql, http, slack, discord, human

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Timestamp Format"
    static var caseDisplayRepresentations: [TimestampFormat: DisplayRepresentation] = [
        .iso: "ISO 8601 (UTC)", .rfc3339: "RFC 3339 (local offset)", .epochSeconds: "Epoch seconds",
        .epochMillis: "Epoch milliseconds", .sql: "SQL (UTC)", .http: "HTTP date",
        .slack: "Slack date token", .discord: "Discord timestamp", .human: "Readable (local)",
    ]

    /// The label of the matching row in Inspector.copyFormats.
    var copyLabel: String {
        switch self {
        case .iso: return "ISO 8601 (UTC)"
        case .rfc3339: return "RFC 3339"
        case .epochSeconds: return "Epoch seconds"
        case .epochMillis: return "Epoch milliseconds"
        case .sql: return "SQL (UTC)"
        case .http: return "HTTP date (RFC 9110)"
        case .slack: return "Slack"
        case .discord: return "Discord"
        case .human: return "Human"
        }
    }
}

enum TimelineFormat: String, AppEnum {
    case markdown, normalized
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Timeline Format"
    static var caseDisplayRepresentations: [TimelineFormat: DisplayRepresentation] = [
        .markdown: "Markdown table", .normalized: "Normalized log",
    ]
}

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

struct ConvertTimestampIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert Timestamp"
    static var description = IntentDescription(
        "Reads a timestamp, Unix epoch or time-based ID (UUIDv7, ULID, Snowflake, ObjectId) and returns it in the format you pick.")

    @Parameter(title: "Text", description: "A timestamp, epoch or ID, e.g. 1761739200123")
    var text: String

    @Parameter(title: "Format", default: .iso)
    var format: TimestampFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$text) to \(\.$format)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard case .found(let i) = Inspector.inspect(text, fallback: .current) else {
            throw IntentFailure(message: "Couldn't read \"\(text)\" as a timestamp or an ID with a time in it.")
        }
        let value = Inspector.copyFormats(i.date, home: .current)
            .first { $0.label.hasPrefix(format.copyLabel) }!.value
        return .result(value: value)
    }
}

struct BuildTimelineIntent: AppIntent {
    static var title: LocalizedStringResource = "Build Timeline from Logs"
    static var description = IntentDescription(
        "Finds the timestamp in each line, converts them to one zone, sorts the lines and adds the gap between events.")

    @Parameter(title: "Log Lines", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Zone for lines without one", description: "An IANA zone such as America/Los_Angeles", default: "UTC")
    var assumeZone: String

    @Parameter(title: "Show times in", description: "An IANA zone such as UTC", default: "UTC")
    var outputZone: String

    @Parameter(title: "Format", default: .markdown)
    var format: TimelineFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Build a \(\.$format) timeline from \(\.$text)") {
            \.$assumeZone
            \.$outputZone
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard TimeZone(identifier: assumeZone) != nil, let out = TimeZone(identifier: outputZone) else {
            throw IntentFailure(message: "Unknown time zone. Use an IANA name such as America/New_York or UTC.")
        }
        let sources = [LogSource(name: "input", zoneID: assumeZone, text: text)]
        let t = LogTimeline.build(sources)
        guard !t.events.isEmpty else { throw IntentFailure(message: "No timestamps found in the text.") }
        return .result(value: format == .markdown ? t.markdown(out, sources: sources) : t.normalized(out, sources: sources))
    }
}

struct OpenWorkbenchIntent: AppIntent {
    static var title: LocalizedStringResource = "Inspect in TimeAlign"
    static var description = IntentDescription("Opens the TimeAlign Workbench with the text decoded.")
    static var openAppWhenRun = true

    @Parameter(title: "Text")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        TimeAlignMain.delegate.inspect(text)
        return .result()
    }
}

struct TimeAlignShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConvertTimestampIntent(), phrases: ["Convert a timestamp with \(.applicationName)"])
        AppShortcut(intent: BuildTimelineIntent(), phrases: ["Build a timeline with \(.applicationName)"])
    }
}
