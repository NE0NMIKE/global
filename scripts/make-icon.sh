#!/usr/bin/env bash
# Renders the app icon from the globe renderer and builds build/AppIcon.icns.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)/Global"
WORK="$ROOT/build/AppIcon.iconset"
rm -rf "$WORK" && mkdir -p "$WORK"
"$BIN" --icon "$ROOT/build/icon-1024.png"
for s in 16 32 128 256 512; do
    sips -z $s $s "$ROOT/build/icon-1024.png" --out "$WORK/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$ROOT/build/icon-1024.png" --out "$WORK/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK" -o "$ROOT/build/AppIcon.icns"
rm -rf "$WORK"
echo "✓ build/AppIcon.icns"
