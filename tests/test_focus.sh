#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
export CLAUDE_SIGNAL_DIR="$(mktemp -d)"
export CLAUDE_SIGNAL_FOCUS_DRYRUN=1   # print resolved action, don't drive GUI
STATE="$CLAUDE_SIGNAL_DIR/state.json"
FOCUS="$ROOT/bin/focus-session.sh"

cat > "$STATE" <<'JSON'
{"sessions":{
  "it":{"status":"working","cwd":"/tmp/a","term":"iTerm.app","tty":"/dev/ttys003"},
  "te":{"status":"working","cwd":"/tmp/b","term":"Apple_Terminal","tty":"/dev/ttys004"},
  "vs":{"status":"working","cwd":"/tmp/c","term":"vscode","tty":"/dev/ttys005"},
  "app":{"status":"working","cwd":"/tmp/d","term":"","tty":""},
  "itnotty":{"status":"working","cwd":"/tmp/e","term":"iTerm.app","tty":""}
}}
JSON

assert_eq "$("$FOCUS" it)"       "iterm:/dev/ttys003"
assert_eq "$("$FOCUS" te)"       "terminal:/dev/ttys004"
assert_eq "$("$FOCUS" vs)"       "vscode:/tmp/c"
assert_eq "$("$FOCUS" app)"      "app-fallback"
# terminal type but no tty -> can only activate the whole app
assert_eq "$("$FOCUS" itnotty)"  "activate:iTerm.app"
# unknown session id -> no output, no crash
assert_eq "$("$FOCUS" nope)"     ""

echo "PASS test_focus"
