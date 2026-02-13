#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/lock/discourse-rebuild.lock"
LOG_FILE="/var/log/discourse-rebuild.log"
DISCOURSE_DIR="/var/discourse"

REPO="${1:-unknown}"
WORKFLOW_URL="${2:-}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$REPO] $*" | tee -a "$LOG_FILE"
}

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Rebuild already in progress — skipping (the running rebuild will pick up latest code)"
    exit 0
fi

log "Rebuild triggered"
if [ -n "$WORKFLOW_URL" ]; then
    log "Workflow: $WORKFLOW_URL"
fi

cd "$DISCOURSE_DIR"
if ./launcher rebuild web >> "$LOG_FILE" 2>&1; then
    log "Rebuild completed successfully"
else
    STATUS=$?
    log "Rebuild failed with exit code $STATUS"
    exit $STATUS
fi
