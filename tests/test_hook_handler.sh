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
# updated_at must be a JSON number (the plugin's stale arithmetic depends on it)
assert_eq "$(jq -r '.sessions.s1.updated_at | type' "$STATE")" "number"

# Missing session_id -> no crash, no record
echo '{"cwd":"/tmp/x"}' | "$ROOT/bin/hook-handler.sh" SessionStart
assert_eq "$(jq -r '.sessions | length' "$STATE")" "1"

# Full lifecycle on a fresh session s2
echo '{"session_id":"s2","cwd":"/tmp/app","model":"claude-sonnet-4-6"}' | "$ROOT/bin/hook-handler.sh" SessionStart
assert_eq "$(jq -r '.sessions.s2.status' "$STATE")" "idle"

echo '{"session_id":"s2","prompt":"fix the login bug"}' | "$ROOT/bin/hook-handler.sh" UserPromptSubmit
assert_eq "$(jq -r '.sessions.s2.status' "$STATE")" "working"
# model preserved even though this payload omitted it
assert_eq "$(jq -r '.sessions.s2.model' "$STATE")" "claude-sonnet-4-6"
# title captured from the payload's prompt field
assert_eq "$(jq -r '.sessions.s2.title' "$STATE")" "fix the login bug"

echo '{"session_id":"s2"}' | "$ROOT/bin/hook-handler.sh" Stop
assert_eq "$(jq -r '.sessions.s2.status' "$STATE")" "waiting"
# title preserved across an event whose payload has no prompt
assert_eq "$(jq -r '.sessions.s2.title' "$STATE")" "fix the login bug"

echo '{"session_id":"s2"}' | "$ROOT/bin/hook-handler.sh" Notification
assert_eq "$(jq -r '.sessions.s2.status' "$STATE")" "attention"

echo '{"session_id":"s2"}' | "$ROOT/bin/hook-handler.sh" SessionEnd
assert_eq "$(jq -r '.sessions.s2 // "gone"' "$STATE")" "gone"

echo "PASS test_hook_handler (Task 2)"
