# TimeAlign 1.2: timestamp workbench

Goal: answer App Review's Guideline 4.3 rejection by making TimeAlign a developer tool, not another world clock.

- [x] Zones / Workbench tabs in the panel header
- [x] Inspect: format detective (what was detected, warnings: epoch unit, day/month order, missing zone, ambiguous abbreviations, DST gaps) and Copy as (ISO 8601, RFC 3339, epoch s/ms/us/ns, SQL, Slack, Discord, JavaScript, Python, HTTP date)
- [x] ID decoder: UUIDv7/v6/v1, ULID, Snowflake (Discord, X), MongoDB ObjectId
- [x] Logs: paste blocks from several sources, each with its own assumed zone; one merged timeline with gaps; copy as normalized log or Markdown table
- [x] Cron: plain-English description, next runs in every zone, flags clock changes
- [x] Services menu items (Inspect Timestamp, Build Timeline from Logs) and Shortcuts actions
- [x] Unit tests for parser, IDs, logs and cron; build; check in the app

## Review
- 19 unit tests pass (`swift test`): epoch units, microsecond ISO, zones anywhere, Apache/syslog, all warnings
  including DST gap/overlap, every ID type against known values, multi-source merge, time-only lines,
  cron descriptions, next runs and spring-forward.
- Checked in the real app: Inspect (UUIDv7, Snowflake, epoch), Logs (3 sources, 3 zones), Cron (DST shift
  shown), Zones tab unchanged, Services menu end to end, sandboxed build (App Store entitlements).
- Not verified here: Shortcuts listing the actions (metadata is generated; check in the Shortcuts app).
- Found on the way: Foundation now names UTC "GMT"; labels fixed.
