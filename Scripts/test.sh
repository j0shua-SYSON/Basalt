#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESTINATION="${BASALT_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro}"

"$SCRIPT_DIR/bootstrap.sh"
mkdir -p "$REPO_ROOT/DerivedData" "$REPO_ROOT/TestResults"
rm -rf "$REPO_ROOT/TestResults/Basalt.xcresult"

xcodebuild \
  -project "$REPO_ROOT/Basalt.xcodeproj" \
  -scheme Basalt \
  -destination "$DESTINATION" \
  -derivedDataPath "$REPO_ROOT/DerivedData" \
  -resultBundlePath "$REPO_ROOT/TestResults/Basalt.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  test

