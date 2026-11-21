#!/usr/bin/env bash
# Manual rollback. Usage: rollback.sh <image> [tag]   (default tag: .previous_tag)
set -euo pipefail
IMAGE="${1:?usage: rollback.sh <image> [tag]}"
APP_DIR="${APP_DIR:-$HOME/app}"
TARGET="${2:-$(cat "$APP_DIR/.previous_tag" 2>/dev/null || true)}"
[[ -n "$TARGET" ]] || { echo "[rollback] no previous tag recorded and none given" >&2; exit 1; }
echo "[rollback] redeploying known-good tag: $TARGET"
exec "$(dirname "$0")/deploy.sh" "$IMAGE" "$TARGET"
