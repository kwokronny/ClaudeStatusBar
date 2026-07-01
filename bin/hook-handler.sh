#!/usr/bin/env bash
set -euo pipefail

# Never disrupt Claude Code: whatever happens below, exit 0.
trap 'exit 0' EXIT

EVENT="${1:-}"
DIR="${CLAUDE_SIGNAL_DIR:-$HOME/.claude/claude-signal}"
STATE="$DIR/state.json"

mkdir -p "$DIR"
if [ ! -f "$STATE" ]; then
  tmp_init="$(mktemp)"
  echo '{"sessions":{}}' > "$tmp_init" && mv "$tmp_init" "$STATE"
fi

payload="$(cat)"
sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$sid" ] || exit 0
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
model="$(printf '%s' "$payload" | jq -r '.model // empty' 2>/dev/null || true)"

# Session title = latest user prompt. Prefer the hook payload's prompt
# (present on UserPromptSubmit); otherwise fall back to the transcript's
# most recent last-prompt entry. Empty when neither is available.
# Terminal identity, so a menu click can focus the exact window later.
# TERM_PROGRAM / the controlling tty are inherited from the Claude Code
# process's environment (empty when it runs in the desktop app).
term="${TERM_PROGRAM:-}"
tty=""
raw_tty="$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d '[:space:]' || true)"
if [ -n "$raw_tty" ] && [ "$raw_tty" != "??" ]; then tty="/dev/$raw_tty"; fi

transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
title="$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null || true)"
if [ -z "$title" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  title="$(jq -rc 'select(.type=="last-prompt") | .lastPrompt' "$transcript" 2>/dev/null | tail -1 || true)"
fi

event_to_status() {
  case "$1" in
    SessionStart) echo "idle" ;;
    UserPromptSubmit) echo "working" ;;
    Stop) echo "waiting" ;;
    Notification) echo "attention" ;;
    *) echo "" ;;
  esac
}

trigger_refresh() {
  if [ -z "${CLAUDE_SIGNAL_NO_REFRESH:-}" ]; then
    open -g "swiftbar://refreshplugin?name=claude-signal" >/dev/null 2>&1 || true
  fi
}

if [ "$EVENT" = "SessionEnd" ]; then
  tmp="$(mktemp)"
  jq --arg sid "$sid" 'del(.sessions[$sid])' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  trigger_refresh
  exit 0
fi

status="$(event_to_status "$EVENT")"
[ -n "$status" ] || exit 0

now="$(date +%s)"
tmp="$(mktemp)"
jq --arg sid "$sid" --arg status "$status" --arg cwd "$cwd" --arg model "$model" --arg title "$title" --arg term "$term" --arg tty "$tty" --argjson now "$now" '
  .sessions[$sid] = {
    status: $status,
    cwd: (if $cwd == "" then (.sessions[$sid].cwd // "") else $cwd end),
    model: (if $model == "" then (.sessions[$sid].model // "") else $model end),
    title: (if $title == "" then (.sessions[$sid].title // "") else ($title | gsub("[\\r\\n|]"; " ")) end),
    term: (if $term == "" then (.sessions[$sid].term // "") else $term end),
    tty: (if $tty == "" then (.sessions[$sid].tty // "") else $tty end),
    notified_at: (.sessions[$sid].notified_at // 0),
    updated_at: $now
  }' "$STATE" > "$tmp" && mv "$tmp" "$STATE"

# Alert when a session needs the user (answered & waiting, or needs auth),
# debounced so the same session doesn't nag repeatedly. Fired detached so
# the dialog never blocks Claude Code's hook.
case " ${CLAUDE_SIGNAL_NOTIFY_ON:-attention} " in *" $status "*) do_notify=1 ;; *) do_notify="" ;; esac
if [ -z "${CLAUDE_SIGNAL_NO_NOTIFY:-}" ] && [ -n "$do_notify" ]; then
  last="$(jq -r --arg s "$sid" '.sessions[$s].notified_at // 0' "$STATE" 2>/dev/null || echo 0)"
  if [ "$(( now - last ))" -ge "${CLAUDE_SIGNAL_NOTIFY_DEBOUNCE:-20}" ]; then
    tmp2="$(mktemp)"
    jq --arg s "$sid" --argjson now "$now" '.sessions[$s].notified_at = $now' "$STATE" > "$tmp2" && mv "$tmp2" "$STATE"
    ( "$DIR/notify.sh" "$sid" >/dev/null 2>&1 & )
  fi
fi

trigger_refresh
exit 0
