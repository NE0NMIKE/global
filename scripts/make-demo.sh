#!/usr/bin/env bash
# Renders the README animation: one full Spin, Then Settle cycle in the
# Realistic Dark style, sped up about 15× (185 s → 12 s at 15 fps).
#   scripts/make-demo.sh        → docs/demo.gif
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --arch "$(uname -m)" >/dev/null
BIN="$(swift build -c release --arch "$(uname -m)" --show-bin-path)/Global"

FRAMES="$(mktemp -d)"
trap 'rm -rf "$FRAMES"' EXIT
"$BIN" --snapshot "$FRAMES" --size 1600x900 --style realistic --dark --tags --spin \
       --frames 185 --scale 1
swift scripts/frames-to-gif.swift "$FRAMES/realistic-dark" docs/demo.gif 960 15
