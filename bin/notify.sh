#!/usr/bin/env bash
# Alert the user that a session needs them: play a sound and show a dialog
# with a "跳转" button that focuses the session. Invoked detached by
# hook-handler.sh:  notify.sh <session_id>
set -uo pipefail
trap 'exit 0' EXIT   # an alert must never surface an error to the caller

SID="${1:-}"
DIR="${CLAUDE_SIGNAL_DIR:-$HOME/.claude/claude-signal}"
STATE="$DIR/state.json"
# Sound precedence: explicit env var > active pick (sounds/ + pointer file)
# > a legacy alert.* dropped in the state dir > a macOS system sound.
SOUND="${CLAUDE_SIGNAL_NOTIFY_SOUND:-}"
if [ -z "$SOUND" ] && [ -f "$DIR/sound" ]; then
  sel="$(cat "$DIR/sound" 2>/dev/null || true)"
  [ -n "$sel" ] && [ -f "$DIR/sounds/$sel" ] && SOUND="$DIR/sounds/$sel"
fi
if [ -z "$SOUND" ]; then
  for f in "$DIR"/alert.aiff "$DIR"/alert.wav "$DIR"/alert.mp3 "$DIR"/alert.m4a "$DIR"/alert.caf; do
    [ -f "$f" ] && { SOUND="$f"; break; }
  done
fi
[ -n "$SOUND" ] || SOUND="/System/Library/Sounds/Glass.aiff"
[ -n "$SID" ] || exit 0
[ -f "$STATE" ] || exit 0

status="$(jq -r --arg s "$SID" '.sessions[$s].status // ""' "$STATE" 2>/dev/null || true)"
title="$(jq -r --arg s "$SID" '.sessions[$s].title // ""' "$STATE" 2>/dev/null || true)"
cwd="$(jq -r --arg s "$SID" '.sessions[$s].cwd // ""' "$STATE" 2>/dev/null || true)"
term="$(jq -r --arg s "$SID" '.sessions[$s].term // ""' "$STATE" 2>/dev/null || true)"
tty="$(jq -r --arg s "$SID" '.sessions[$s].tty // ""' "$STATE" 2>/dev/null || true)"

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

# Play the sound FIRST, before any osascript — so a slow/denied automation
# permission on the frontmost checks below can never swallow the cue. Played
# in the FOREGROUND (this whole script is already detached from the hook via
# setsid, so it blocks nothing) with an absolute path in case PATH is bare.
# (Skipped in dry-run.)
AFPLAY="$(command -v afplay 2>/dev/null || echo /usr/bin/afplay)"
if [ -z "${CLAUDE_SIGNAL_NOTIFY_DRYRUN:-}" ]; then
  printf '%s sid=%s status=%s sound=%s\n' "$(date '+%F %T')" "$SID" "$status" "$SOUND" >> "$DIR/notify.log" 2>/dev/null || true
  [ -f "$SOUND" ] && "$AFPLAY" "$SOUND" >/dev/null 2>&1 || true
fi

# Are you already sitting in this very session? If so, the sound alone is
# enough — skip the dialog. "In this session" = the frontmost terminal tab's
# tty matches, or (no tty, e.g. desktop app / VS Code) the session's own app
# is frontmost. Overridable via env for testing.
frontapp="${CLAUDE_SIGNAL_FRONT_APP:-$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true)}"
if [ -n "${CLAUDE_SIGNAL_ACTIVE_TTY+x}" ]; then
  active_tty="$CLAUDE_SIGNAL_ACTIVE_TTY"
else
  case "$frontapp" in
    iTerm*)   active_tty="$(osascript -e 'tell application "iTerm" to tty of current session of current window' 2>/dev/null || true)" ;;
    Terminal) active_tty="$(osascript -e 'tell application "Terminal" to tty of selected tab of front window' 2>/dev/null || true)" ;;
    *)        active_tty="" ;;
  esac
fi
active=""
if [ -n "$active_tty" ] && [ "$tty" = "$active_tty" ]; then
  active=1                                   # exact: frontmost tab IS this session
elif [ -z "$active_tty" ]; then
  case "$term:$frontapp" in
    ":Claude") active=1 ;;                                            # desktop-app session, Claude frontmost
    "vscode:Code"|"vscode:Electron"|"vscode:Code - Insiders") active=1 ;;  # VS Code session, VS Code frontmost
  esac
fi

# Dry-run: report the composed alert instead of playing/showing it (tests).
if [ -n "${CLAUDE_SIGNAL_NOTIFY_DRYRUN:-}" ]; then
  echo "sound=$SOUND"
  echo "status=$status"
  echo "msg=$msg"
  echo "dialog=$([ -n "$active" ] && echo no || echo yes)"
  exit 0
fi

# already in this session -> the sound (played above) is enough, no dialog
[ -n "$active" ] && exit 0

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
