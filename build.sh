#!/bin/bash
# Builds build/TimeAlign.app. By default: native arch, ad-hoc signed, copied to /Applications and opened.
# Needs Xcode or the Command Line Tools (xcode-select --install).
#
# Options (environment variables, used by release.sh):
#   VERSION=1.2        CFBundleShortVersionString (default 1.0)
#   BUILD=7            CFBundleVersion (default: same as VERSION); App Store uploads need a new one each time
#   UNIVERSAL=1        build for Apple Silicon and Intel
#   SIGN_ID="Developer ID Application: ..."   sign with hardened runtime instead of ad-hoc
#   ENTITLEMENTS=file  sign with these entitlements (App Store: Resources/TimeAlign.entitlements)
#   PROFILE=file       embed this provisioning profile (App Store)
#   INSTALL=0          only build; don't copy to /Applications or launch
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0}"
BUILD="${BUILD:-$VERSION}"
ARCH_FLAGS=()
[[ "${UNIVERSAL:-0}" == 1 ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
# Ask SwiftPM where it put the binary: the universal output path differs between toolchains.
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/TimeAlign"

APP="build/TimeAlign.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TimeAlign"
cp Resources/cities.tsv "$APP/Contents/Resources/"   # GeoNames cities15000 (CC BY 4.0)
cp Resources/AppIcon.icns "$APP/Contents/Resources/"  # regenerate with: swift tools/make_icon.swift
[[ -n "${PROFILE:-}" ]] && cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TimeAlign</string>
  <key>CFBundleDisplayName</key><string>TimeAlign</string>
  <key>CFBundleIdentifier</key><string>com.vinay.timealign</string>
  <key>CFBundleExecutable</key><string>TimeAlign</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>City data by GeoNames (CC BY 4.0)</string>
</dict>
</plist>
PLIST

# Absolute path: conda and other toolchains ship their own incompatible codesign.
if [[ -n "${SIGN_ID:-}" ]]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
    ${ENTITLEMENTS:+--entitlements "$ENTITLEMENTS"} "$APP"
elif [[ -n "${ENTITLEMENTS:-}" ]]; then   # ad-hoc + sandbox: lets you test the App Store build locally
  /usr/bin/codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
else
  /usr/bin/codesign --force --deep --sign - "$APP"
fi
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/TimeAlign"), version $VERSION)"

if [[ "${INSTALL:-1}" == 1 ]]; then
  rm -rf /Applications/TimeAlign.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/TimeAlign.app"
  open /Applications/TimeAlign.app
fi
