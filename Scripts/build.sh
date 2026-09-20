#!/bin/zsh
set -euo pipefail
NEXA_ROOT="${0:A:h:h}"
NEXA_BUILD_DIR="${TMPDIR:-/tmp}/NexaStorageBuild"
NEXA_CONFIGURATION="${1:-Release}"
xcodebuild -project "$NEXA_ROOT/Nexa.xcodeproj" -scheme Nexa -configuration "$NEXA_CONFIGURATION" -derivedDataPath "$NEXA_BUILD_DIR" -destination 'platform=macOS' build
print "Built: $NEXA_BUILD_DIR/Build/Products/$NEXA_CONFIGURATION/Nexa.app"
if [[ "${2:-}" == "--open" ]]; then
  open "$NEXA_BUILD_DIR/Build/Products/$NEXA_CONFIGURATION/Nexa.app"
fi
