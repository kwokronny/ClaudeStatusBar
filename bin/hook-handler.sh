#!/usr/bin/env bash
set -euo pipefail

EVENT="${1:-}"
DIR="${CLAUDE_SIGNAL_DIR:-$HOME/.claude/claude-signal}"
STATE="$DIR/state.json"

mkdir -p "$DIR"
[ -f "$STATE" ] || echo '{"sessions":{}}' > "$STATE"

payload="$(cat)"
sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$sid" ] || exit 0
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
model="$(printf '%s' "$payload" | jq -r '.model // empty' 2>/dev/null || true)"

event_to_status() {
  case "$1" in
    SessionStart) echo "idle" ;;
    *) echo "" ;;
  esac
}

trigger_refresh() {
  if [ -z "${CLAUDE_SIGNAL_NO_REFRESH:-}" ]; then
    open -g "swiftbar://refreshplugin?name=claude-signal" >/dev/null 2>&1 || true
  fi
}

status="$(event_to_status "$EVENT")"
[ -n "$status" ] || exit 0

now="$(date +%s)"
tmp="$(mktemp)"
jq --arg sid "$sid" --arg status "$status" --arg cwd "$cwd" --arg model "$model" --argjson now "$now" '
  .sessions[$sid] = {
    status: $status,
    cwd: (if $cwd == "" then (.sessions[$sid].cwd // "") else $cwd end),
    model: (if $model == "" then (.sessions[$sid].model // "") else $model end),
    updated_at: $now
  }' "$STATE" > "$tmp" && mv "$tmp" "$STATE"

trigger_refresh
exit 0
