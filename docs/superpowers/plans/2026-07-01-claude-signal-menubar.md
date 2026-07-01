# claude-signal Menu Bar Status Light — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar status light (SwiftBar plugin) that reflects the live state of Claude Code sessions, driven by Claude Code hooks.

**Architecture:** Claude Code hooks call `hook-handler.sh`, which writes per-session state to `state.json` and triggers an instant SwiftBar refresh. The `claude-signal.5s.sh` SwiftBar plugin reads `state.json`, prunes stale sessions, and renders an aggregated menu bar icon plus a per-session dropdown.

**Tech Stack:** bash, jq, SwiftBar (macOS). No compilation.

## Global Constraints

- Platform: macOS. Shell: bash. Hard dependency: `jq` (readme instructs `brew install jq`).
- `hook-handler.sh` MUST never disrupt Claude Code: on any error or missing input it exits 0 silently. It ALWAYS ends with exit code 0.
- All state lives under `CLAUDE_SIGNAL_DIR`, default `$HOME/.claude/claude-signal`. State file: `$CLAUDE_SIGNAL_DIR/state.json`.
- State schema (exact):
  ```json
  {"sessions": {"<session_id>": {"status": "idle|working|waiting|attention", "cwd": "/abs/path", "model": "claude-opus-4-8", "updated_at": 1751328000}}}
  ```
- Writes to `state.json` MUST be atomic: write to `mktemp` file, then `mv` over the target.
- Env vars for testability: `CLAUDE_SIGNAL_DIR` (state location), `CLAUDE_SIGNAL_NO_REFRESH` (if set, skip the `open` refresh call), `CLAUDE_SIGNAL_NOW` (plugin: override current epoch), `CLAUDE_SIGNAL_STALE_SECONDS` (plugin: stale threshold, default 1800).
- Event→status map (exact): `SessionStart`→`idle`, `UserPromptSubmit`→`working`, `Stop`→`waiting`, `Notification`→`attention`, `SessionEnd`→delete record.
- Status→icon map (exact): `working`→🟢, `waiting`→🟡, `attention`→🔴, `idle`→⚪.
- Menu bar aggregate priority (exact): `attention` > `working` > `waiting` > `idle`.
- SwiftBar plugin filename MUST be `claude-signal.5s.sh` (the `5s` heartbeat is the fallback refresh cadence).

---

## Task 1: Scaffold + hook-handler skeleton (SessionStart→idle)

**Files:**
- Create: `bin/hook-handler.sh`
- Create: `tests/helpers.sh`
- Create: `tests/test_hook_handler.sh`
- Create: `tests/run.sh`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `hook-handler.sh <EVENT>` — reads Claude Code hook JSON from stdin, extracts `.session_id` (required), `.cwd`, `.model`; upserts the session record in `state.json` with the mapped status and `updated_at=now`; triggers refresh unless `CLAUDE_SIGNAL_NO_REFRESH` is set; always exits 0.
  - `assert_eq <actual> <expected>` (in `tests/helpers.sh`) — prints `FAIL` and exits 1 on mismatch.
  - State schema and env vars per Global Constraints.

- [ ] **Step 1: Write the failing test**

Create `tests/helpers.sh`:

```bash
#!/usr/bin/env bash
assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: expected [$2] got [$1]" >&2
    exit 1
  fi
}

assert_contains() {
  # assert_contains <haystack> <needle>
  case "$1" in
    *"$2"*) : ;;
    *) echo "FAIL: [$1] does not contain [$2]" >&2; exit 1 ;;
  esac
}
```

Create `tests/test_hook_handler.sh`:

```bash
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
```

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
for t in "$DIR"/test_*.sh; do
  echo "== $t"
  bash "$t"
done
echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/run.sh && bash tests/test_hook_handler.sh`
Expected: FAIL — `bin/hook-handler.sh` does not exist (`No such file or directory`).

- [ ] **Step 3: Write minimal implementation**

Create `bin/hook-handler.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

