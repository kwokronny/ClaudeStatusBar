#!/usr/bin/env bash
# One-command installer for claude-signal.
#   git clone <repo> && cd claude-signal && ./install.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/.claude/claude-signal"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD="~/.claude/claude-signal/hook-handler.sh"   # tilde: expanded by the shell at hook time

echo "▶ 安装 claude-signal"
trap 'echo "  ✗ 安装在第 $LINENO 行中断,请把以上输出发给分享者。" >&2' ERR

# 1. jq (必需)
if ! command -v jq >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then echo "· 安装 jq…"; brew install jq
  else echo "  ✗ 需要 jq,且未找到 Homebrew。请先安装:https://brew.sh 然后重跑。"; exit 1; fi
fi

# 2. SwiftBar (菜单栏宿主)
if [ ! -d "/Applications/SwiftBar.app" ]; then
  if command -v brew >/dev/null 2>&1; then echo "· 安装 SwiftBar…"; brew install --cask swiftbar
  else echo "  ✗ 未安装 SwiftBar,且无 Homebrew。请手动安装:https://swiftbar.app 然后重跑。"; exit 1; fi
fi

# 3. 脚本
echo "· 拷贝脚本到 $DIR"
mkdir -p "$DIR"
cp "$HERE/bin/hook-handler.sh" "$HERE/bin/focus-session.sh" "$HERE/bin/notify.sh" "$HERE/bin/set-sound.sh" "$DIR/"
chmod +x "$DIR/hook-handler.sh" "$DIR/focus-session.sh" "$DIR/notify.sh" "$DIR/set-sound.sh"

# 提示音库:仓库自带的音效拷到 sounds/,菜单栏可切换。首次安装播下默认指针。
if [ -d "$HERE/assets/sounds" ]; then
  mkdir -p "$DIR/sounds"
  cp "$HERE"/assets/sounds/* "$DIR/sounds/" 2>/dev/null || true
  if [ ! -f "$DIR/sound" ]; then
    if [ -f "$DIR/sounds/没座.mp3" ]; then printf '没座.mp3\n' > "$DIR/sound"
    else first="$(ls "$DIR/sounds" 2>/dev/null | head -1)"; [ -n "$first" ] && printf '%s\n' "$first" > "$DIR/sound"; fi
  fi
  # 清掉旧的单一 alert.*(已被音效库取代)
  rm -f "$DIR"/alert.aiff "$DIR"/alert.wav "$DIR"/alert.mp3 "$DIR"/alert.m4a "$DIR"/alert.caf
  echo "· 已安装音效库($(ls "$DIR/sounds" 2>/dev/null | wc -l | tr -d ' ') 个,菜单栏「🔔 提示音」可切换)"
fi

# 4. 插件目录 + 插件
# 动态读取 SwiftBar 真实 bundle id(不同版本可能不同),避免写错 defaults 域
SB_ID="$(defaults read /Applications/SwiftBar.app/Contents/Info CFBundleIdentifier 2>/dev/null || echo com.ameba.SwiftBar)"
# 强制把插件目录设为我们的目录(即使 SwiftBar 已设过别的),保证插件被加载
PLUGDIR="$DIR/plugins"; mkdir -p "$PLUGDIR"
defaults write "$SB_ID" PluginDirectory "$PLUGDIR" 2>/dev/null || true
defaults write "$SB_ID" SwiftBarLaunchAtLogin -bool true 2>/dev/null || true
echo "· 安装插件到 $PLUGDIR(SwiftBar id: $SB_ID)"
cp "$HERE/bin/claude-signal.5s.sh" "$PLUGDIR/"
chmod +x "$PLUGDIR/claude-signal.5s.sh"
# 去掉下载解压带来的隔离属性,否则 SwiftBar 可能拒绝运行插件
xattr -dr com.apple.quarantine "$DIR" 2>/dev/null || true

# 5. 合并 hooks 到 settings.json(幂等:先删旧的 claude-signal 条目再加)
echo "· 接入 hooks 到 $SETTINGS"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
tmp="$(mktemp)"
jq --arg cmd "$HOOK_CMD" '
  def wire($n):
    .hooks[$n] = (((.hooks[$n] // [])
      | map(select(all(.hooks[]?; (.command // "") | contains("claude-signal/hook-handler.sh") | not))))
      + [ { hooks: [ { type: "command", command: ($cmd + " " + $n) } ] } ]);
  .hooks = (.hooks // {})
  | wire("SessionStart") | wire("UserPromptSubmit") | wire("Stop")
  | wire("Notification") | wire("SessionEnd")
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# 6. 重启 SwiftBar,让它重新读取插件目录设置(仅 open -a 不会重载已改的 pref)
osascript -e 'quit app "SwiftBar"' 2>/dev/null || true
sleep 1
open -a SwiftBar 2>/dev/null || true
( sleep 2; open -g "swiftbar://refreshplugin?name=claude-signal" >/dev/null 2>&1 || true ) &

cat <<'DONE'

✔ 安装完成。
  · 新开的 Claude Code 会话会自动点亮菜单栏(已在运行的会话需重开才生效)。
  · 切换提示音:菜单栏下拉「🔔 提示音」点选即可。
  · 加自己的音效:丢进 ~/.claude/claude-signal/sounds/(mp3/wav/aiff/m4a/caf)。
  · 菜单栏没出现灯?运行 ./doctor.sh 自检(常见:去 SwiftBar 首次欢迎窗/Preferences 把 Plugin Folder 设为 ~/.claude/claude-signal/plugins,再 Refresh All)。
  · 卸载:./uninstall.sh
DONE
