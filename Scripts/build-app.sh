#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/package-cache" -Xswiftc -D -Xswiftc DISTRIBUTION
swift -module-cache-path "$PWD/.build/swift-module-cache" Scripts/make-assets.swift "$PWD/.build/release-assets"
python3 Scripts/make-icns.py
APP_PATH="$PWD/dist/轻译.app"
mkdir -p "$PWD/dist"
STAGING_DIR=$(mktemp -d "$PWD/dist/.lighttranslate-build.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/轻译.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources" "$STAGED_APP/Contents/Frameworks"
cp .build/release/LightTranslate "$STAGED_APP/Contents/MacOS/LightTranslate"
strip -S -x "$STAGED_APP/Contents/MacOS/LightTranslate"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
cp -R .build/release/LightTranslate_TranslationCore.bundle "$STAGED_APP/Contents/Resources/"
cp .build/release-assets/AppIcon.icns "$STAGED_APP/Contents/Resources/"
ditto .build/release/Sparkle.framework "$STAGED_APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_LICENSES=("$PWD"/.build/artifacts/*/Sparkle/LICENSE(N))
[[ ${#SPARKLE_LICENSES[@]} -eq 1 ]] || { print "Expected one resolved Sparkle artifact."; exit 1; }
cp "$SPARKLE_LICENSES[1]" "$STAGED_APP/Contents/Resources/Sparkle-LICENSE.txt"
IDENTITY="${SIGNING_IDENTITY:--}"
CODESIGN_FLAGS=()
if [[ "$IDENTITY" != '-' ]]; then
    CODESIGN_FLAGS=(--options runtime --timestamp)
    FRAMEWORK="$STAGED_APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    for COMPONENT in "$FRAMEWORK/XPCServices/Downloader.xpc" "$FRAMEWORK/XPCServices/Installer.xpc" "$FRAMEWORK/Updater.app" "$FRAMEWORK/Autoupdate" "$STAGED_APP/Contents/Frameworks/Sparkle.framework"; do
        codesign --force --sign "$IDENTITY" "${CODESIGN_FLAGS[@]}" "$COMPONENT"
    done
fi
codesign --force --sign "$IDENTITY" "${CODESIGN_FLAGS[@]}" --identifier com.local.LightTranslate "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
# Swap the bundle after verification; never overwrite a running executable or mapped resources.
if [[ -d "$APP_PATH" ]]; then
    PREVIOUS_DIR=$(mktemp -d "$PWD/.build/previous-release.XXXXXX")
    mv "$APP_PATH" "$PREVIOUS_DIR/轻译.app"
    if ! mv "$STAGED_APP" "$APP_PATH"; then
        mv "$PREVIOUS_DIR/轻译.app" "$APP_PATH"
        exit 1
    fi
    print "Previous release: $PREVIOUS_DIR/轻译.app"
else
    mv "$STAGED_APP" "$APP_PATH"
fi
print "Built: $APP_PATH"
