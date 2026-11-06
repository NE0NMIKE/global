#!/usr/bin/env bash
# Debug builds only: sends a settings command to the running app.
# Examples: scripts/debug-command.sh style=lineArt
#           scripts/debug-command.sh appearance=light
set -euo pipefail
for cmd in "$@"; do
swift - "$cmd" <<'SWIFT'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("io.github.ne0nmike.global.debugCommand"), object: CommandLine.arguments[1],
    userInfo: nil, deliverImmediately: true)
SWIFT
done
