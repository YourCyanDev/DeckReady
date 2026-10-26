#!/bin/bash
set -Eeuo pipefail

VERSION="a1.09.2"
NUMERIC_VERSION="1.9.2"
APP_NAME="DeckReady"
BUNDLE_ID="com.deckready.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/DeckReady.xcodeproj"
ASSETS="$SCRIPT_DIR/Assets"
LOGO="$ASSETS/DeckReady-Logo.png"
BUILD_ROOT="$SCRIPT_DIR/.dmg-cache"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"
ICONSET="$BUILD_ROOT/${APP_NAME}.iconset"
ICNS="$BUILD_ROOT/${APP_NAME}.icns"
OUTPUT="$SCRIPT_DIR/${APP_NAME}-${VERSION}.pkg"
LOG="$BUILD_ROOT/pkg-build.log"
PACKAGE_ONLY=0
[[ "${1:-}" == "--package-only" ]] && PACKAGE_ONLY=1

pause_on_exit() {
  [[ "${DECKREADY_NO_PAUSE:-0}" == "1" ]] && return 0
  if [[ -t 0 ]]; then
    echo
    read -r -p "Press Return to close..." _ || true
  fi
}

on_error() {
  local code=$?
  echo
  echo "DeckReady PKG build failed with exit code: $code"
  [[ -f "$LOG" ]] && echo "Build log: $LOG"
  pause_on_exit
  exit "$code"
}
trap on_error ERR

clear
printf '\n====================================================\n'
printf '       DeckReady %s PKG Builder\n' "$VERSION"
printf '====================================================\n\n'

for tool in xcodebuild pkgbuild sips iconutil; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool was not found."; pause_on_exit; exit 1; }
done
[[ -x /usr/libexec/PlistBuddy ]] || { echo "ERROR: PlistBuddy is missing."; pause_on_exit; exit 1; }
[[ -e "$PROJECT" ]] || { echo "ERROR: Xcode project not found: $PROJECT"; pause_on_exit; exit 1; }
[[ -f "$LOGO" ]] || { echo "ERROR: DeckReady logo not found: $LOGO"; pause_on_exit; exit 1; }

mkdir -p "$BUILD_ROOT" "$ICONSET"

if [[ $PACKAGE_ONLY -eq 0 || ! -d "$APP_PATH" ]]; then
  echo "[1/4] Building DeckReady Release app (incremental, unsigned)..."
  set +e
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    build 2>&1 | tee "$LOG"
  BUILD_STATUS=${PIPESTATUS[0]}
  set -e
  if [[ $BUILD_STATUS -ne 0 ]]; then
    echo
    echo "Compiler errors:"
    grep -nE "error:|fatal error:" "$LOG" | tail -20 || true
    exit "$BUILD_STATUS"
  fi
else
  echo "[1/4] Reusing cached DeckReady.app..."
fi

[[ -d "$APP_PATH" ]] || { echo "ERROR: DeckReady.app was not produced."; exit 1; }

echo "[2/4] Applying DeckReady app icon..."
if [[ ! -f "$ICNS" || "$LOGO" -nt "$ICNS" ]]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  sips -z 16 16     "$LOGO" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32     "$LOGO" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$LOGO" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64     "$LOGO" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$LOGO" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256   "$LOGO" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$LOGO" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512   "$LOGO" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$LOGO" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$LOGO" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$ICNS"
fi
mkdir -p "$APP_PATH/Contents/Resources"
cp "$ICNS" "$APP_PATH/Contents/Resources/${APP_NAME}.icns"
PLIST="$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFile' "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}.icns" "$PLIST"
xattr -cr "$APP_PATH" >/dev/null 2>&1 || true

echo "[3/4] Creating unsigned PKG installer..."
rm -f "$OUTPUT"
pkgbuild \
  --component "$APP_PATH" \
  --install-location /Applications \
  --identifier "${BUNDLE_ID}.pkg" \
  --version "$NUMERIC_VERSION" \
  --ownership recommended \
  "$OUTPUT"

echo "[4/4] Verifying package..."
pkgutil --check-signature "$OUTPUT" >/dev/null 2>&1 || true
pkgutil --payload-files "$OUTPUT" | grep -Fq "DeckReady.app" || {
  echo "ERROR: PKG was created but DeckReady.app was not found in its payload."
  exit 1
}

echo
echo "SUCCESS"
echo "PKG: $OUTPUT"
echo
echo "This alpha package is unsigned. macOS may display a security warning."
pause_on_exit
