#!/bin/bash
# Builds Almanac.app into build/. Signs with the first "Developer ID Application"
# identity found, or ad-hoc otherwise. Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="0.1.0"

swift build -c "$CONFIG" --product Almanac
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Almanac"

APP="build/Almanac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN" "$APP/Contents/MacOS/Almanac"
cp Resources/countries.json "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.almanac.app</string>
  <key>CFBundleName</key><string>Almanac</string>
  <key>CFBundleDisplayName</key><string>Almanac</string>
  <key>CFBundleExecutable</key><string>Almanac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

cat > "$APP/Contents/Library/LaunchAgents/dev.almanac.agent.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.almanac.agent</string>
  <key>BundleProgram</key><string>Contents/MacOS/Almanac</string>
  <key>ProgramArguments</key><array><string>Almanac</string><string>--sync</string></array>
  <key>StartInterval</key><integer>21600</integer>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
EOF

IDENTITY="$(security find-identity -v -p codesigning | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)".*/\1/' || true)"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP" && echo "Built $APP (${IDENTITY:-ad-hoc})"
