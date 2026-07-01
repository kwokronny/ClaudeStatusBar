#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
export CLAUDE_SIGNAL_DIR="$(mktemp -d)"
export CLAUDE_SIGNAL_NO_REFRESH=1
STATE="$CLAUDE_SIGNAL_DIR/state.json"

# SessionStart -> idle
echo '{"session_id":"s1","cwd":"/tmp/proj","model":"claude-opus-4-8"}' \
  | "$ROOT/bin/hook-handler.sh" SessionStart
assert_eq "$(jq -r '.sessions.s1.status' "$STATE")" "idle"
assert_eq "$(jq -r '.sessions.s1.cwd' "$STATE")" "/tmp/proj"
assert_eq "$(jq -r '.sessions.s1.model' "$STATE")" "claude-opus-4-8"

# Missing session_id -> no crash, no record
echo '{"cwd":"/tmp/x"}' | "$ROOT/bin/hook-handler.sh" SessionStart
assert_eq "$(jq -r '.sessions | length' "$STATE")" "1"

echo "PASS test_hook_handler (Task 1)"
