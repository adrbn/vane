#!/bin/bash
# Builds Vane.app (the Mac app; target and data paths are still named Almanac) into build/. Signs with the first "Developer ID Application"
# identity found, or ad-hoc otherwise. Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="${VERSION:-0.1.13}"
# Sparkle compares CFBundleVersion: the commit count only goes up on main.
BUILD="${BUILD:-$(git rev-list --count HEAD)}"
FEED="${FEED:-https://github.com/adrbn/vane/releases/latest/download/appcast.xml}"

swift build -c "$CONFIG" --product Almanac
swift build -c "$CONFIG" --product vane-mcp
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Almanac"

APP="build/Vane.app"
rm -rf "$APP" build/Almanac.app   # old name
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Almanac"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Almanac"
cp "$(dirname "$BIN")/vane-mcp" "$APP/Contents/MacOS/vane-mcp"
cp Resources/countries.json "$APP/Contents/Resources/"
# The icon is an Icon Composer document: actool (Xcode 26) renders it into Assets.car (Liquid Glass layers)
# plus an AppIcon.icns fallback.
rm -rf build/icon && mkdir -p build/icon
xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/build/icon" --platform macosx --minimum-deployment-target 26.0 \
  --app-icon AppIcon --output-partial-info-plist "$PWD/build/icon/partial.plist" >/dev/null
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
  <key>CFBundleLocalizations</key><array><string>en</string><string>ca</string><string>cs</string><string>da</string><string>de</string><string>es</string><string>fr</string><string>it</string><string>nl</string><string>nb</string><string>pl</string><string>pt</string><string>pt-PT</string><string>ro</string><string>fi</string><string>sv</string><string>tr</string><string>el</string><string>ru</string><string>uk</string><string>th</string><string>ja</string><string>zh-Hans</string><string>zh-Hant</string><string>ko</string></array>
  <key>CFBundleName</key><string>Vane</string>
  <key>CFBundleDisplayName</key><string>Vane</string>
  <key>CFBundleExecutable</key><string>Almanac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>SUFeedURL</key><string>$FEED</string>
  <key>SUPublicEDKey</key><string>C22tesvxKTWSmuKyusPIgfsCXRrlnn8BKHUgFCSzTPc=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
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
  SIGN=(codesign --force --options runtime "$TS" --sign "$IDENTITY")
else
  SIGN=(codesign --force --sign -)
fi
# Inside out: Sparkle's helpers keep their ad-hoc signature otherwise, and then notarization fails and Sparkle
# refuses to launch its installer (it must carry the app's identity).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for helper in "$SPARKLE"/XPCServices/*.xpc "$SPARKLE/Updater.app" "$SPARKLE/Autoupdate"; do
  "${SIGN[@]}" --preserve-metadata=entitlements "$helper"
done
"${SIGN[@]}" "$SPARKLE" "$APP/Contents/MacOS/vane-mcp"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP" && echo "Built $APP (${IDENTITY:-ad-hoc})"
