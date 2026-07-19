#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/.build-tools"
CACHE_DIR="$REPO_ROOT/.build-cache/downloads"

VERSION="2.46.0"
ARCHIVE_NAME="xcodegen-$VERSION.zip"
ARCHIVE="$CACHE_DIR/$ARCHIVE_NAME"
INSTALL_DIR="$TOOLS_DIR/xcodegen-$VERSION"
BINARY="$INSTALL_DIR/bin/xcodegen"
PRESETS="$INSTALL_DIR/share/xcodegen/SettingPresets"
URL="https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"

if [[ -x "$BINARY" ]] && [[ -d "$PRESETS" ]]; then
  exit 0
fi

mkdir -p "$CACHE_DIR" "$TOOLS_DIR"

if [[ -f "$ARCHIVE" ]] && ! echo "$SHA256  $ARCHIVE" | shasum -a 256 --check --status; then
  rm -f "$ARCHIVE"
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Downloading XcodeGen $VERSION..."
  curl --fail --location --silent --show-error "$URL" --output "$ARCHIVE"
fi

echo "$SHA256  $ARCHIVE" | shasum -a 256 --check --status

STAGING="$(mktemp -d "$TOOLS_DIR/xcodegen-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto -x -k "$ARCHIVE" "$STAGING"

FOUND_BINARY="$(find "$STAGING" -type f -path '*/xcodegen/bin/xcodegen' -print -quit)"
if [[ -z "$FOUND_BINARY" ]]; then
  echo "The XcodeGen distribution was not present in the verified archive." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
FOUND_DISTRIBUTION="$(cd "$(dirname "$FOUND_BINARY")/.." && pwd)"
cp -R "$FOUND_DISTRIBUTION/." "$INSTALL_DIR/"
chmod +x "$BINARY"
