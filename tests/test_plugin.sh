#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
export CLAUDE_SIGNAL_DIR="$(mktemp -d)"
export CLAUDE_SIGNAL_NOW=1000000
export CLAUDE_SIGNAL_STALE_SECONDS=1800
STATE="$CLAUDE_SIGNAL_DIR/state.json"
PLUGIN="$ROOT/bin/claude-signal.5s.sh"

# No state file at all -> grey, no sessions
out="$("$PLUGIN")"
assert_eq "$(printf '%s' "$out" | head -1)" "⚪"

# Two active sessions (working + waiting), one stale (idle, updated long ago)
cat > "$STATE" <<'JSON'
{"sessions":{
  "a":{"status":"working","cwd":"/tmp/a","model":"claude-opus-4-8","updated_at":999990},
  "b":{"status":"waiting","cwd":"/tmp/b","model":"claude-sonnet-4-6","updated_at":999980},
  "c":{"status":"idle","cwd":"/tmp/c","model":"claude-opus-4-8","updated_at":900000}
}}
JSON
out="$("$PLUGIN")"
# aggregate: working present, no attention -> 🟢 ; count excludes stale c -> 2
assert_eq "$(printf '%s' "$out" | head -1)" "🟢 2"

# attention wins over working
cat > "$STATE" <<'JSON'
{"sessions":{
  "a":{"status":"working","cwd":"/tmp/a","model":"claude-opus-4-8","updated_at":999990},
  "d":{"status":"attention","cwd":"/tmp/d","model":"claude-opus-4-8","updated_at":999995}
}}
JSON
out="$("$PLUGIN")"
assert_eq "$(printf '%s' "$out" | head -1)" "🔴 2"

echo "PASS test_plugin (Task 3)"
