#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$REPO_ROOT/.build-cache/downloads"
VENDOR_DIR="$REPO_ROOT/Vendor"

VERSION="b10068"
ARCHIVE_NAME="llama-$VERSION-xcframework.zip"
ARCHIVE="$CACHE_DIR/$ARCHIVE_NAME"
FRAMEWORK="$VENDOR_DIR/llama.xcframework"
MARKER="$VENDOR_DIR/.llama-version"
URL="https://github.com/ggml-org/llama.cpp/releases/download/$VERSION/$ARCHIVE_NAME"
SHA256="5238397dd4ca305c9db537c3ae106948909ba2605e77d2d3463ac2d2ca08cc8a"

if [[ -d "$FRAMEWORK" ]] && [[ -f "$MARKER" ]] && [[ "$(<"$MARKER")" == "$VERSION" ]]; then
  exit 0
fi

mkdir -p "$CACHE_DIR" "$VENDOR_DIR"

if [[ -f "$ARCHIVE" ]] && ! echo "$SHA256  $ARCHIVE" | shasum -a 256 --check --status; then
  rm -f "$ARCHIVE"
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Downloading llama.cpp $VERSION XCFramework (247 MiB)..."
  curl --fail --location --silent --show-error "$URL" --output "$ARCHIVE"
fi

echo "$SHA256  $ARCHIVE" | shasum -a 256 --check --status

STAGING="$(mktemp -d "$REPO_ROOT/.build-cache/llama-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto -x -k "$ARCHIVE" "$STAGING"

FOUND="$(find "$STAGING" -type d -name llama.xcframework -print -quit)"
if [[ -z "$FOUND" ]]; then
  echo "llama.xcframework was not present in the verified archive." >&2
  exit 1
fi

if [[ -e "$FRAMEWORK" ]]; then
  rm -rf "$FRAMEWORK"
fi
cp -R "$FOUND" "$FRAMEWORK"
echo "$VERSION" > "$MARKER"