EVENT="${1:-}"
DIR="${CLAUDE_SIGNAL_DIR:-$HOME/.claude/claude-signal}"
STATE="$DIR/state.json"

mkdir -p "$DIR"
[ -f "$STATE" ] || echo '{"sessions":{}}' > "$STATE"

payload="$(cat)"
sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$sid" ] || exit 0
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
model="$(printf '%s' "$payload" | jq -r '.model // empty' 2>/dev/null || true)"

event_to_status() {
  case "$1" in
    SessionStart) echo "idle" ;;
    *) echo "" ;;
  esac
}

trigger_refresh() {
  if [ -z "${CLAUDE_SIGNAL_NO_REFRESH:-}" ]; then
    open -g "swiftbar://refreshplugin?name=claude-signal" >/dev/null 2>&1 || true
  fi
}

status="$(event_to_status "$EVENT")"
[ -n "$status" ] || exit 0

now="$(date +%s)"
tmp="$(mktemp)"
jq --arg sid "$sid" --arg status "$status" --arg cwd "$cwd" --arg model "$model" --argjson now "$now" '
  .sessions[$sid] = {
    status: $status,
    cwd: (if $cwd == "" then (.sessions[$sid].cwd // "") else $cwd end),
    model: (if $model == "" then (.sessions[$sid].model // "") else $model end),
    updated_at: $now
  }' "$STATE" > "$tmp" && mv "$tmp" "$STATE"

trigger_refresh
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x bin/hook-handler.sh && bash tests/test_hook_handler.sh`
Expected: PASS — prints `PASS test_hook_handler (Task 1)`.

- [ ] **Step 5: Commit**

```bash
git add bin/hook-handler.sh tests/helpers.sh tests/test_hook_handler.sh tests/run.sh
git commit -m "feat: hook-handler skeleton with SessionStart->idle"
```

---

## Task 2: hook-handler full event mapping + SessionEnd removal

**Files:**
- Modify: `bin/hook-handler.sh`
- Modify: `tests/test_hook_handler.sh`

**Interfaces:**
- Consumes: `hook-handler.sh` from Task 1.
- Produces: `hook-handler.sh` now maps all events per Global Constraints. `SessionEnd` deletes the session record. `model` is preserved across events when a later event's payload omits it (already handled by the Task 1 jq `// (.sessions[$sid].model // "")`).

- [ ] **Step 1: Write the failing test**

Append to `tests/test_hook_handler.sh` (before the final `echo "PASS..."` line — replace that final line):

```bash
# Full lifecycle on a fresh session s2
echo '{"session_id":"s2","cwd":"/tmp/app","model":"claude-sonnet-4-6"}' | "$ROOT/bin/hook-handler.sh" SessionStart
assert_eq "$(jq -r '.sessions.s2.status' "$STATE")" "idle"

echo '{"session_id":"s2"}' | "$ROOT/bin/hook-handler.sh" UserPromptSubmit
assert_eq "$(jq -r '.sessions.s2.status' "$STATE")" "working"
# model preserved even though this payload omitted it
assert_eq "$(jq -r '.sessions.s2.model' "$STATE")" "claude-sonnet-4-6"

echo '{"session_id":"s2"}' | "$ROOT/bin/hook-handler.sh" Stop
assert_eq "$(jq -r '.sessions.s2.status' "$STATE")" "waiting"

echo '{"session_id":"s2"}' | "$ROOT/bin/hook-handler.sh" Notification
assert_eq "$(jq -r '.sessions.s2.status' "$STATE")" "attention"

echo '{"session_id":"s2"}' | "$ROOT/bin/hook-handler.sh" SessionEnd
assert_eq "$(jq -r '.sessions.s2 // "gone"' "$STATE")" "gone"

echo "PASS test_hook_handler (Task 2)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_hook_handler.sh`
Expected: FAIL — after `UserPromptSubmit` the status is not `working` (event_to_status returns "" so the record is unchanged/stays `idle`), assertion fails.

- [ ] **Step 3: Write minimal implementation**

In `bin/hook-handler.sh`, replace the `event_to_status` function with:

```bash
event_to_status() {
  case "$1" in
    SessionStart) echo "idle" ;;
    UserPromptSubmit) echo "working" ;;
    Stop) echo "waiting" ;;
    Notification) echo "attention" ;;
    *) echo "" ;;
  esac
}
```

Then, in `bin/hook-handler.sh`, insert the SessionEnd branch immediately AFTER the `model="..."` line and BEFORE the `event_to_status` function definition is used (i.e. right before `status="$(event_to_status "$EVENT")"`):

```bash
if [ "$EVENT" = "SessionEnd" ]; then
  tmp="$(mktemp)"
  jq --arg sid "$sid" 'del(.sessions[$sid])' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  trigger_refresh
  exit 0
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_hook_handler.sh`
Expected: PASS — prints `PASS test_hook_handler (Task 2)`.

- [ ] **Step 5: Commit**

```bash
git add bin/hook-handler.sh tests/test_hook_handler.sh
git commit -m "feat: full event mapping and SessionEnd removal in hook-handler"
```

---

## Task 3: SwiftBar plugin — read state, prune stale, aggregate menu bar icon

**Files:**
- Create: `bin/claude-signal.5s.sh`
- Create: `tests/test_plugin.sh`

**Interfaces:**
- Consumes: state schema and env vars per Global Constraints.
- Produces:
  - `claude-signal.5s.sh` — prints SwiftBar output to stdout. First line = menu bar label: `<icon> <count>` where `count` is the number of active (non-stale) sessions and `<icon>` is the aggregate per priority; if `count == 0`, first line is `⚪`. Second line is always `---`.
  - Shell functions `icon_for <status>` and (later, Task 4) the session list — reused within the script.

- [ ] **Step 1: Write the failing test**

Create `tests/test_plugin.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_plugin.sh`
Expected: FAIL — `bin/claude-signal.5s.sh` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `bin/claude-signal.5s.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

DIR="${CLAUDE_SIGNAL_DIR:-$HOME/.claude/claude-signal}"
STATE="$DIR/state.json"
NOW="${CLAUDE_SIGNAL_NOW:-$(date +%s)}"
STALE="${CLAUDE_SIGNAL_STALE_SECONDS:-1800}"

icon_for() {
  case "$1" in
    working) echo "🟢" ;;
    waiting) echo "🟡" ;;
    attention) echo "🔴" ;;
    *) echo "⚪" ;;
  esac
}

if [ ! -f "$STATE" ]; then
  echo "⚪"
  echo "---"
  exit 0
fi

# active (non-stale) sessions as a compact JSON array
active="$(jq -c --argjson now "$NOW" --argjson stale "$STALE" '
  [ .sessions | to_entries[]
    | select(($now - .value.updated_at) <= $stale)
    | {sid: .key, status: .value.status, cwd: .value.cwd, model: .value.model, updated_at: .value.updated_at}
  ]' "$STATE")"

count="$(printf '%s' "$active" | jq 'length')"

if [ "$count" -eq 0 ]; then
  echo "⚪"
  echo "---"
  exit 0
fi

agg="idle"
for s in attention working waiting idle; do
  has="$(printf '%s' "$active" | jq --arg s "$s" 'any(.[]; .status == $s)')"
  if [ "$has" = "true" ]; then agg="$s"; break; fi
done

echo "$(icon_for "$agg") $count"
echo "---"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x bin/claude-signal.5s.sh && bash tests/test_plugin.sh`
Expected: PASS — prints `PASS test_plugin (Task 3)`.

- [ ] **Step 5: Commit**

```bash
git add bin/claude-signal.5s.sh tests/test_plugin.sh
git commit -m "feat: SwiftBar plugin menu bar aggregate with stale pruning"
```

---

## Task 4: SwiftBar plugin — per-session dropdown with click-to-open

**Files:**
- Modify: `bin/claude-signal.5s.sh`
- Modify: `tests/test_plugin.sh`

**Interfaces:**
- Consumes: `claude-signal.5s.sh` and `icon_for` from Task 3.
- Produces: after the `---` separator, one dropdown line per active session sorted by `updated_at` descending. Line format: `<icon> <basename(cwd)>  <short_model> · <relative_time>` followed by SwiftBar params `| bash=/usr/bin/open param1="<cwd>" terminal=false` (omitted when `cwd` is empty). `short_model` strips a leading `claude-`. Relative time: `<10s`→`刚刚`, `<60s`→`Ns 前`, `<3600s`→`Nm 前`, else `Nh 前`. A trailing `---` and `刷新 | refresh=true` line close the menu.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_plugin.sh` (replace the final `echo "PASS test_plugin (Task 3)"` line):

```bash
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

echo "PASS test_plugin (Task 4)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_plugin.sh`
Expected: FAIL — output has no `🟢 myproj` line (dropdown not implemented yet).

- [ ] **Step 3: Write minimal implementation**

In `bin/claude-signal.5s.sh`, add these two functions right after the `icon_for` function:

```bash
rel_time() {
  local d=$(( NOW - $1 ))
  if [ "$d" -lt 10 ]; then echo "刚刚"
  elif [ "$d" -lt 60 ]; then echo "${d}s 前"
  elif [ "$d" -lt 3600 ]; then echo "$((d/60))m 前"
  else echo "$((d/3600))h 前"
  fi
}

short_model() { printf '%s' "${1#claude-}"; }
```

Then, at the END of the script (after the aggregate `echo "---"` line), append:

```bash
printf '%s' "$active" | jq -c 'sort_by(-.updated_at)[]' | while IFS= read -r row; do
  st="$(printf '%s' "$row" | jq -r '.status')"
  cwd="$(printf '%s' "$row" | jq -r '.cwd')"
  model="$(printf '%s' "$row" | jq -r '.model')"
  ua="$(printf '%s' "$row" | jq -r '.updated_at')"
  if [ -n "$cwd" ]; then name="$(basename "$cwd")"; else name="(unknown)"; fi
  sm="$(short_model "$model")"
  label="$(icon_for "$st") $name  $sm · $(rel_time "$ua")"
  if [ -n "$cwd" ]; then
    echo "$label | bash=/usr/bin/open param1=\"$cwd\" terminal=false"
  else
    echo "$label"
  fi
done

echo "---"
echo "刷新 | refresh=true"
```

Note: `count == 0` and no-state-file branches `exit 0` before this block, so an empty menu bar shows just ⚪ with no session lines.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_plugin.sh`
Expected: PASS — prints `PASS test_plugin (Task 4)`.

- [ ] **Step 5: Commit**

```bash
git add bin/claude-signal.5s.sh tests/test_plugin.sh
git commit -m "feat: per-session dropdown with click-to-open cwd"
```

---

## Task 5: Hooks config snippet + README + full-suite verification

**Files:**
- Create: `install/settings-hooks.json`
- Create: `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: a copy-pasteable hooks block and install/verify docs. No new runtime code.

- [ ] **Step 1: Write the hooks config snippet**

Create `install/settings-hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "~/.claude/claude-signal/hook-handler.sh SessionStart" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "~/.claude/claude-signal/hook-handler.sh UserPromptSubmit" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/.claude/claude-signal/hook-handler.sh Stop" } ] }
    ],
    "Notification": [
      { "hooks": [ { "type": "command", "command": "~/.claude/claude-signal/hook-handler.sh Notification" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "~/.claude/claude-signal/hook-handler.sh SessionEnd" } ] }
    ]
  }
}
```

- [ ] **Step 2: Verify the snippet is valid JSON**

Run: `jq . install/settings-hooks.json >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 3: Write the README**

Create `README.md`:

````markdown
# claude-signal

macOS 菜单栏状态灯,实时反映 Claude Code 会话状态。

- 🟢 Claude 正在跑  · 🟡 答完了该你了  · 🔴 需要授权/关注  · ⚪ 空闲
- 多会话并存,菜单栏取最需关注的状态;下拉列出每个会话,点击在 Finder 打开其目录。

## 依赖

```bash
brew install jq
brew install --cask swiftbar
```

## 安装

1. 拷贝 hook 脚本到 `~/.claude/claude-signal/` 并赋可执行权限:

   ```bash
   mkdir -p ~/.claude/claude-signal
   cp bin/hook-handler.sh ~/.claude/claude-signal/
   chmod +x ~/.claude/claude-signal/hook-handler.sh
   ```

2. 拷贝插件到 SwiftBar 的插件目录(首次启动 SwiftBar 时会让你选择该目录),并赋可执行权限:

   ```bash
   cp bin/claude-signal.5s.sh "$(defaults read com.ambarski.SwiftBar PluginDirectory)/"
   chmod +x "$(defaults read com.ambarski.SwiftBar PluginDirectory)/claude-signal.5s.sh"
   ```

   若上面的 `defaults read` 取不到目录,手动把 `bin/claude-signal.5s.sh` 拖到你在 SwiftBar 设置里指定的插件文件夹。

3. 把 `install/settings-hooks.json` 里的 `hooks` 块合并进 `~/.claude/settings.json`。若已有 `hooks`,把各事件条目并入对应数组即可。

4. **重开** 已有的 Claude Code 会话(hooks 只对新会话生效)。

## 验证

- 手动喂一条事件,确认状态写入:

  ```bash
  echo '{"session_id":"test","cwd":"'"$PWD"'","model":"claude-opus-4-8"}' \
    | ~/.claude/claude-signal/hook-handler.sh UserPromptSubmit
  jq . ~/.claude/claude-signal/state.json
  ```

  应看到 `test` 会话 `status: "working"`。菜单栏应变绿。

- 在真实 Claude Code 会话里发一条消息,菜单栏应变 🟢;Claude 答完变 🟡。

## 工作原理

Claude Code 在生命周期节点触发 hooks → `hook-handler.sh` 把状态写入 `~/.claude/claude-signal/state.json` 并用 `open -g "swiftbar://refreshplugin?name=claude-signal"` 让菜单栏秒级刷新。`claude-signal.5s.sh` 读状态、剔除超过 30 分钟没更新的僵尸会话、渲染图标。`5s` 是兜底心跳刷新频率。

## 覆盖范围

只监控 Claude Code CLI 会话(任意终端)。不监控 claude.ai 网页版、Claude 桌面 App。配在 `~/.claude/settings.json`(用户级)则所有项目都监控;配在项目 `.claude/settings.json` 则仅该项目。

## 测试

```bash
bash tests/run.sh
```
````

- [ ] **Step 4: Run the full test suite**

Run: `bash tests/run.sh`
Expected: both test files pass; ends with `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add install/settings-hooks.json README.md
git commit -m "docs: hooks config snippet and install/verify README"
```

---

## Self-Review Notes

- **Spec coverage:** architecture (Tasks 1–4), state schema (Task 1), event→status map (Tasks 1–2), aggregate priority (Task 3), dropdown + click-to-open (Task 4), stale pruning (Task 3), storage location (Global Constraints/README), hooks config (Task 5), monitoring scope (README). All covered.
- **Instant refresh** is fired by `hook-handler.sh` (Task 1, `trigger_refresh`), guarded by `CLAUDE_SIGNAL_NO_REFRESH` in tests.
- **Type/name consistency:** `icon_for`, `rel_time`, `short_model`, `active`, `trigger_refresh`, `event_to_status` used consistently across tasks. State keys `status/cwd/model/updated_at` consistent throughout.
