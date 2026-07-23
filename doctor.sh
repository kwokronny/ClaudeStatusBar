#!/usr/bin/env bash
# 诊断:为什么菜单栏没出现 claude-signal 的灯。把输出发给分享者即可定位。
DIR="$HOME/.claude/claude-signal"
echo "==== claude-signal doctor ===="

# 1. SwiftBar 应用 + bundle id
if [ -d /Applications/SwiftBar.app ]; then
  SB_ID="$(defaults read /Applications/SwiftBar.app/Contents/Info CFBundleIdentifier 2>/dev/null)"
  echo "1) SwiftBar 应用: ✅ 已安装  (bundle id: ${SB_ID:-未知})"
else
  echo "1) SwiftBar 应用: ❌ 未安装  → 运行:brew install --cask swiftbar"
  SB_ID=""
fi

# 2. 进程
if pgrep -x SwiftBar >/dev/null; then echo "2) SwiftBar 进程: ✅ 运行中"
else echo "2) SwiftBar 进程: ❌ 没运行  → 运行:open -a SwiftBar"; fi

# 3. 插件目录设置
if [ -n "$SB_ID" ]; then
  PD="$(defaults read "$SB_ID" PluginDirectory 2>/dev/null || true)"
  if [ -z "$PD" ]; then
    echo "3) 插件目录: ❌ 未设置  → 打开 SwiftBar 首次欢迎窗/Preferences,把 Plugin Folder 设为 $DIR/plugins"
  elif [ "$PD" = "$DIR/plugins" ]; then
    echo "3) 插件目录: ✅ $PD"
  else
    echo "3) 插件目录: ⚠️ 当前是 $PD,但插件装在 $DIR/plugins"
    echo "     → 要么把 SwiftBar 的 Plugin Folder 改成 $DIR/plugins,要么把插件拷到 $PD"
  fi
fi

# 4. 插件文件
if [ -x "$DIR/plugins/claude-signal.5s.sh" ]; then echo "4) 插件文件: ✅ 存在且可执行"
elif [ -f "$DIR/plugins/claude-signal.5s.sh" ]; then echo "4) 插件文件: ⚠️ 存在但不可执行  → 运行:chmod +x $DIR/plugins/claude-signal.5s.sh"
else echo "4) 插件文件: ❌ 缺失  → 重新运行 ./install.sh"; fi

# 5. 隔离属性(下载解压常见)
if xattr "$DIR/plugins/claude-signal.5s.sh" 2>/dev/null | grep -q com.apple.quarantine; then
  echo "5) 隔离属性: ⚠️ 有 quarantine,SwiftBar 可能拒绝运行  → 运行:xattr -dr com.apple.quarantine $DIR"
else
  echo "5) 隔离属性: ✅ 无"
fi

# 6. 依赖
command -v jq >/dev/null 2>&1 && echo "6) jq: ✅" || echo "6) jq: ❌  → 运行:brew install jq"

# 7. 插件能否正常输出(SwiftBar 就是这么调它的)
echo "7) 插件试运行(前 3 行):"
if [ -f "$DIR/plugins/claude-signal.5s.sh" ]; then
  CLAUDE_SIGNAL_DIR="$DIR" bash "$DIR/plugins/claude-signal.5s.sh" 2>&1 | head -3 | sed 's/^/     /'
else
  echo "     (插件缺失,跳过)"
fi

# 8. hooks
if grep -q claude-signal "$HOME/.claude/settings.json" 2>/dev/null; then echo "8) Claude hooks: ✅ 已配置"
else echo "8) Claude hooks: ❌ 未配置  → 重新运行 ./install.sh"; fi

echo
echo "最常见修复:打开 SwiftBar → 首次欢迎窗选插件文件夹(或 Preferences → Plugin Folder)= $DIR/plugins,然后菜单里点 Refresh All。"
echo "若菜单栏图标很多(尤其刘海屏),灯可能被藏在刘海后面,试着减少其它菜单栏图标。"
