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
    | select(($now - (.value.updated_at // 0)) <= $stale)
    | {sid: .key, status: .value.status, cwd: .value.cwd, model: .value.model, title: (.value.title // ""), updated_at: (.value.updated_at // 0)}
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

FOCUS="$DIR/focus-session.sh"
printf '%s' "$active" | jq -c 'sort_by(-.updated_at)[]' | while IFS= read -r row; do
  sid="$(printf '%s' "$row" | jq -r '.sid')"
  st="$(printf '%s' "$row" | jq -r '.status')"
  cwd="$(printf '%s' "$row" | jq -r '.cwd')"
  model="$(printf '%s' "$row" | jq -r '.model')"
  ua="$(printf '%s' "$row" | jq -r '.updated_at')"
  # headline = latest prompt (truncated), falling back to the directory name
  disp="$(printf '%s' "$row" | jq -r '.title | if . == "" then "" elif length > 20 then .[0:20] + "…" else . end')"
  if [ -n "$cwd" ]; then name="$(basename "$cwd")"; else name="(unknown)"; fi
  if [ -n "$disp" ]; then headline="$disp"; else headline="$name"; fi
  sm="$(short_model "$model")"
  label="$(icon_for "$st") $headline · $(rel_time "$ua")"
  # click the row -> focus the terminal/window running that session
  echo "$label | bash=\"$FOCUS\" param1=\"$sid\" terminal=false"
  # submenu keeps the plain "open folder in Finder" affordance + model
  if [ -n "$cwd" ]; then
    echo "-- 📂 $name | bash=/usr/bin/open param1=\"$cwd\" terminal=false"
  else
    echo "-- 📂 (unknown)"
  fi
  echo "-- 🧠 $sm"
done

echo "---"

# sound picker: list the library, ✓ the active one, click to switch
SETSND="$DIR/set-sound.sh"
cur=""
[ -f "$DIR/sound" ] && cur="$(cat "$DIR/sound" 2>/dev/null || true)"
if [ -d "$DIR/sounds" ]; then
  echo "🔔 提示音"
  for f in "$DIR"/sounds/*; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    if [ "$b" = "$cur" ]; then mark="✓ "; else mark="　"; fi
    echo "-- ${mark}${b%.*} | bash=\"$SETSND\" param1=\"$b\" terminal=false refresh=true"
  done
fi

echo "刷新 | refresh=true"
