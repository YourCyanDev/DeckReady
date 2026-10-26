#!/bin/bash
set -Eeuo pipefail

VERSION="a1.09.2"
APP_NAME="DeckReady"
VOLUME_NAME="DeckReady"
CURRENT_STEP="Starting"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/DeckReady.xcodeproj"
ASSETS="$SCRIPT_DIR/Assets"
LOGO="$ASSETS/DeckReady-Logo.png"
BACKGROUND="$ASSETS/DMG-Background.png"
BUILD_ROOT="$SCRIPT_DIR/.dmg-cache"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
ICONSET="$BUILD_ROOT/${APP_NAME}.iconset"
RW_DMG="$BUILD_ROOT/${APP_NAME}-rw.dmg"
STAGING="$BUILD_ROOT/staging"
OUTPUT="$SCRIPT_DIR/${APP_NAME}-${VERSION}.dmg"
LOG="$BUILD_ROOT/build.log"
MOUNTPOINT=""
FINAL_MOUNTPOINT=""
STYLE_WARNING=0
PACKAGE_ONLY=0
if [[ "${1:-}" == "--package-only" ]]; then
  PACKAGE_ONLY=1
fi

pause_on_exit() {
  [[ "${DECKREADY_NO_PAUSE:-0}" == "1" ]] && return 0
  if [[ -t 0 ]]; then
    echo
    read -r -p "Press Return to close..." _ || true
  fi
}

safe_detach() {
  local mp="${1:-}"
  [[ -z "$mp" || ! -d "$mp" ]] && return 0

  if mount | grep -Fq " on $mp "; then
    hdiutil detach "$mp" -quiet >/dev/null 2>&1 && return 0
    sleep 1
    hdiutil detach "$mp" -force -quiet >/dev/null 2>&1 || true
  fi
}

cleanup() {
  safe_detach "$FINAL_MOUNTPOINT"
  safe_detach "$MOUNTPOINT"
}
trap cleanup EXIT

on_error() {
  local code=$?
  echo
  echo "===================================================="
  echo " DeckReady DMG builder stopped during: $CURRENT_STEP"
  echo "===================================================="
  echo "Exit code: $code"
  if [[ -f "$LOG" ]]; then
    echo "Build log: $LOG"
  fi
  cleanup
  pause_on_exit
  exit "$code"
}
trap on_error ERR

clear
printf '\n====================================================\n'
printf '       DeckReady %s Branded DMG Builder\n' "$VERSION"
printf '====================================================\n\n'

CURRENT_STEP="Preflight checks"
for path in "$PROJECT" "$LOGO" "$BACKGROUND"; do
  if [[ ! -e "$path" ]]; then
    echo "ERROR: Required file was not found:"
    echo "$path"
    pause_on_exit
    exit 1
  fi
done

for tool in xcodebuild hdiutil sips iconutil osascript ditto PlistBuddy; do
  case "$tool" in
    PlistBuddy)
      [[ -x /usr/libexec/PlistBuddy ]] || { echo "ERROR: /usr/libexec/PlistBuddy is missing."; pause_on_exit; exit 1; }
      ;;
    *)
      command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool was not found."; pause_on_exit; exit 1; }
      ;;
  esac
done

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "ERROR: Xcode is not ready. Open Xcode once and complete its setup first."
  pause_on_exit
  exit 1
fi

# Building plus DMG creation needs temporary disk space. Warn instead of failing hard.
FREE_KB=$(df -Pk "$SCRIPT_DIR" | awk 'NR==2 {print $4}')
if [[ "${FREE_KB:-0}" -lt 3145728 ]]; then
  echo "WARNING: Less than 3 GB of free space is available."
  echo "The build may fail if Xcode needs additional temporary space."
  echo
fi

CURRENT_STEP="Preparing cached build"
echo "[1/8] Preparing fast DMG build cache..."
mkdir -p "$DERIVED_DATA" "$ICONSET"
rm -rf "$STAGING"
rm -f "$RW_DMG" "$OUTPUT" "$OUTPUT".dmg
mkdir -p "$STAGING"

APP_PATH="$DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"

CURRENT_STEP="Building DeckReady"
if [[ $PACKAGE_ONLY -eq 1 ]]; then
  echo "[2/8] Reusing cached DeckReady.app (package-only mode)..."
  if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: No cached Release app exists yet. Run 'Build DeckReady DMG Fast.command' once first."
    pause_on_exit
    exit 1
  fi
