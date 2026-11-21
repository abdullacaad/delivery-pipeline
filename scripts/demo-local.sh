#!/usr/bin/env bash
# Runs the whole deploy/rollback story on your machine (needs Docker + curl). No GitHub needed.
set -euo pipefail
cd "$(dirname "$0")/.."
export IMAGE=pipeline-demo SKIP_PULL=1 PORT=8080 APP_DIR="$(mktemp -d)"
trap 'docker rm -f app app-candidate >/dev/null 2>&1 || true' EXIT

ver() { curl -fsS "localhost:$PORT/version"; echo; }

docker build -q -t "$IMAGE:v1" --build-arg GIT_SHA=v1 .
for t in v2 v3 v4; do docker tag "$IMAGE:v1" "$IMAGE:$t"; done

echo; echo "== 1. first deploy (v1)";                         scripts/deploy.sh "$IMAGE" v1; ver
echo; echo "== 2. healthy upgrade (v2)";                       scripts/deploy.sh "$IMAGE" v2; ver
echo; echo "== 3. bad release fails pre-flight (v3)"
SIMULATE_FAILURE_STAGE=candidate scripts/deploy.sh "$IMAGE" v3 || echo "(expected: deploy rejected)"; ver
echo; echo "== 4. bad release fails after swap -> auto rollback (v4)"
SIMULATE_FAILURE_STAGE=live scripts/deploy.sh "$IMAGE" v4 || echo "(expected: rolled back)"; ver
echo; echo "== 5. manual rollback to v1";                      scripts/rollback.sh "$IMAGE" v1; ver
