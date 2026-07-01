#!/usr/bin/env bash
# Alert the user that a session needs them: play a sound and show a dialog
# with a "跳转" button that focuses the session. Invoked detached by
# hook-handler.sh:  notify.sh <session_id>
set -uo pipefail
trap 'exit 0' EXIT   # an alert must never surface an error to the caller

SID="${1:-}"
DIR="${CLAUDE_SIGNAL_DIR:-$HOME/.claude/claude-signal}"
STATE="$DIR/state.json"
SOUND="${CLAUDE_SIGNAL_NOTIFY_SOUND:-/System/Library/Sounds/Glass.aiff}"
[ -n "$SID" ] || exit 0
[ -f "$STATE" ] || exit 0

status="$(jq -r --arg s "$SID" '.sessions[$s].status // ""' "$STATE" 2>/dev/null || true)"
title="$(jq -r --arg s "$SID" '.sessions[$s].title // ""' "$STATE" 2>/dev/null || true)"
cwd="$(jq -r --arg s "$SID" '.sessions[$s].cwd // ""' "$STATE" 2>/dev/null || true)"

case "$status" in
  waiting)   msg="答完了,该你了" ;;
  attention) msg="需要你授权 / 关注" ;;
  *)         exit 0 ;;   # only these two states alert
esac

if [ -n "$cwd" ]; then name="$(basename "$cwd")"; else name="会话"; fi
if [ -n "$title" ]; then
  body="「$title」"$'\n'"$msg  ·  $name"
else
  body="$msg  ·  $name"
fi

# Dry-run: report the composed alert instead of playing/showing it (tests).
if [ -n "${CLAUDE_SIGNAL_NOTIFY_DRYRUN:-}" ]; then
  echo "sound=$SOUND"
  echo "status=$status"
  echo "msg=$msg"
  exit 0
fi

# sound, non-blocking
[ -f "$SOUND" ] && afplay "$SOUND" >/dev/null 2>&1 &

# dialog with a jump button; body passed as argv so quotes/newlines in the
# title can't break the AppleScript
btn="$(osascript - "$body" 2>/dev/null <<'OSA'
on run argv
  try
    set r to display dialog (item 1 of argv) with title "claude-signal" buttons {"忽略", "跳转"} default button "跳转" with icon note
    return button returned of r
  on error
    return "忽略"
  end try
end run
OSA
)"

if [ "$btn" = "跳转" ]; then
  "$DIR/focus-session.sh" "$SID" >/dev/null 2>&1 || true
fi
exit 0