else
  echo "[2/8] Incremental Release build (unsigned)..."
  echo "      DerivedData is preserved, so unchanged files do not rebuild."
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
    echo "ERROR: Xcode could not build DeckReady."
    echo "Build log: $LOG"
    echo
    echo "Compiler errors:"
    grep -nE "error:|fatal error:" "$LOG" | tail -20 || true
    pause_on_exit
    exit "$BUILD_STATUS"
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Build finished but ${APP_NAME}.app was not found at:"
  echo "$APP_PATH"
  pause_on_exit
  exit 1
fi

CURRENT_STEP="Creating app icon"
echo "[3/8] Preparing DeckReady app icon..."
if [[ ! -f "$BUILD_ROOT/${APP_NAME}.icns" || "$LOGO" -nt "$BUILD_ROOT/${APP_NAME}.icns" ]]; then
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
  iconutil -c icns "$ICONSET" -o "$BUILD_ROOT/${APP_NAME}.icns"
else
  echo "      Reusing cached app icon."
fi

mkdir -p "$APP_PATH/Contents/Resources"
cp "$BUILD_ROOT/${APP_NAME}.icns" "$APP_PATH/Contents/Resources/${APP_NAME}.icns"
PLIST="$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFile' "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}.icns" "$PLIST"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIconName' "$PLIST" >/dev/null 2>&1 || true
xattr -cr "$APP_PATH" >/dev/null 2>&1 || true
touch "$APP_PATH"

CURRENT_STEP="Preparing installer contents"
echo "[4/8] Preparing branded installer contents..."
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
/usr/bin/ditto "$APP_PATH" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"
cp "$BACKGROUND" "$STAGING/.background/DMG-Background.png"
cp "$BUILD_ROOT/${APP_NAME}.icns" "$STAGING/.VolumeIcon.icns"
touch "$STAGING/.metadata_never_index"
cat > "$STAGING/.background/README.txt" <<README
DeckReady ${VERSION}

Install by dragging DeckReady.app to Applications.

This is an unsigned local build. macOS may require Control-click > Open on first launch.
README
chflags hidden "$STAGING/.background" "$STAGING/.metadata_never_index" "$STAGING/.VolumeIcon.icns" 2>/dev/null || true

CURRENT_STEP="Creating writable DMG"
echo "[5/8] Creating writable installer image..."
hdiutil create \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -volname "$VOLUME_NAME" \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

# Give Finder guaranteed room for .DS_Store and other view metadata.
STAGING_KB=$(du -sk "$STAGING" | awk '{print $1}')
TARGET_MB=$(( (STAGING_KB / 1024) + 32 ))
hdiutil resize -size "${TARGET_MB}m" "$RW_DMG" >/dev/null 2>&1 || true

ATTACH_OUTPUT=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -owners off)
MOUNTPOINT=$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -n 1)
if [[ -z "$MOUNTPOINT" || ! -d "$MOUNTPOINT" ]]; then
  echo "ERROR: The writable DMG mounted, but its /Volumes path could not be detected."
  echo "$ATTACH_OUTPUT"
  pause_on_exit
  exit 1
fi
ACTUAL_VOLUME_NAME=$(basename "$MOUNTPOINT")
echo "    Mounted as: $MOUNTPOINT"

# Mark the mounted volume as having a custom icon when SetFile is available.
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MOUNTPOINT" >/dev/null 2>&1 || true
fi

CURRENT_STEP="Styling Finder window"
echo "[6/8] Styling the Finder window..."

# Give Finder a moment to register the newly mounted disk.
for _ in 1 2 3 4 5; do
  if osascript -e 'tell application "Finder" to get name of every disk' 2>/dev/null | grep -Fq "$ACTUAL_VOLUME_NAME"; then
    break
  fi
  sleep 1
done

# Primary styling pass. Use an absolute POSIX alias for the background image;
# this is more reliable across Ventura/Sonoma than a raw Finder colon path.
set +e
osascript <<APPLESCRIPT
set volumeName to "$ACTUAL_VOLUME_NAME"
set mountPath to "$MOUNTPOINT"
set backgroundPath to mountPath & "/.background/DMG-Background.png"

tell application "Finder"
    activate
    set targetDisk to disk volumeName
    open targetDisk
    delay 1

    set targetWindow to container window of targetDisk
    set current view of targetWindow to icon view
    set toolbar visible of targetWindow to false
    set statusbar visible of targetWindow to false
    set bounds of targetWindow to {160, 120, 920, 610}

    set viewOptions to icon view options of targetWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 15

    try
        -- Finder stores DMG backgrounds most reliably using a file object that
        -- lives on the mounted volume itself.
        set background picture of viewOptions to file ".background:DMG-Background.png" of targetDisk
    on error
        -- Ventura compatibility fallback.
        set backgroundAlias to (POSIX file backgroundPath) as alias
        set background picture of viewOptions to backgroundAlias
    end try

    set position of item "${APP_NAME}.app" of targetDisk to {205, 305}
    set position of item "Applications" of targetDisk to {555, 305}
    update targetDisk without registering applications
    delay 2
    close targetWindow
    delay 2
