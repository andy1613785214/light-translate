#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Uses fixed fixtures and separate preferences. No API requests or global shortcuts.
dist/轻译.app/Contents/MacOS/LightTranslate --smoke-layout
