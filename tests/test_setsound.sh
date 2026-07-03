#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
export CLAUDE_SIGNAL_DIR="$(mktemp -d)"
export CLAUDE_SIGNAL_NOTIFY_DRYRUN=1   # report instead of playing
SET="$ROOT/bin/set-sound.sh"

mkdir -p "$CLAUDE_SIGNAL_DIR/sounds"
: > "$CLAUDE_SIGNAL_DIR/sounds/one.wav"
: > "$CLAUDE_SIGNAL_DIR/sounds/two.mp3"

# switching writes the pointer file and reports the choice
assert_eq "$("$SET" two.mp3)" "active=two.mp3"
assert_eq "$(cat "$CLAUDE_SIGNAL_DIR/sound")" "two.mp3"
assert_eq "$("$SET" one.wav)" "active=one.wav"
assert_eq "$(cat "$CLAUDE_SIGNAL_DIR/sound")" "one.wav"

# a name not in the library is rejected -> pointer unchanged
"$SET" nope.wav >/dev/null 2>&1 || true
assert_eq "$(cat "$CLAUDE_SIGNAL_DIR/sound")" "one.wav"

echo "PASS test_setsound"
