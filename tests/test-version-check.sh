#!/usr/bin/env bash
# scripts/version-check.sh 的表驱动回归测试。
# 用法：bash tests/test-version-check.sh（独立于 jq：脚本内有无 jq 只影响读 plugin.json 的路径）
set -u
cd "$(dirname "$0")/.."

pass=0
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

PLUGIN_ROOT="$tmp"
mkdir -p "$PLUGIN_ROOT/.claude-plugin"

mkplugin() { printf '{"name":"qa-powers","version":"%s"}\n' "$1" > "$PLUGIN_ROOT/.claude-plugin/plugin.json"; }
mkconf()  { printf 'browser:\n  channel: chrome\nplugin_version: %s\n' "$1" > "$tmp/c.yaml"; }

# check <should_warn> <desc> <plugin_version> <config_plugin_version|<missing>|none>
check() {
  local should_warn=$1 desc=$2 pv=${3:-} cv=${4:-}
  pv="${pv:-0.3.7}"; mkplugin "$pv"
  if [ "$cv" = none ] || [ "$cv" = missing ]; then
    printf 'browser:\n  channel: chrome\n' > "$tmp/c.yaml"
  else
    mkconf "$cv"
  fi
  local out status
  out=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash scripts/version-check.sh "$tmp/c.yaml" 2>&1)
  status=$?
  if [ "$should_warn" = warn ]; then
    if [ "$status" -eq 1 ] && [ -n "$out" ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      printf 'FAIL 期望警告 exit1+有输出 | status=%s out=%s | %s\n' "$status" "${out:-（空）}" "$desc"
    fi
  else
    if [ "$status" -eq 0 ] && [ -z "$out" ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      printf 'FAIL 期望静默 exit0 | status=%s out=%s | %s\n' "$status" "${out:-（空）}" "$desc"
    fi
  fi
}

# ---- 警告：major.minor 不同 ----
check warn  '小版本不同（0.3.7 -> 0.4.0）'    0.4.0 0.3.7
check warn  '大版本不同（0.3.7 -> 1.0.0）'    1.0.0 0.3.7
check warn  '缺 patch（0.3.7 -> 1.0）'        1.0   0.3.7

# ---- 静默：版本相同 / 仅 patch 差异 / 缺信息 ----
check quiet '版本相同'                         0.3.7 0.3.7
check quiet '仅 patch 不同（0.3.7 -> 0.3.8）' 0.3.8 0.3.7
check quiet 'patch 高版本（0.3.10 vs 0.3.7）' 0.3.10 0.3.7
check quiet 'config 无 plugin_version'        0.3.7 none
check quiet 'config 文件不存在'               0.3.7 missing

# ---- 行内注释：plugin_version 值后带 # 注释，注释不应并进版本串致误报 ----
mkplugin 0.3.8
printf 'plugin_version: 0.3.7 # init 时写入\n' > "$tmp/c.yaml"
out=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash scripts/version-check.sh "$tmp/c.yaml" 2>&1); status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL 期望静默 exit0（行内注释被并入版本串？）| status=%s out=%s\n' "$status" "$out"
fi

# ---- 非插件环境：CLAUDE_PLUGIN_ROOT 未设时从脚本自身目录读版本 ----
out=$(bash scripts/version-check.sh /tmp/opencode/nonexistent-config.yaml 2>&1); status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL 期望缺 config 静默 exit0 | status=%s out=%s | 非插件环境兜底\n' "$status" "$out"
fi

echo "version-check 回归：pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