end tell
APPLESCRIPT
STYLE_STATUS=$?
set -e

if [[ $STYLE_STATUS -ne 0 ]]; then
  STYLE_WARNING=1
  echo "    Finder rejected the branded background. Retrying with a basic icon layout..."
  # A background failure should not destroy an otherwise valid installer.
  # This fallback still produces the familiar app -> Applications layout.
  set +e
  osascript <<APPLESCRIPT
set volumeName to "$ACTUAL_VOLUME_NAME"
tell application "Finder"
    activate
    set targetDisk to disk volumeName
    open targetDisk
    delay 1
    set targetWindow to container window of targetDisk
    set current view of targetWindow to icon view
    set toolbar visible of targetWindow to false
    set statusbar visible of targetWindow to false
    set bounds of targetWindow to {160, 120, 920, 610}
    set viewOptions to icon view options of targetWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 15
    set position of item "${APP_NAME}.app" of targetDisk to {205, 305}
    set position of item "Applications" of targetDisk to {555, 305}
    update targetDisk without registering applications
    delay 3
    close targetWindow
end tell
APPLESCRIPT
  FALLBACK_STYLE_STATUS=$?
  set -e
  if [[ $FALLBACK_STYLE_STATUS -ne 0 ]]; then
    echo "    WARNING: Finder styling could not be saved."
    echo "    The DMG will still be created and remain installable."
  fi
fi

# Wait for Finder to write .DS_Store. Do not fail if Finder chooses not to.
for _ in 1 2 3 4 5; do
  [[ -f "$MOUNTPOINT/.DS_Store" ]] && break
  sleep 1
done
sync
sleep 1
safe_detach "$MOUNTPOINT"
MOUNTPOINT=""

CURRENT_STEP="Compressing DMG"
echo "[7/8] Compressing final DMG..."
rm -f "$OUTPUT"
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUTPUT" >/dev/null

# hdiutil may append .dmg when an output path does not already end exactly as expected.
if [[ ! -f "$OUTPUT" && -f "$OUTPUT.dmg" ]]; then
  mv "$OUTPUT.dmg" "$OUTPUT"
fi
if [[ ! -f "$OUTPUT" ]]; then
  echo "ERROR: hdiutil finished but the final DMG was not found."
  pause_on_exit
  exit 1
fi

CURRENT_STEP="Verifying final DMG"
echo "[8/8] Verifying final DMG..."
hdiutil verify "$OUTPUT" >/dev/null

FINAL_ATTACH=$(hdiutil attach "$OUTPUT" -readonly -noverify -noautoopen -nobrowse -owners off)
FINAL_MOUNTPOINT=$(printf '%s\n' "$FINAL_ATTACH" | awk -F '\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -n 1)
if [[ -z "$FINAL_MOUNTPOINT" || ! -d "$FINAL_MOUNTPOINT" ]]; then
  echo "ERROR: The final DMG passed hdiutil verify but could not be mounted for content verification."
  pause_on_exit
  exit 1
fi

[[ -d "$FINAL_MOUNTPOINT/${APP_NAME}.app" ]] || { echo "ERROR: Final DMG is missing ${APP_NAME}.app"; exit 1; }
[[ -e "$FINAL_MOUNTPOINT/Applications" ]] || { echo "ERROR: Final DMG is missing the Applications shortcut"; exit 1; }
[[ -f "$FINAL_MOUNTPOINT/.background/DMG-Background.png" ]] || { echo "ERROR: Final DMG is missing its background asset"; exit 1; }

safe_detach "$FINAL_MOUNTPOINT"
FINAL_MOUNTPOINT=""

SIZE=$(du -h "$OUTPUT" | awk '{print $1}')
trap - ERR
trap - EXIT
rm -rf "$STAGING"
rm -f "$RW_DMG"

printf '\n====================================================\n'
printf ' SUCCESS — DeckReady DMG created and verified!\n'
printf '====================================================\n\n'
echo "File: $OUTPUT"
echo "Size: $SIZE"
echo
if [[ $STYLE_WARNING -eq 1 ]]; then
  echo "NOTE: Finder needed the compatibility styling fallback."
  echo "The DMG is valid and installable; open it once to confirm the visual layout."
  echo
fi
echo "Verified contents:"
echo "  ✓ DeckReady.app"
echo "  ✓ Applications shortcut"
echo "  ✓ Branded background asset"
echo "  ✓ Valid compressed disk image"
echo
open -R "$OUTPUT" || true
pause_on_exit
