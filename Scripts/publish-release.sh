#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
OUTPUT="$PWD/dist/releases/$VERSION"
python3 Scripts/audit-release.py --source --staged --bundle "$PWD/dist/轻译.app"
gh release create "v$VERSION" "$OUTPUT/LightTranslate-$VERSION-arm64.dmg" "$OUTPUT/LightTranslate-$VERSION-arm64.zip" "$OUTPUT/appcast.xml" "$OUTPUT/SHA256SUMS.txt" "$OUTPUT/release.json" --repo andy1613785214/light-translate --title "轻译 $VERSION" --notes-file docs/RELEASE-NOTES.md --latest
