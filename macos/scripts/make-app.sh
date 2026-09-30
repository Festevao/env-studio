#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --arch arm64
BIN="$ROOT/.build/arm64-apple-macosx/release/EnvStudio"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/.build/release/EnvStudio"
fi
APP="$ROOT/dist/EnvStudio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EnvStudio"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/EnvStudio"
echo "App: $APP"
