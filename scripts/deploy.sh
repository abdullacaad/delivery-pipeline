#!/usr/bin/env bash
# Deploy <image>:<tag> with a pre-flight gate and automatic rollback.
#
#   1. Start the new tag as a *candidate* on PORT+1 and health-check it.
#      If it fails, abort: the live container is never touched.
#   2. Swap the live container to the new tag and health-check again.
#      If it fails, restart the previously deployed tag (rollback) and exit 1.
#   3. On success, record state: .current_tag / .previous_tag.
#
# Env: APP_DIR (state dir), PORT, NAME, RETRIES, SKIP_PULL=1 (local demo),
#      SIMULATE_FAILURE_STAGE=candidate|live (demo only: forces an unhealthy start)
set -euo pipefail

IMAGE="${1:?usage: deploy.sh <image> <tag>}"
TAG="${2:?usage: deploy.sh <image> <tag>}"
APP_DIR="${APP_DIR:-$HOME/app}"
PORT="${PORT:-8080}"
CAND_PORT=$((PORT + 1))
NAME="${NAME:-app}"
RETRIES="${RETRIES:-15}"
SIM="${SIMULATE_FAILURE_STAGE:-}"

mkdir -p "$APP_DIR"
STATE_CUR="$APP_DIR/.current_tag"
STATE_PREV="$APP_DIR/.previous_tag"
CURRENT="$(cat "$STATE_CUR" 2>/dev/null || true)"

log() { echo "[deploy] $*"; }

# healthy <port> <expected-tag>: /health must say ok AND report the expected version
healthy() {
  local body
  for _ in $(seq 1 "$RETRIES"); do
    body="$(curl -fsS --max-time 3 "http://127.0.0.1:$1/health" 2>/dev/null || true)"
    if grep -Eq '"status": ?"ok"' <<<"$body" && grep -Fq "\"$2\"" <<<"$body"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# start <container-name> <tag> <host-port> <stage>
start() {
  local extra=()
  if [[ "$SIM" == "$4" ]]; then extra=(-e SIMULATE_UNHEALTHY=1); fi
  docker run -d --name "$1" --restart unless-stopped \
    -p "$3:8000" -e "APP_VERSION=$2" \
    ${extra[@]+"${extra[@]}"} "$IMAGE:$2" >/dev/null
}

if [[ "${SKIP_PULL:-0}" != "1" ]]; then
  log "pulling $IMAGE:$TAG"
  docker pull "$IMAGE:$TAG"
fi

# ---- 1. pre-flight candidate ----
log "pre-flight: candidate $TAG on :$CAND_PORT"
docker rm -f "$NAME-candidate" >/dev/null 2>&1 || true
start "$NAME-candidate" "$TAG" "$CAND_PORT" candidate
if ! healthy "$CAND_PORT" "$TAG"; then
  docker logs --tail 30 "$NAME-candidate" || true
  docker rm -f "$NAME-candidate" >/dev/null 2>&1 || true
  log "FAILED pre-flight. Live container (${CURRENT:-none}) was not touched."
  exit 1
fi
docker rm -f "$NAME-candidate" >/dev/null

# ---- 2. swap live ----
log "switching live ${CURRENT:-none} -> $TAG"
docker rm -f "$NAME" >/dev/null 2>&1 || true
start "$NAME" "$TAG" "$PORT" live

if healthy "$PORT" "$TAG"; then
  if [[ -n "$CURRENT" && "$CURRENT" != "$TAG" ]]; then echo "$CURRENT" > "$STATE_PREV"; fi
  echo "$TAG" > "$STATE_CUR"
  docker image prune -f >/dev/null 2>&1 || true
  log "OK: $TAG is live (previous: $(cat "$STATE_PREV" 2>/dev/null || echo none))"
  exit 0
fi

# ---- 3. automatic rollback ----
log "live container unhealthy after swap -> ROLLING BACK"
docker logs --tail 30 "$NAME" || true
docker rm -f "$NAME" >/dev/null 2>&1 || true
if [[ -n "$CURRENT" ]]; then
  start "$NAME" "$CURRENT" "$PORT" none
  if healthy "$PORT" "$CURRENT"; then
    log "rolled back: $CURRENT is live again"
  else
    log "CRITICAL: rollback to $CURRENT is also unhealthy"
  fi
else
  log "no previous release recorded; nothing to roll back to"
fi
exit 1
