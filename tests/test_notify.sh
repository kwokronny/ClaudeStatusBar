#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
export CLAUDE_SIGNAL_DIR="$(mktemp -d)"
export CLAUDE_SIGNAL_NOTIFY_DRYRUN=1   # report the alert, don't play/show it
STATE="$CLAUDE_SIGNAL_DIR/state.json"
NOTIFY="$ROOT/bin/notify.sh"

cat > "$STATE" <<'JSON'
{"sessions":{
  "w":{"status":"waiting","cwd":"/tmp/a","title":"fix login"},
  "a":{"status":"attention","cwd":"/tmp/b","title":"deploy prod"},
  "r":{"status":"working","cwd":"/tmp/c","title":"still running"}
}}
JSON

assert_contains "$("$NOTIFY" w)" "msg=答完了,该你了"
assert_contains "$("$NOTIFY" a)" "msg=需要你授权 / 关注"

# sound resolution: no custom file -> falls back to a system sound
assert_contains "$("$NOTIFY" w)" "sound=/System/Library/Sounds/"
# a user-supplied alert.* in the state dir is preferred automatically
: > "$CLAUDE_SIGNAL_DIR/alert.wav"
assert_contains "$("$NOTIFY" w)" "sound=$CLAUDE_SIGNAL_DIR/alert.wav"
rm -f "$CLAUDE_SIGNAL_DIR/alert.wav"
# a running session does not alert -> no output
assert_eq "$("$NOTIFY" r)" ""
# unknown session -> no output, no crash
assert_eq "$("$NOTIFY" nope)" ""

echo "PASS test_notify"
