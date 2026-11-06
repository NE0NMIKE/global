#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) Global.app and wraps it in
# build/Global.dmg: open it, drag Global onto Applications, done.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
UNIVERSAL=1 "$ROOT/scripts/build-app.sh"

STAGE="$ROOT/build/dmg"
rm -rf "$STAGE" build/Global.dmg
mkdir -p "$STAGE"
# ditto preserves the code signature and extended attributes.
ditto build/Global.app "$STAGE/Global.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -quiet -volname "Global" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/Global.dmg
rm -rf "$STAGE"
echo "✓ build/Global.dmg"
