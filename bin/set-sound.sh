#!/usr/bin/env bash
# Switch the active alert sound. Called by the SwiftBar "提示音" submenu:
#   set-sound.sh <filename-in-sounds-dir>
# Writes the choice to ~/.claude/claude-signal/sound and previews it.
set -uo pipefail
trap 'exit 0' EXIT

DIR="${CLAUDE_SIGNAL_DIR:-$HOME/.claude/claude-signal}"
SOUNDS="$DIR/sounds"
name="${1:-}"
[ -n "$name" ] || exit 0
[ -f "$SOUNDS/$name" ] || exit 0   # only accept a file that exists in the library

# record the active choice atomically
tmp="$(mktemp)"; printf '%s\n' "$name" > "$tmp" && mv "$tmp" "$DIR/sound"

# dry-run (tests): report instead of playing
if [ -n "${CLAUDE_SIGNAL_NOTIFY_DRYRUN:-}" ]; then
  echo "active=$name"
  exit 0
fi

# preview the chosen sound
afplay "$SOUNDS/$name" >/dev/null 2>&1 &
exit 0
