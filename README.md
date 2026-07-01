# claude-signal

macOS 菜单栏状态灯,实时反映 Claude Code 会话状态。

- 🟢 Claude 正在跑  · 🟡 答完了该你了  · 🔴 需要授权/关注  · ⚪ 空闲
- 多会话并存,菜单栏取最需关注的状态;下拉逐条列出会话,每条以该会话的**最新提问**为标题(过长截断),子菜单里放完整目录和模型。
- **点击一条会话** → 聚焦到正在跑它的终端/窗口:iTerm、Terminal.app 精确到标签页(按 tty 定位),VS Code 聚焦该文件夹窗口,Claude Code 桌面 App 会话则激活 App。首次点击 macOS 会弹窗要求授权 SwiftBar 控制终端,同意即可。子菜单的 📂 仍可在 Finder 打开目录。

## 依赖

```bash
brew install jq
brew install --cask swiftbar
```

## 安装

1. 拷贝 hook 脚本到 `~/.claude/claude-signal/` 并赋可执行权限:

   ```bash
   mkdir -p ~/.claude/claude-signal
   cp bin/hook-handler.sh bin/focus-session.sh ~/.claude/claude-signal/
   chmod +x ~/.claude/claude-signal/hook-handler.sh ~/.claude/claude-signal/focus-session.sh
   ```

2. 拷贝插件到 SwiftBar 的插件目录(首次启动 SwiftBar 时会让你选择该目录),并赋可执行权限:

   ```bash
   cp bin/claude-signal.5s.sh "$(defaults read com.ameba.SwiftBar PluginDirectory)/"
   chmod +x "$(defaults read com.ameba.SwiftBar PluginDirectory)/claude-signal.5s.sh"
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

## 需要你时的提醒

当会话进入 🟡(答完等你)或 🔴(要授权/关注)时,`hook-handler.sh` 会后台调 `notify.sh`:播放提示音 + 弹出对话框(带「跳转」按钮,点它直接聚焦到那个会话)。同一会话在短时间内不重复打扰(去抖)。可用环境变量调整:

| 变量 | 默认 | 作用 |
|---|---|---|
| `CLAUDE_SIGNAL_NOTIFY_ON` | `waiting attention` | 哪些状态提醒。改成 `attention` 即"只在 🔴 时提醒" |
| `CLAUDE_SIGNAL_NOTIFY_DEBOUNCE` | `20` | 同一会话最短提醒间隔(秒) |
| `CLAUDE_SIGNAL_NOTIFY_SOUND` | `/System/Library/Sounds/Glass.aiff` | 提示音 |
| `CLAUDE_SIGNAL_NO_NOTIFY` | (未设) | 设为任意值则完全关闭提醒 |

## 覆盖范围

只监控 Claude Code CLI 会话(任意终端)。不监控 claude.ai 网页版、Claude 桌面 App。配在 `~/.claude/settings.json`(用户级)则所有项目都监控;配在项目 `.claude/settings.json` 则仅该项目。

## 测试

```bash
bash tests/run.sh
```
