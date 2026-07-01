# claude-signal —— Claude Code 运行状态灯(macOS 菜单栏)

设计文档 · 2026-07-01

## 目标

一个 macOS 菜单栏状态灯,实时反映 Claude Code 会话的运行状态:Claude 是在跑、答完在等你、还是需要你授权。支持多会话并存,一眼看出哪个窗口在等你。

## 形态与技术栈

- **形态**:macOS 菜单栏图标(彩色圆点)
- **实现**:SwiftBar/xbar 插件(shell 脚本),无需编译 App
- **信号源**:Claude Code hooks(事件驱动,精确)

## 整体架构

```
Claude Code 会话 ──hook触发──▶ hook-handler.sh ──写入──▶ state.json
                                     │                        │
                                     └─触发即时刷新─┐          │读取
                                                   ▼          ▼
                                          SwiftBar ◀── claude-signal.5s.sh ──▶ 菜单栏灯
```

三个部件,各司其职,通过 `state.json` 这个明确接口通信:

### 1. hook-handler.sh(状态写入器)
- **职责**:接收 Claude Code hook 调用,更新单个会话的状态,并触发菜单栏即时刷新。
- **输入**:Claude Code 通过 stdin 传入的 JSON,含 `session_id`、`cwd`、`hook_event_name`、`model`(视事件而定)。事件类型也可由传给脚本的参数指定(`hook-handler.sh <event>`),以兼容各 hook 传参差异。
- **行为**:
  1. 读 stdin JSON,解析出 `session_id` / `cwd` / `model`。
  2. 按事件映射为会话状态(见下表),写入/更新 `state.json` 中该 `session_id` 的记录,`updated_at` 置为当前时间。`SessionEnd` 则删除该记录。
  3. 执行 `open -g "swiftbar://refreshplugin?name=claude-signal"` 触发秒级刷新(`-g` 不抢焦点)。
- **依赖**:`jq`(JSON 读写)、`open`(macOS 自带)。
- **健壮性**:JSON 解析失败或缺 `session_id` 时安静退出、不阻塞 Claude;对 `state.json` 的读改写用临时文件 + 原子 `mv`,避免并发写坏。始终 `exit 0`,绝不干扰 Claude Code 主流程。

### 2. state.json(状态存储)
- **位置**:`~/.claude/claude-signal/state.json`
- **结构**:以 `session_id` 为键的对象。
  ```json
  {
    "sessions": {
      "<session_id>": {
        "status": "working|waiting|attention|idle",
        "cwd": "/abs/path/to/project",
        "model": "claude-opus-4-8",
        "updated_at": 1751328000
      }
    }
  }
  ```

### 3. claude-signal.5s.sh(SwiftBar 插件)
- **位置**:SwiftBar 插件目录(README 说明),文件名后缀 `5s` = 5 秒兜底心跳。
- **职责**:读 `state.json` → 清理僵尸会话 → 聚合出菜单栏图标 → 渲染下拉菜单。
- **刷新**:即时刷新靠 hook 触发的 URL scheme;`5s` 心跳作兜底,并借每次刷新剔除 stale 会话。
- **依赖**:`jq`。

## 状态与灯色映射

| Hook 事件 | 会话状态 | 灯 | 含义 |
|---|---|---|---|
| `UserPromptSubmit` | `working` | 🟢 绿 | Claude 正在跑 |
| `Stop` | `waiting` | 🟡 黄 | 答完了,该你了 |
| `Notification` | `attention` | 🔴 红 | 要授权 / 需要你 |
| `SessionStart` | `idle` | ⚪ 灰 | 会话就绪,还没提问 |
| `SessionEnd` | (移除) | — | 会话结束 |

> 说明:`UserPromptSubmit`→`Stop` 已能框住"Claude 工作中"这段,故不引入 `PreToolUse`/`PostToolUse`(YAGNI)。

## 菜单栏聚合逻辑

按优先级取最"需要关注"的状态作为菜单栏图标:

```
attention(🔴) > working(🟢) > waiting(🟡) > idle(⚪)
```

即:任一会话需要关注 → 红;否则任一在跑 → 绿;否则任一在等你 → 黄;否则灰。图标旁显示活跃会话数(如 `🟢 2`)。无任何会话时显示 ⚪(或按 SwiftBar 惯例淡出)。

## 下拉菜单

逐条列出活跃会话:

```
🟢 claude-signal        opus-4-8    · 12s 前
🟡 my-web-app           sonnet-4-6  · 3m 前
🔴 api-service          opus-4-8    · 刚刚
─────────────
刷新
```

- 每条:`灯色 + 目录名(cwd 的 basename) + 模型简称 + 相对时间`。
- **点击一条会话** → 在 Finder 打开该会话的 `cwd`(`open <cwd>`)。

## 僵尸会话清理

终端被直接关闭不会触发 `SessionEnd`。插件在每次读取 `state.json` 时,把 `updated_at` 距今超过阈值(默认 30 分钟)的会话判为 stale 并从展示中剔除;下次 hook 写入时也会顺带压缩。阈值在插件脚本顶部以常量形式可调。

## 存放位置

- 状态与 hook 脚本:`~/.claude/claude-signal/`(`state.json`、`hook-handler.sh`)
- SwiftBar 插件:SwiftBar 的插件目录(安装步骤在 README 指引拷贝/软链)

## 监控范围

- 只监控 **Claude Code CLI** 会话,与所在终端无关(Terminal.app / iTerm2 / VS Code / JetBrains 终端均可)。
- 覆盖范围由 hooks 配在哪决定:配在 `~/.claude/settings.json`(用户级,默认)→ 所有项目、所有终端的会话都监控;只配在项目 `.claude/settings.json` → 仅该项目的会话。
- 每个终端窗口 = 一个独立 `session_id`,并存展示。
- 不监控 claude.ai 网页版、Claude 桌面 App、以及非 Claude Code 的普通进程。
- hooks 配好*之前*已启动的会话不会生效,需重开该会话。

## Hooks 配置

在 `~/.claude/settings.json` 的 `hooks` 中,为 `UserPromptSubmit`、`Stop`、`Notification`、`SessionStart`、`SessionEnd` 各注册一条 command,均指向 `hook-handler.sh` 并以参数标明事件名。README 提供完整可粘贴片段。

## 交付物

- `hook-handler.sh`
- `claude-signal.5s.sh`
- `settings.json` hooks 配置片段
- `README.md`:安装 SwiftBar → 放插件 → 配 hooks → 验证

## 非目标(YAGNI)

- 不做原生 App / 不打包 .app
- 不接进程监控兜底(纯 hook 驱动)
- 不做点击"聚焦终端窗口"等复杂交互(仅打开目录)
- 不引入 `PreToolUse`/`PostToolUse` 细分工作态
