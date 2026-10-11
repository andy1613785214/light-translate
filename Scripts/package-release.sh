#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ "${SKIP_BUILD:-0}" != '1' ]]; then ./Scripts/build-app.sh; fi
VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
OUTPUT="$PWD/dist/releases/$VERSION"
mkdir -p "$OUTPUT"
APP="$PWD/dist/轻译.app"
NAME="LightTranslate-$VERSION-arm64"
DITTO_ARGS=(-c -k --sequesterRsrc --keepParent)
ditto "${DITTO_ARGS[@]}" "$APP" "$OUTPUT/$NAME.zip"
if ! PYTHONPATH="$PWD/.build/release-tools" python3 -c 'import ds_store, mac_alias' 2>/dev/null; then
    python3 -m pip install --target .build/release-tools 'ds_store==1.3.3' 'mac_alias==2.2.3'
fi
STAGING_DIR=$(mktemp -d "$PWD/.build/release-image.XXXXXX")
MOUNT="$STAGING_DIR/mount"
MOUNTED=0
cleanup() {
    if (( MOUNTED )); then hdiutil detach "$MOUNT" -force >/dev/null || true; fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
hdiutil create -size 128m -fs HFS+ -volname "轻译 $VERSION" "$STAGING_DIR/image.dmg" >/dev/null
mkdir -p "$MOUNT"
hdiutil attach "$STAGING_DIR/image.dmg" -mountpoint "$MOUNT" -nobrowse -noautoopen >/dev/null
MOUNTED=1
ditto "$APP" "$MOUNT/轻译.app"
ln -s /Applications "$MOUNT/Applications"
mkdir -p "$MOUNT/.background"
cp .build/release-assets/dmg-background.png "$MOUNT/.background/background.png"
PYTHONPATH="$PWD/.build/release-tools" python3 Scripts/dmg-layout.py "$MOUNT"
hdiutil detach "$MOUNT" >/dev/null
MOUNTED=0
hdiutil convert "$STAGING_DIR/image.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$OUTPUT/$NAME.dmg" >/dev/null
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$OUTPUT/$NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUTPUT/$NAME.dmg"
fi
python3 Scripts/make-appcast.py "$OUTPUT"
python3 Scripts/audit-release.py --bundle "$APP" --source
print "Release: $OUTPUT"
