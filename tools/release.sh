#!/bin/zsh
# Builds a Developer-ID-signed, Apple-notarized Roost Menu .dmg in dist/.
#
# One-time setup (see README / SETUP.md "Making a downloadable build"):
#   1. A "Developer ID Application" certificate in your login Keychain (Xcode > Settings > Accounts > Manage Certificates).
#   2. A saved notarization login:  xcrun notarytool store-credentials "roost-notary" --apple-id <id> --team-id <TEAM>
#
# Usage:  DIST_BUNDLE_ID=com.yourname.RoostMenu ./tools/release.sh
# Optional env: NOTARY_PROFILE (default roost-notary), TEAM (default: DEVELOPMENT_TEAM from Config/Local.xcconfig).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DIST_BUNDLE_ID:?Set DIST_BUNDLE_ID, e.g. DIST_BUNDLE_ID=com.yourname.RoostMenu ./tools/release.sh}"
PROFILE="${NOTARY_PROFILE:-roost-notary}"
TEAM="${TEAM:-$(sed -nE 's/^DEVELOPMENT_TEAM *= *([A-Z0-9]+).*/\1/p' Config/Local.xcconfig 2>/dev/null | head -1)}"
[[ -n "$TEAM" ]] || { echo "No team ID. Set TEAM=... or put DEVELOPMENT_TEAM in Config/Local.xcconfig."; exit 1; }

IDENTITY="$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application: [^"]*\('"$TEAM"'\))".*/\1/p' | head -1)"
[[ -n "$IDENTITY" ]] || { echo "No 'Developer ID Application' certificate for team $TEAM in your Keychain."; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || { echo "Notarization profile '$PROFILE' not found or not valid. Run notarytool store-credentials first."; exit 1; }

VERSION="$(sed -nE 's/^ *MARKETING_VERSION: *"?([0-9.]+)"?.*/\1/p' project.yml | head -1)"
OUT=dist; BUILD=dist/build; STAGE=dist/stage
rm -rf "$OUT"; mkdir -p "$BUILD" "$STAGE"

echo "==> Building (signing as: $IDENTITY)"
xcodegen generate >/dev/null
xcodebuild -project RoostMenu.xcodeproj -scheme RoostMenu -configuration Release -derivedDataPath "$BUILD" build -quiet \
  PRODUCT_BUNDLE_IDENTIFIER="$DIST_BUNDLE_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
APP="$BUILD/Build/Products/Release/RoostMenu.app"

echo "==> Checking signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority=Developer ID Application|flags=|Timestamp|TeamIdentifier"
if codesign -d --entitlements - "$APP" 2>&1 | grep -q "get-task-allow"; then
  echo "Refusing: debug entitlement get-task-allow is present."; exit 1
fi

echo "==> Notarizing the app itself (so its ticket travels with it, even when copied out of the .dmg)"
ditto -c -k --keepParent "$APP" "$OUT/RoostMenu-app.zip"
xcrun notarytool submit "$OUT/RoostMenu-app.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$OUT/RoostMenu-app.zip"

echo "==> Packaging"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/RoostMenu-$VERSION.dmg"
hdiutil create -volname "Roost Menu" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Notarizing (this usually takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> Verifying"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
rm -rf "$STAGE"
echo "Done: $DMG"
shasum -a 256 "$DMG"
