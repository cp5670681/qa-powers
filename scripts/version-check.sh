#!/usr/bin/env bash
# 版本核对：比较 config.yaml 记录的 plugin_version 与插件当前版本（.claude-plugin/plugin.json）。
# 规则（按语义化版本 X.Y.Z）：
#   - major.minor 相同（含仅 patch 差异的修复版）→ 不影响流程，静默（无输出，exit 0）
#   - major.minor 不同（大/小版本升级）→ 流程提示可能过时，输出警告（exit 1）
# 缺信息（config 无 plugin_version / 插件版本读不到 / config 不存在）→ 不干预（无输出，exit 0）。
# 用法：version-check.sh <config.yaml 路径>   默认为 .qa-powers/config.yaml
# 依赖：jq（读 plugin.json）；无 jq 时降级用 sed 读 version 字段。
set -euo pipefail

config="${1:-.qa-powers/config.yaml}"
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
plugin_json="$plugin_root/.claude-plugin/plugin.json"

# 插件当前版本：CLAUDE_PLUGIN_ROOT 由 Claude Code 注入；非插件环境退回脚本自身目录
cur=""
if command -v jq >/dev/null 2>&1; then
  cur=$(jq -r '.version // empty' "$plugin_json" 2>/dev/null || true)
else
  cur=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin_json" 2>/dev/null | head -1 || true)
fi

# config 记录的版本
cfg=""
if [ -f "$config" ]; then
  cfg=$(awk -F: '/^[[:space:]]*plugin_version[[:space:]]*:/{sub(/^[[:space:]]*/,"",$2); sub(/[[:space:]]*#.*$/,"",$2); sub(/[[:space:]]*\r?$/,"",$2); gsub(/["'"'"']/,"",$2); print $2; exit}' "$config")
fi

[ -n "$cur" ] && [ -n "$cfg" ] || exit 0

# 取 major.minor 段比较（仅 patch 差异不警告）
seg(){ printf '%s' "$1" | awk -F. '{print $1"."$2}'; }

[ "$(seg "$cur")" = "$(seg "$cfg")" ] && exit 0

echo "⚠️ qa-powers 插件版本已更新：config 记录 $cfg，当前插件 $cur（major.minor 不一致）。流程提示可能过时，建议重跑 /qa-powers:init 更新 config（仅 patch 版本差异不影响流程，无需处理）。"
exit 1
