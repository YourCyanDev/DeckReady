#!/bin/bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

clear
printf '\n====================================================\n'
printf '    DeckReady a1.09.2 macOS Release Builder\n'
printf '                 DMG + PKG\n'
printf '====================================================\n\n'

export DECKREADY_NO_PAUSE=1
"$SCRIPT_DIR/Build DeckReady DMG Fast.command"
"$SCRIPT_DIR/Build DeckReady PKG.command" --package-only
unset DECKREADY_NO_PAUSE

echo
printf '====================================================\n'
printf ' DeckReady macOS a1.09.2 installers are ready.\n'
printf '====================================================\n'
printf '  %s\n' "$SCRIPT_DIR/DeckReady-a1.09.2.dmg"
printf '  %s\n' "$SCRIPT_DIR/DeckReady-a1.09.2.pkg"
printf '\n'
if [[ -t 0 ]]; then
  read -r -p "Press Return to close..." _ || true
fi
