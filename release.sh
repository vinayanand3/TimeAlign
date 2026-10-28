#!/bin/bash
# Builds a universal, Developer ID signed, notarized build/TimeAlign-<version>.dmg for sharing.
#   ./release.sh 1.0
# One-time setup (saves your Apple ID app-specific password in the keychain):
#   xcrun notarytool store-credentials TimeAlign --apple-id <email> --team-id 5J2B4ZDMXV
# Then publish:  gh release create v1.0 build/TimeAlign-1.0.dmg
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>, e.g. ./release.sh 1.0}"
SIGN_ID="${SIGN_ID:-Developer ID Application: Vinay Bhaskarla (5J2B4ZDMXV)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-TimeAlign}"
DMG="build/TimeAlign-$VERSION.dmg"

VERSION="$VERSION" UNIVERSAL=1 SIGN_ID="$SIGN_ID" INSTALL=0 ./build.sh

# Disk image with the app and an Applications shortcut to drag it onto.
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/TimeAlign.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "TimeAlign $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
/usr/bin/codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "Ready: $DMG"
