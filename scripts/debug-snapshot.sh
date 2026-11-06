#!/usr/bin/env bash
# Asks the running Global app to save a PNG of each display's wallpaper.
# Usage: scripts/debug-snapshot.sh [output-dir]   (default: build/debug-snapshots)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/debug-snapshots}"
mkdir -p "$OUT"
swift - "$OUT" <<'SWIFT'
import Foundation
let dir = CommandLine.arguments[1]
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("io.github.ne0nmike.global.debugSnapshot"), object: dir, userInfo: nil, deliverImmediately: true)
SWIFT
sleep 2
ls -1 "$OUT"
