#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift run --disable-sandbox --cache-path "$PWD/.build/package-cache" TranslationChecks
python3 Scripts/check-http.py
