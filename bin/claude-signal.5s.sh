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

rel_time() {
  local d=$(( NOW - $1 ))
  if [ "$d" -lt 10 ]; then echo "刚刚"
  elif [ "$d" -lt 60 ]; then echo "${d}s 前"
  elif [ "$d" -lt 3600 ]; then echo "$((d/60))m 前"
  else echo "$((d/3600))h 前"
  fi
}

short_model() { printf '%s' "${1#claude-}"; }

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

printf '%s' "$active" | jq -c 'sort_by(-.updated_at)[]' | while IFS= read -r row; do
  st="$(printf '%s' "$row" | jq -r '.status')"
  cwd="$(printf '%s' "$row" | jq -r '.cwd')"
  model="$(printf '%s' "$row" | jq -r '.model')"
  ua="$(printf '%s' "$row" | jq -r '.updated_at')"
  if [ -n "$cwd" ]; then name="$(basename "$cwd")"; else name="(unknown)"; fi
  sm="$(short_model "$model")"
  label="$(icon_for "$st") $name  $sm · $(rel_time "$ua")"
  if [ -n "$cwd" ]; then
    echo "$label | bash=/usr/bin/open param1=\"$cwd\" terminal=false"
  else
    echo "$label"
  fi
done

echo "---"
echo "刷新 | refresh=true"
