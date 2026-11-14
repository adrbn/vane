#!/bin/bash
# Builds Vane.app (the Mac app; target and data paths are still named Almanac) into build/. Signs with the first "Developer ID Application"
# identity found, or ad-hoc otherwise. Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="0.1.2"

swift build -c "$CONFIG" --product Almanac
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Almanac"

APP="build/Vane.app"
rm -rf "$APP" build/Almanac.app   # old name
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN" "$APP/Contents/MacOS/Almanac"
cp Resources/countries.json "$APP/Contents/Resources/"
# The icon is an Icon Composer document: actool (Xcode 26) renders it into Assets.car (Liquid Glass layers)
# plus an AppIcon.icns fallback.
rm -rf build/icon && mkdir -p build/icon
xcrun actool Resources/AppIcon.icon --compile build/icon --platform macosx --minimum-deployment-target 26.0 \
  --app-icon AppIcon --output-partial-info-plist build/icon/partial.plist >/dev/null
cp build/icon/Assets.car build/icon/AppIcon.icns "$APP/Contents/Resources/"
# Translations: the string catalog compiles into one .lproj per language (scripts/strings.sh refreshes it).
rm -rf build/strings && mkdir -p build/strings
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory build/strings
cp -R build/strings/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.almanac.app</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>fr</string><string>es</string><string>it</string></array>
  <key>CFBundleName</key><string>Vane</string>
  <key>CFBundleDisplayName</key><string>Vane</string>
  <key>CFBundleExecutable</key><string>Almanac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
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
  # Release builds get a secure timestamp, which notarization requires.
  TS="--timestamp=none"; [ "$CONFIG" = release ] && TS="--timestamp"
  codesign --force --options runtime "$TS" --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP" && echo "Built $APP (${IDENTITY:-ad-hoc})"
