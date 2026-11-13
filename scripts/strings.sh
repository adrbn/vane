#!/bin/bash
# Refreshes Resources/Localizable.xcstrings from the code of the Mac app, the iPhone app and the widgets.
# Translations already in the catalog are kept; new strings arrive untranslated, removed ones are marked stale.
set -euo pipefail
cd "$(dirname "$0")/.."
CAT=Resources/Localizable.xcstrings
[ -f "$CAT" ] || echo '{"sourceLanguage":"en","strings":{},"version":"1.0"}' > "$CAT"
rm -rf build/loc && mkdir -p build/loc

swift build --product Almanac -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$PWD/build/loc"
(cd ios && xcodegen generate -q && xcodebuild -project Vane.xcodeproj -scheme Vane -destination "generic/platform=iOS Simulator" \
  -derivedDataPath build/loc-dd build SWIFT_EMIT_LOC_STRINGS=YES CODE_SIGNING_ALLOWED=NO -quiet)

ARGS=()
while IFS= read -r f; do ARGS+=(--stringsdata "$f"); done < <(find build/loc ios/build/loc-dd -name '*.stringsdata')
xcrun xcstringstool sync "$CAT" "${ARGS[@]}"
python3 -c "import json;d=json.load(open('$CAT'));print(len(d['strings']),'strings in $CAT')"
