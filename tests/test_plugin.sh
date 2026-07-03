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

# Dropdown lines: single working session, 12s old
cat > "$STATE" <<'JSON'
{"sessions":{
  "a":{"status":"working","cwd":"/tmp/foo/myproj","model":"claude-opus-4-8","updated_at":999988}
}}
JSON
out="$("$PLUGIN")"
assert_contains "$out" "🟢 myproj"
assert_contains "$out" "opus-4-8"
assert_contains "$out" "12s 前"
assert_contains "$out" 'param1="/tmp/foo/myproj"'
assert_contains "$out" "刷新 | refresh=true"

# Dropdown headline uses the session title (latest prompt), truncated,
# with cwd/model in the submenu
cat > "$STATE" <<'JSON'
{"sessions":{
  "t":{"status":"working","cwd":"/tmp/foo/myproj","model":"claude-opus-4-8","updated_at":999988,"title":"fix the login flow bug end to end"}
}}
JSON
out="$("$PLUGIN")"
assert_contains "$out" "fix the login flow"        # title shown as headline
assert_contains "$out" "…"                          # truncated (title > 20 chars)
assert_contains "$out" "-- 📂 myproj"               # dir in submenu
assert_contains "$out" "-- 🧠 opus-4-8"             # model in submenu

# No title -> headline falls back to the directory name
cat > "$STATE" <<'JSON'
{"sessions":{
  "u":{"status":"waiting","cwd":"/tmp/bar/webapp","model":"claude-sonnet-4-6","updated_at":999988,"title":""}
}}
JSON
out="$("$PLUGIN")"
assert_contains "$out" "🟡 webapp ·"                # dir name as headline

# sound picker submenu: lists the library, ✓ the active one, click switches
cat > "$STATE" <<'JSON'
{"sessions":{"s":{"status":"working","cwd":"/tmp/p","model":"","updated_at":999990}}}
JSON
mkdir -p "$CLAUDE_SIGNAL_DIR/sounds"
: > "$CLAUDE_SIGNAL_DIR/sounds/default.mp3"
: > "$CLAUDE_SIGNAL_DIR/sounds/红警-任务完成.wav"
printf '红警-任务完成.wav\n' > "$CLAUDE_SIGNAL_DIR/sound"
out="$("$PLUGIN")"
assert_contains "$out" "🔔 提示音"
assert_contains "$out" "-- ✓ 红警-任务完成 | bash="            # active one marked + clickable
assert_contains "$out" "set-sound.sh"
assert_contains "$out" 'param1="default.mp3"'                 # the other is switchable
rm -rf "$CLAUDE_SIGNAL_DIR/sounds" "$CLAUDE_SIGNAL_DIR/sound"

echo "PASS test_plugin (Task 4 + title + sound picker)"
