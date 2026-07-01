#!/usr/bin/env bash
# Bring the terminal/window running a given Claude Code session to the front.
# Invoked by the SwiftBar plugin when a session row is clicked:
#   focus-session.sh <session_id>
# Uses the term/tty recorded in state.json by hook-handler.sh.
set -uo pipefail
trap 'exit 0' EXIT   # a menu click must never surface an error

SID="${1:-}"
DIR="${CLAUDE_SIGNAL_DIR:-$HOME/.claude/claude-signal}"
STATE="$DIR/state.json"
[ -n "$SID" ] || exit 0
[ -f "$STATE" ] || exit 0

exists="$(jq -r --arg s "$SID" 'if .sessions[$s] then "1" else "" end' "$STATE" 2>/dev/null || true)"
[ -n "$exists" ] || exit 0

term="$(jq -r --arg s "$SID" '.sessions[$s].term // ""' "$STATE" 2>/dev/null || true)"
tty="$(jq -r --arg s "$SID" '.sessions[$s].tty // ""' "$STATE" 2>/dev/null || true)"
cwd="$(jq -r --arg s "$SID" '.sessions[$s].cwd // ""' "$STATE" 2>/dev/null || true)"

# Decide what to do. A terminal type without a captured tty can only be
# activated as a whole app.
case "$term" in
  iTerm.app)      action="iterm" ;;
  Apple_Terminal) action="terminal" ;;
  vscode)         action="vscode" ;;
  *)              action="app-fallback" ;;
esac
if [ -z "$tty" ] && { [ "$term" = "iTerm.app" ] || [ "$term" = "Apple_Terminal" ]; }; then
  action="activate-$term"
fi

# Dry-run: print the resolved action instead of executing (used by tests).
if [ -n "${CLAUDE_SIGNAL_FOCUS_DRYRUN:-}" ]; then
  case "$action" in
    iterm)    echo "iterm:$tty" ;;
    terminal) echo "terminal:$tty" ;;
    vscode)   echo "vscode:$cwd" ;;
    activate-iTerm.app)      echo "activate:iTerm.app" ;;
    activate-Apple_Terminal) echo "activate:Apple_Terminal" ;;
    *)        echo "app-fallback" ;;
  esac
  exit 0
fi

focus_iterm() {
  osascript 2>/dev/null <<OSA
tell application "iTerm"
  activate
  repeat with w in windows
    repeat with tb in tabs of w
      repeat with s in sessions of tb
        if tty of s is "$1" then
          select w
          tell tb to select
          tell s to select
          return
        end if
      end repeat
    end repeat
  end repeat
end tell
OSA
}

focus_terminal() {
  osascript 2>/dev/null <<OSA
tell application "Terminal"
  activate
  repeat with w in windows
    repeat with tb in tabs of w
      if tty of tb is "$1" then
        set selected of tb to true
        set frontmost of w to true
        return
      end if
    end repeat
  end repeat
end tell
OSA
}

case "$action" in
  iterm)                   focus_iterm "$tty" || open -a iTerm ;;
  terminal)                focus_terminal "$tty" || open -a Terminal ;;
  vscode)                  [ -n "$cwd" ] && open -a "Visual Studio Code" "$cwd" || open -a "Visual Studio Code" ;;
  activate-iTerm.app)      open -a iTerm ;;
  activate-Apple_Terminal) open -a Terminal ;;
  app-fallback)
    # Claude Code desktop-app session, or an unrecognised terminal.
    open -a "Claude" 2>/dev/null || { [ -n "$cwd" ] && open "$cwd"; } ;;
esac
exit 0
