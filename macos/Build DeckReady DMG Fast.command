#!/bin/bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="a1.09.2"
BUILD_ROOT="$SCRIPT_DIR/.dmg-cache"
APP_PATH="$BUILD_ROOT/DerivedData/Build/Products/Release/DeckReady.app"
TOOLS="$BUILD_ROOT/dmg-tools"

pause_on_exit() {
  if [[ "${DECKREADY_NO_PAUSE:-0}" != "1" && -t 0 ]]; then
    read -r -p "Press Return to close..." _ || true
  fi
}
on_error() { code=$?; echo "DMG packaging failed (exit $code)."; pause_on_exit; exit "$code"; }
trap on_error ERR

if [[ "${1:-}" == "--package-only" ]]; then
  [[ -d "$APP_PATH" ]] || { echo "No cached app. Run Build DeckReady PKG.command first."; exit 1; }
else
  # This preserves the incremental build and creates the app's branded icon.
  DECKREADY_NO_PAUSE=1 bash "$SCRIPT_DIR/Build DeckReady PKG.command"
fi

PYTHON=""
for candidate in python3 python3.13 python3.12 python3.11 python3.10 python3.9; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 9))'; then
    PYTHON="$candidate"
    break
  fi
done
[[ -n "$PYTHON" ]] || { echo "Python 3.9 or newer is required to package the DMG."; exit 1; }
if [[ ! -x "$TOOLS/bin/python" ]]; then "$PYTHON" -m venv "$TOOLS"; fi
"$TOOLS/bin/python" -m pip --disable-pip-version-check install -r "$SCRIPT_DIR/packaging/dmg-requirements.txt"
"$TOOLS/bin/python" "$SCRIPT_DIR/packaging/build_dmg.py" \
  --app "$APP_PATH" --background "$SCRIPT_DIR/Assets/DMG-Background.png" \
  --output "$SCRIPT_DIR/DeckReady-$VERSION.dmg"
echo "SUCCESS: Branded DMG created and verified after two separate mounts."
pause_on_exit
