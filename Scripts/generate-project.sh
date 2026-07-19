#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODEGEN="$REPO_ROOT/.build-tools/xcodegen-2.46.0/bin/xcodegen"

"$SCRIPT_DIR/fetch-xcodegen.sh"
"$XCODEGEN" generate --spec "$REPO_ROOT/project.yml" --project "$REPO_ROOT"
