#!/usr/bin/env bash
set -euo pipefail

DIR="${CLAUDE_SIGNAL_DIR:-$HOME/.claude/claude-signal}"
STATE="$DIR/state.json"
NOW="${CLAUDE_SIGNAL_NOW:-$(date +%s)}"
STALE="${CLAUDE_SIGNAL_STALE_SECONDS:-1800}"

icon_for() {
  case "$1" in
    working) echo "🟢" ;;
    waiting) echo "🟡" ;;
    attention) echo "🔴" ;;
    *) echo "⚪" ;;
  esac
}

if [ ! -f "$STATE" ]; then
  echo "⚪"
  echo "---"
  exit 0
fi

# active (non-stale) sessions as a compact JSON array
active="$(jq -c --argjson now "$NOW" --argjson stale "$STALE" '
  [ .sessions | to_entries[]
    | select(($now - .value.updated_at) <= $stale)
    | {sid: .key, status: .value.status, cwd: .value.cwd, model: .value.model, updated_at: .value.updated_at}
  ]' "$STATE")"

count="$(printf '%s' "$active" | jq 'length')"

if [ "$count" -eq 0 ]; then
  echo "⚪"
  echo "---"
  exit 0
fi

agg="idle"
for s in attention working waiting idle; do
  has="$(printf '%s' "$active" | jq --arg s "$s" 'any(.[]; .status == $s)')"
  if [ "$has" = "true" ]; then agg="$s"; break; fi
done

echo "$(icon_for "$agg") $count"
echo "---"
