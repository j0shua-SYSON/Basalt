#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Basalt's Apple build bootstrap requires macOS." >&2
  exit 1
fi

"$SCRIPT_DIR/fetch-llama.sh"
"$SCRIPT_DIR/generate-project.sh"

echo "Basalt is ready. Open Basalt.xcodeproj in Xcode."

