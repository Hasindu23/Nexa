#!/bin/zsh
set -euo pipefail
NEXA_ROOT="${0:A:h:h}"
NEXA_BUILD_DIR="${TMPDIR:-/tmp}/NexaBuild"
xcodebuild -project "$NEXA_ROOT/Nexa.xcodeproj" -scheme Nexa -configuration Debug -derivedDataPath "$NEXA_BUILD_DIR" -destination 'platform=macOS' test
