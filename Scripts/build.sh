#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/bootstrap.sh"
mkdir -p "$REPO_ROOT/DerivedData" "$REPO_ROOT/TestResults"

xcodebuild \
  -project "$REPO_ROOT/Basalt.xcodeproj" \
  -scheme Basalt \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$REPO_ROOT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

