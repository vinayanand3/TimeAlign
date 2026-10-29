# TimeAlign

A small macOS menu bar app with an always-on-top panel for comparing time zones and lining up
timestamps across them.

- Add any of ~34,000 cities, a zone abbreviation (PST, IST, BST) or an IANA zone (Europe/Lisbon).
- Drag the day/night bar on any row and every row moves together.
- "Best time" banner finds the overlap of everyone's working hours.
- Paste a timestamp (ISO 8601, epoch, log formats, "3pm PDT") to see it in every zone.
- Lives in the menu bar (shows UTC); Option-Command-T shows or hides the panel.

## Install

1. Download `TimeAlign-<version>.dmg` from the [latest release](../../releases/latest).
2. Open it and drag **TimeAlign** onto **Applications**.
3. Launch TimeAlign from Applications. There's no Dock icon: look for the globe and UTC time in
   the menu bar.

Requires macOS 13 or later. Runs on Apple Silicon and Intel Macs.

## Build from source

```bash
./build.sh            # build, install to /Applications and launch
./release.sh 1.1      # universal, signed, notarized DMG in build/ (needs a Developer ID)
./appstore.sh 1.1 2   # sandboxed Mac App Store .pkg (needs App Store certificates and profile)
```

## Credits

City data from [GeoNames](https://www.geonames.org), licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). See `Resources/README.md`.

Code is MIT licensed; see `LICENSE`.
