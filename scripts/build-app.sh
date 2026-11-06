#!/usr/bin/env bash
#
# Builds Global.app from the SwiftPM executable.
#
# Usage:
#   scripts/build-app.sh                 # release build for this Mac's arch
#   UNIVERSAL=1 scripts/build-app.sh     # arm64 + x86_64 (for an Intel Mac)
#   CONFIG=debug scripts/build-app.sh    # debug build
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# Output: build/Global.app
#
# Signing defaults to ad-hoc ("-"). Ad-hoc apps run fine locally; on another
# Mac they must be approved once in System Settings › Privacy & Security.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

APP="$ROOT/build/Global.app"
CONTENTS="$APP/Contents"

echo "▸ Building ($CONFIG)…"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    # Command Line Tools can't do `--arch a --arch b` (needs Xcode's build
    # system), so build each triple separately and merge with lipo.
    swift build -c "$CONFIG" --triple arm64-apple-macosx13.0
    swift build -c "$CONFIG" --triple x86_64-apple-macosx13.0
    ARM_BIN="$(swift build -c "$CONFIG" --triple arm64-apple-macosx13.0 --show-bin-path)/Global"
    X86_BIN="$(swift build -c "$CONFIG" --triple x86_64-apple-macosx13.0 --show-bin-path)/Global"
    BIN="$ROOT/build/Global-universal"
    mkdir -p "$ROOT/build"
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$BIN"
else
    swift build -c "$CONFIG"
    BIN="$(swift build -c "$CONFIG" --show-bin-path)/Global"
fi

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/Global"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    Config/Info.plist > "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist" >/dev/null

# Bundled resources (textures, land data).
cp -R Resources/Textures "$CONTENTS/Resources/Textures"
cp -R Resources/GeoData "$CONTENTS/Resources/GeoData"

# App icon — generated once from code, cached in build/.
if [[ ! -f "$ROOT/build/AppIcon.icns" ]]; then
    "$ROOT/scripts/make-icon.sh" || echo "  (icon generation skipped)"
fi
[[ -f "$ROOT/build/AppIcon.icns" ]] && cp "$ROOT/build/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

echo "▸ Signing (${SIGN_IDENTITY})…"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --strict "$APP"

echo "✓ $APP"
