#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/make-app.sh"
STAGE="$ROOT/dist/dmg-stage"
DMG="$ROOT/dist/EnvStudio-arm64.dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$ROOT/dist/EnvStudio.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Env Studio" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "DMG: $DMG"
