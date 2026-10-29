#!/bin/bash
# Builds a sandboxed, universal build/TimeAlign-<version>.pkg for Mac App Store upload.
#   ./appstore.sh 1.0 1                 (version, build number: raise the build number every upload)
# Needs, from developer.apple.com (Certificates, Identifiers & Profiles):
#   - "Apple Distribution" certificate (signs the app)
#   - "Mac Installer Distribution" certificate (signs the .pkg)
#   - a Mac App Store provisioning profile for com.vinay.timealign, saved as
#     Resources/TimeAlign_AppStore.provisionprofile (or pass PROFILE=path)
# Upload the .pkg with Apple's Transporter app, then submit it in App Store Connect.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./appstore.sh <version> <build>, e.g. ./appstore.sh 1.0 1}"
BUILD="${2:?usage: ./appstore.sh <version> <build>, e.g. ./appstore.sh 1.0 1}"
TEAM=5J2B4ZDMXV
BUNDLE_ID=com.vinay.timealign
PROFILE="${PROFILE:-Resources/TimeAlign_AppStore.provisionprofile}"
APP_SIGN_ID="${APP_SIGN_ID:-Apple Distribution: Vinay Bhaskarla ($TEAM)}"
# The "Mac Installer Distribution" certificate's name still starts with "3rd Party Mac Developer Installer".
PKG_SIGN_ID="${PKG_SIGN_ID:-3rd Party Mac Developer Installer: Vinay Bhaskarla ($TEAM)}"
PKG="build/TimeAlign-$VERSION.pkg"

[[ -f "$PROFILE" ]] || { echo "Missing provisioning profile: $PROFILE" >&2; exit 1; }
security find-identity -v | grep -qF "$PKG_SIGN_ID" ||
  { echo "Missing installer certificate: $PKG_SIGN_ID" >&2; exit 1; }

# Sandbox entitlements plus the identifiers the provisioning profile grants (Xcode adds these itself).
ENT="build/TimeAlign.appstore.entitlements"
mkdir -p build
cp Resources/TimeAlign.entitlements "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM.$BUNDLE_ID" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM" "$ENT"

VERSION="$VERSION" BUILD="$BUILD" UNIVERSAL=1 SIGN_ID="$APP_SIGN_ID" ENTITLEMENTS="$ENT" \
  PROFILE="$PROFILE" INSTALL=0 ./build.sh

rm -f "$PKG"
productbuild --component build/TimeAlign.app /Applications --sign "$PKG_SIGN_ID" "$PKG"
pkgutil --check-signature "$PKG" | head -3
echo "Ready: $PKG (version $VERSION, build $BUILD). Upload it with Transporter."
