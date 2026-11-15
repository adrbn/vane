#!/bin/bash
# Prints a one-item Sparkle appcast for a zipped Vane.app.  Usage: scripts/appcast.sh <Vane.zip> <download URL> <EdDSA key file>
set -euo pipefail
cd "$(dirname "$0")/.."
ZIP="$1"; URL="$2"; KEY="$3"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ditto -x -k "$ZIP" "$TMP"
PLIST="$TMP/Vane.app/Contents/Info.plist"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$PLIST")"
SIG="$(.build/artifacts/sparkle/Sparkle/bin/sign_update --ed-key-file "$KEY" "$ZIP")"
cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Vane</title>
    <item>
      <title>Vane $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/adrbn/vane/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <enclosure url="$URL" $SIG type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
