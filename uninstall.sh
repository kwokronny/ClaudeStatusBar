#!/usr/bin/env bash
# Remove claude-signal: unwire hooks, remove the plugin and installed files.
set -euo pipefail

DIR="$HOME/.claude/claude-signal"
SETTINGS="$HOME/.claude/settings.json"
SB_ID="com.ameba.SwiftBar"

echo "▶ 卸载 claude-signal"

# 1. 从 settings.json 移除 claude-signal 的 hook 条目(保留其它 hooks)
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  tmp="$(mktemp)"
  jq '
    if .hooks then
      .hooks |= with_entries(
        .value |= map(select(all(.hooks[]?; (.command // "") | contains("claude-signal/hook-handler.sh") | not)))
      )
      | .hooks |= with_entries(select(.value | length > 0))
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "· 已从 settings.json 移除 hooks"
fi

# 2. 移除插件
PLUGDIR="$(defaults read "$SB_ID" PluginDirectory 2>/dev/null || true)"
[ -n "$PLUGDIR" ] && rm -f "$PLUGDIR/claude-signal.5s.sh" && echo "· 已移除插件"

# 3. 移除安装目录(含 state / 脚本 / 自定义音效)
rm -rf "$DIR"
echo "· 已删除 $DIR"

open -g "swiftbar://refreshplugin?name=claude-signal" >/dev/null 2>&1 || true
echo "✔ 卸载完成。SwiftBar 本身未卸载(如需:brew uninstall --cask swiftbar)。"
