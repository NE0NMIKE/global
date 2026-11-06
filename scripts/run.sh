#!/usr/bin/env bash
# Build the .app and (re)launch it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh"
pkill -x Global 2>/dev/null || true
sleep 0.5
open "$ROOT/build/Global.app"
