#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
export CLAUDE_SIGNAL_DIR="$(mktemp -d)"
export CLAUDE_SIGNAL_NOTIFY_DRYRUN=1   # report the alert, don't play/show it
export CLAUDE_SIGNAL_FRONT_APP="Finder"   # neutral default: not in any session
STATE="$CLAUDE_SIGNAL_DIR/state.json"
NOTIFY="$ROOT/bin/notify.sh"

cat > "$STATE" <<'JSON'
{"sessions":{
  "w":{"status":"waiting","cwd":"/tmp/a","title":"fix login","term":"iTerm.app","tty":"/dev/ttys013"},
  "a":{"status":"attention","cwd":"/tmp/b","title":"deploy prod","term":"iTerm.app","tty":"/dev/ttys013"},
  "r":{"status":"working","cwd":"/tmp/c","title":"still running"},
  "d":{"status":"attention","cwd":"/tmp/e","title":"desktop sess","term":"","tty":""}
}}
JSON

assert_contains "$("$NOTIFY" w)" "msg=答完了,该你了"
assert_contains "$("$NOTIFY" a)" "msg=需要你授权 / 关注"

# --- dialog-vs-sound-only (are you already in this session?) ---
# background session (front app is Finder) -> full dialog
assert_contains "$("$NOTIFY" a)" "dialog=yes"
# you're in this exact iTerm tab (tty matches frontmost) -> sound only
assert_contains "$(CLAUDE_SIGNAL_FRONT_APP=iTerm2 CLAUDE_SIGNAL_ACTIVE_TTY=/dev/ttys013 "$NOTIFY" a)" "dialog=no"
# a different iTerm tab is frontmost -> still dialog
assert_contains "$(CLAUDE_SIGNAL_FRONT_APP=iTerm2 CLAUDE_SIGNAL_ACTIVE_TTY=/dev/ttys999 "$NOTIFY" a)" "dialog=yes"
# desktop-app session while Claude is frontmost -> sound only
assert_contains "$(CLAUDE_SIGNAL_FRONT_APP=Claude CLAUDE_SIGNAL_ACTIVE_TTY= "$NOTIFY" d)" "dialog=no"
# desktop-app session while some other app is frontmost -> dialog
assert_contains "$(CLAUDE_SIGNAL_FRONT_APP=Finder CLAUDE_SIGNAL_ACTIVE_TTY= "$NOTIFY" d)" "dialog=yes"

# sound resolution: no custom file -> falls back to a system sound
assert_contains "$("$NOTIFY" w)" "sound=/System/Library/Sounds/"
# a user-supplied alert.* in the state dir is preferred automatically
: > "$CLAUDE_SIGNAL_DIR/alert.wav"
assert_contains "$("$NOTIFY" w)" "sound=$CLAUDE_SIGNAL_DIR/alert.wav"
rm -f "$CLAUDE_SIGNAL_DIR/alert.wav"
# the active pointer (library pick) outranks a legacy alert.*
mkdir -p "$CLAUDE_SIGNAL_DIR/sounds"; : > "$CLAUDE_SIGNAL_DIR/sounds/pick.wav"; : > "$CLAUDE_SIGNAL_DIR/alert.wav"
printf 'pick.wav\n' > "$CLAUDE_SIGNAL_DIR/sound"
assert_contains "$("$NOTIFY" w)" "sound=$CLAUDE_SIGNAL_DIR/sounds/pick.wav"
rm -f "$CLAUDE_SIGNAL_DIR/sound" "$CLAUDE_SIGNAL_DIR/alert.wav"; rm -rf "$CLAUDE_SIGNAL_DIR/sounds"
# a running session does not alert -> no output
assert_eq "$("$NOTIFY" r)" ""
# unknown session -> no output, no crash
assert_eq "$("$NOTIFY" nope)" ""

echo "PASS test_notify"
