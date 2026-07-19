#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULT_BUNDLE="$REPO_ROOT/TestResults/Basalt.xcresult"
ARTIFACTS="$REPO_ROOT/VisualArtifacts"

"$SCRIPT_DIR/bootstrap.sh"
mkdir -p "$REPO_ROOT/DerivedData" "$REPO_ROOT/TestResults" "$ARTIFACTS"
rm -rf "$RESULT_BUNDLE"

device_id() {
  local pattern="$1"
  xcrun simctl list devices available \
    | grep -m 1 "$pattern" \
    | grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
    | head -n 1
}

IPAD_ID="$(device_id 'iPad')"
IPHONE_ID="$(device_id 'iPhone')"
if [[ -z "$IPAD_ID" ]] || [[ -z "$IPHONE_ID" ]]; then
  echo "An available iPad and iPhone simulator are required." >&2
  xcrun simctl list devices available
  exit 1
fi

xcrun simctl boot "$IPAD_ID" 2>/dev/null || true
xcrun simctl bootstatus "$IPAD_ID" -b

VIDEO="$ARTIFACTS/ipad-walkthrough.mp4"

xcodebuild \
  -project "$REPO_ROOT/Basalt.xcodeproj" \
  -scheme Basalt \
  -destination "platform=iOS Simulator,id=$IPAD_ID" \
  -derivedDataPath "$REPO_ROOT/DerivedData" \
  build-for-testing

xcrun simctl io "$IPAD_ID" recordVideo --codec=h264 "$VIDEO" >/dev/null 2>&1 &
VIDEO_PID=$!

stop_recording() {
  if kill -0 "$VIDEO_PID" 2>/dev/null; then
    kill -INT "$VIDEO_PID" 2>/dev/null || true
    wait "$VIDEO_PID" 2>/dev/null || true
  fi
}
trap stop_recording EXIT

set +e
xcodebuild \
  -project "$REPO_ROOT/Basalt.xcodeproj" \
  -scheme Basalt \
  -destination "platform=iOS Simulator,id=$IPAD_ID" \
  -derivedDataPath "$REPO_ROOT/DerivedData" \
  -resultBundlePath "$RESULT_BUNDLE" \
  test-without-building
TEST_STATUS=$?
set -e

stop_recording
trap - EXIT
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$ARTIFACTS/xctest-attachments" 2>/dev/null || true
xcrun simctl io "$IPAD_ID" screenshot "$ARTIFACTS/ipad-final.png"

APP_PATH="$REPO_ROOT/DerivedData/Build/Products/Debug-iphonesimulator/Basalt.app"
if [[ -d "$APP_PATH" ]]; then
  xcrun simctl boot "$IPHONE_ID" 2>/dev/null || true
  xcrun simctl bootstatus "$IPHONE_ID" -b
  xcrun simctl install "$IPHONE_ID" "$APP_PATH"
  xcrun simctl launch \
    --terminate-running-process \
    --stdout="$ARTIFACTS/iphone-stdout.log" \
    --stderr="$ARTIFACTS/iphone-stderr.log" \
    "$IPHONE_ID" com.joshuasyson.Basalt --ui-testing
  sleep 3
  xcrun simctl io "$IPHONE_ID" screenshot "$ARTIFACTS/iphone-chat.png"
fi

exit "$TEST_STATUS"
