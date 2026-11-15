#!/usr/bin/env bash
# Builds a notarized, stapled Vane DMG in build/release/.
#   scripts/release.sh            uses VERSION from bundle.sh
# Needs the Developer ID certificate and a notarytool keychain profile (NOTARY_PROFILE, default "haze").
set -euo pipefail
cd "$(dirname "$0")/.."
NOTARY_PROFILE="${NOTARY_PROFILE:-haze}"
APP=build/Vane.app
OUT=build/release
die() { printf '\n✗ %s\n' "$1" >&2; exit 1; }
contains() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

# notarytool exits 0 on "Invalid" too: read the verdict
notarize() {
  local out; out="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 || true)"
  printf '%s\n' "$out"
  contains "status: Accepted" "$out" || die "Notarization of $(basename "$1") failed."
}

scripts/bundle.sh release
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
SIGN_INFO="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
contains "Authority=Developer ID Application" "$SIGN_INFO" || die "Not Developer ID-signed."
SIGN_ID="$(printf '%s\n' "$SIGN_INFO" | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p')"

rm -rf "$OUT"; mkdir -p "$OUT/dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/app.zip"
notarize "$OUT/app.zip"; rm -f "$OUT/app.zip"
xcrun stapler staple "$APP"
contains accepted "$(spctl --assess --type execute -vv "$APP" 2>&1 || true)" || die "Gatekeeper rejects the app."

DMG="$OUT/Vane-$VERSION.dmg"
cp -cR "$APP" "$OUT/dmg/"; ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -quiet -volname Vane -srcfolder "$OUT/dmg" -ov -format UDZO "$DMG"; rm -rf "$OUT/dmg"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
contains accepted "$(spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 || true)" || die "Gatekeeper rejects the DMG."

# Sparkle: the stapled app zipped, plus an appcast signed with .secrets/sparkle_ed_private_key (never committed;
# lose it and installed copies can no longer update). Upload both next to the DMG: SUFeedURL reads
# releases/latest/download/appcast.xml.
KEY=.secrets/sparkle_ed_private_key
[ -f "$KEY" ] || die "Missing $KEY."
ZIP="$OUT/Vane.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
URL="${UPDATE_URL:-https://github.com/adrbn/vane/releases/download/v$VERSION/Vane.zip}"
scripts/appcast.sh "$ZIP" "$URL" "$KEY" > "$OUT/appcast.xml"

printf '\n✓ %s  %s\n' "$DMG" "$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
printf '  gh release create v%s %s %s %s\n' "$VERSION" "$DMG" "$ZIP" "$OUT/appcast.xml"
