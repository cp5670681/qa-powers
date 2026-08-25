#!/usr/bin/env bash
# 校验插件结构：JSON 合法 + 每个 skill 有合法 frontmatter
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

json_check() {
  if command -v jq >/dev/null 2>&1; then
    jq empty "$1" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$1" >/dev/null 2>&1
  else
    echo "缺少依赖：校验 JSON 需要 jq 或 python3 任一"; exit 1
  fi
}

for f in .claude-plugin/plugin.json hooks/hooks.json; do
  if ! json_check "$f"; then
    echo "JSON 不合法：$f"; fail=1
  fi
done

if ! ls skills/*/SKILL.md >/dev/null 2>&1; then
  echo "未找到 skill（skills/*/SKILL.md）"; fail=1
fi

for skill in skills/*/SKILL.md; do
  if ! head -1 "$skill" | grep -q '^---$'; then
    echo "缺少 frontmatter 起始行（---）：$skill"; fail=1; continue
  fi
  fm=$(awk 'NR==1{next} /^---$/{exit} {print}' "$skill")
  echo "$fm" | grep -q '^name:' || { echo "缺少 name 字段：$skill"; fail=1; }
  echo "$fm" | grep -q '^description:' || { echo "缺少 description 字段：$skill"; fail=1; }
done

[ "$fail" -eq 0 ] && echo "OK：插件结构校验通过"
exit "$fail"
