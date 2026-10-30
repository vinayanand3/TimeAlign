# TimeAlign 1.2: App Store Connect text and reply to App Review

## Metadata

- **Name:** TimeAlign: Timestamp Workbench
- **Subtitle (30 max):** Decode timestamps, logs & cron
- **Primary category:** Developer Tools. **Secondary:** Utilities
- **Keywords (100 max):** timestamp,epoch,unix,log,timeline,cron,uuid,ulid,snowflake,iso8601,utc,incident,timezone,sre

### Promotional text

Paste a timestamp, an epoch or an ID and see exactly what it means. Merge logs from different systems into one timeline for your postmortem.

### Description

TimeAlign is a timestamp workbench for engineers, SREs and support teams. It lives in your menu bar and turns the timestamps you run into every day into answers.

INSPECT ANY TIMESTAMP OR ID
Paste ISO 8601, a Unix epoch in seconds, milliseconds, microseconds or nanoseconds, a log or syslog line, or a time-based ID (UUIDv1, v6 and v7, ULID, Discord and X Snowflakes, MongoDB ObjectId). TimeAlign shows what it was read as and warns you about the mistakes that cost hours: the wrong epoch unit, day and month swapped, a missing or ambiguous zone (IST, CST, BST), and local times that a clock change skips or repeats.

COPY IT THE WAY YOU NEED IT
One click copies the instant as ISO 8601, RFC 3339, epoch, a SQL literal, an HTTP date, a Slack or Discord date token, JavaScript or Python.

ONE TIMELINE FROM MANY LOGS
Paste lines from your app logs, alerts and chat, each with the zone it was written in. TimeAlign finds every timestamp, converts them to one zone, merges and sorts them, shows the gap between events and marks the longest one. Copy the result as a Markdown table for your postmortem.

CRON, EXPLAINED
Type a cron expression to read it in plain English and see its next runs in every zone you care about, including the runs a daylight saving change moves or skips.

COMPARE ZONES
Every zone your team uses on one panel, with a day/night bar you drag to move all of them together and a banner that finds the hours everyone is working.

WORKS EVERYWHERE ON YOUR MAC
Select text in any app and use the Services menu, or build automations with the Shortcuts actions Convert Timestamp and Build Timeline from Logs. Option-Command-T shows or hides the panel.

PRIVATE BY DESIGN
No account, no network access, no tracking. Everything you paste stays on your Mac.

### What's New in 1.2

- New Workbench tab with three developer tools: Inspect, Logs and Cron.
- Decode Unix epochs in any unit and the time inside UUIDv7, ULID, Snowflake and ObjectId IDs.
- Merge logs from several systems into one timeline and export it as Markdown.
- Read cron expressions in plain English with the next runs in every zone.
- Services menu items and Shortcuts actions.
- UTC is labeled UTC again on recent macOS versions.

### Review notes (App Review Information > Notes)

TimeAlign runs in the menu bar (globe icon with the UTC time). Click it or press Option-Command-T to show the panel. Click Workbench at the top. To try it: in Inspect paste 1761739200123 or 019a3a0a-7c00-7abc-8def-0123456789ab; in Logs paste a few log lines with timestamps and click Build timeline; in Cron type 30 2 * * *.

## Reply to App Review (Guidelines 4.3 and 4.2.6)

Hello,

Thank you for the review. We have made significant changes in version 1.2 (build 4) and resubmitted it. Here are our answers.

1. What the app does and the problem it solves. TimeAlign is a timestamp workbench for software engineers. Engineers constantly have to work out what a timestamp means: a Unix epoch in a log, an ID such as a UUIDv7 or a Discord Snowflake that carries its creation time, or log lines from several systems that were each written in a different time zone. Getting this wrong (reading milliseconds as seconds, swapping day and month, assuming the wrong zone, missing a daylight saving change) is a common cause of mistakes during incidents. TimeAlign decodes any timestamp or time-based ID, says what it was read as and what to double-check, merges logs from several sources into one sorted timeline in one zone with the gaps between events, and explains cron schedules with their next runs across zones. Zone comparison is one supporting view, not the product.

2. Intended users. Software engineers, site reliability engineers and on-call staff who investigate incidents across services and teams in different zones, and support engineers who match customer reports to server logs.

3. The gap it fills. World clock apps convert a time you type. None that we know of decodes epochs in every unit with warnings about the likely misreading, extracts times from UUIDv7, ULID, Snowflake and ObjectId IDs, merges log lines from several systems written in different zones into one timeline with a Markdown export for postmortems, or shows when daylight saving changes move or skip cron runs. Developers today do this with ad hoc scripts and several websites; TimeAlign does it offline in the menu bar, from the Services menu in any app, and in Shortcuts.

4. Beta testing. [YOUR ANSWER: describe who used the TestFlight or GitHub builds and real feedback that changed the app. Only include feedback that actually happened.]

5. Standalone or suite. Standalone. It is the only app on our developer account.

6. Could it be an in-app purchase in another app on the account? No. There are no other apps on the account.

7. Shared code with other apps on the account. None. There are no other apps.

8. Shared code with third-party apps. No. The app uses only Apple frameworks (SwiftUI, AppKit, Foundation, App Intents). City names come from the GeoNames cities15000 dataset (CC BY 4.0), used for the zone search.

9. Created for a client or from a template? No. I designed and wrote the app myself, and it is submitted under my own developer account. It was not made from a template or an app generation service.

Thank you,
Vinay Bhaskarla
