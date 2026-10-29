# TimeAlign: handoff notes

Native macOS menu bar app with an always-on-top floating panel for comparing time zones,
modeled on the Savvy Time web widget. Built for triaging and aligning timestamps across zones.

## Status
- Builds cleanly (Swift 6.4, macOS 26) and `./build.sh` installs and launches /Applications/TimeAlign.app.
- Entry point is a plain AppKit `@main enum` (not a SwiftUI `App`): the placeholder `Settings` scene
  opened an empty window at launch. A hidden Edit main menu keeps Cmd-C/V/A working in text fields.
- Panel is NOT movable by background (that stole the day-track drags); the header row is the
  drag handle (`WindowDragArea` in Views.swift). The panel is sized before its saved frame is
  restored, otherwise it drifted down by its own height on every launch.
- `build.sh` calls `/usr/bin/codesign` by absolute path because conda's `codesign` shadows it on PATH.

## Layout
- `Package.swift`: SwiftPM executable, macOS 13+.
- `Sources/App.swift`: plain AppKit `@main enum TimeAlignMain` + `AppDelegate`; accessory activation
  policy (no Dock icon); `FloatingPanel` (NSPanel, `.floating` level, all Spaces, dragged by its header,
  Esc hides, resizable with min 380x340, kept on screen); `PanelState.rowsHeightChanged` refits the
  height when cities are added or removed (top edge fixed), but a saved size wins at launch. Rows sit in
  a ScrollView. The minimum (`PanelState.minSize`) is enforced in `windowWillResize`, not
  `contentMinSize`, which the SwiftUI hosting controller keeps overwriting; menu bar status item showing UTC time;
  global hotkey Option-Command-T via Carbon `RegisterEventHotKey`.
- `Sources/Models.swift`: `TimeStore` (places persisted in UserDefaults, the selected `instant`,
  live vs. scrubbing, 24h toggle, working hours, best-overlap search in 15-min steps), `Fmt` helpers.
- `Sources/Views.swift`: `RootView` (header, search + date picker + Now, best-time banner, rows,
  timestamp bar, footer), `PlaceRow`, `DayTrack` (draggable day/night slider), `TimestampBar`.
- `Sources/Cities.swift`: search over zone shorthands (UTC, PST / PDT, IST...), ~34k world cities
  from `Resources/cities.tsv`, IANA zone names and raw abbreviations. Ranked by match quality,
  then population. Pre-folded keys plus a `memmem` prefilter keep it ~3 ms per keystroke.
- `Resources/cities.tsv`: GeoNames cities15000 (CC BY 4.0), trimmed by `tools/trim_geonames.py`;
  see `Resources/README.md`. `build.sh` copies it into the app's Resources.
- `Sources/TimestampParser.swift`: ISO 8601, epoch s/ms, many human formats, trailing zone
  abbreviations (PDT, IST...) or offsets (+05:30); falls back to a chosen zone; NSDataDetector last.
- `build.sh`: release build, wraps binary in .app with Info.plist (LSUIElement), ad-hoc codesign,
  copies to /Applications, opens it. Env switches VERSION, UNIVERSAL=1, SIGN_ID, INSTALL=0.
- `release.sh <version>`: universal Developer ID build, DMG, notarize (keychain profile `TimeAlign`),
  staple. Publish with `gh release create v<version> build/TimeAlign-<version>.dmg`.
- `appstore.sh <version> <build>`: sandboxed (`Resources/TimeAlign.entitlements` plus team/app ids)
  universal build signed with Apple Distribution, embeds `Resources/TimeAlign_AppStore.provisionprofile`
  (gitignored), wraps it in a .pkg signed with the Mac Installer Distribution cert. Upload via Transporter.
  Test the sandbox locally with `ENTITLEMENTS=Resources/TimeAlign.entitlements INSTALL=0 ./build.sh`.
- `tools/make_icon.swift`: draws the icon, writes `Resources/AppIcon.icns` and a 1024px PNG.
- `tools/make_screenshot.swift` + `AppStore/`: 2880x1800 App Store screenshots. Capture the panel by
  launching the binary with argument-domain overrides (`-places.v1 <hex data> -use24h YES
  -"NSWindow Frame TimeAlignPanel" "x y w h ..."`) so real settings are untouched, then
  `screencapture -l <window id>`. Privacy policy: `PRIVACY.md` (linked from App Store Connect).
- Gotcha: once `~/Library/Containers/com.vinay.timealign` exists (from running a sandboxed build),
  `defaults read/write com.vinay.timealign` targets the container, not the plist the normal build uses.

## Reference behavior (Savvy Time)
- Rows: name (bold), big local time on the right; subtitle "place | ABBR" and "UTC-7 | 7h behind | Wed, Oct 28".
- Each row has a day/night bar (blue night, sand day) with a knob at that zone's local time.
  Dragging any knob moves all rows together.
- Top: search "Add a city or time zone" with dropdown showing each match's current time,
  date picker (calendar popover), blue "Now" button.
- Banner: "Best time: 4:00 pm - 6:00 pm, works for all N places".
- First row is the home zone; offsets are relative to it.

## User preferences
- Don't use em dashes in replies or UI text.
- Default zones: UTC, Pacific, Detroit, Austin (Central).

## Ideas not done yet
- Launch at login via `SMAppService.mainApp.register()` toggle in the ... menu.
- Drag-to-reorder rows (currently right-click Move up/down).
