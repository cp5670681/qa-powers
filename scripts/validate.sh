#!/usr/bin/env bash
# 校验插件结构：JSON 合法 + 每个 skill 有合法 frontmatter
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

for f in .claude-plugin/plugin.json hooks/hooks.json; do
  if ! jq empty "$f" 2>/dev/null; then
    echo "INVALID JSON: $f"; fail=1
  fi
done

if ! ls skills/*/SKILL.md >/dev/null 2>&1; then
  echo "NO SKILLS FOUND (skills/*/SKILL.md)"; fail=1
fi

for skill in skills/*/SKILL.md; do
  if ! head -1 "$skill" | grep -q '^---$'; then
    echo "MISSING FRONTMATTER START: $skill"; fail=1; continue
  fi
  fm=$(awk 'NR==1{next} /^---$/{exit} {print}' "$skill")
  echo "$fm" | grep -q '^name:' || { echo "MISSING name: $skill"; fail=1; }
  echo "$fm" | grep -q '^description:' || { echo "MISSING description: $skill"; fail=1; }
done

[ "$fail" -eq 0 ] && echo "OK: plugin structure valid"
exit "$fail"
