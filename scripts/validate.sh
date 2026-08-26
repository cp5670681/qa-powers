#!/usr/bin/env bash
# 校验插件结构：JSON 合法 + 每个 skill 有合法 frontmatter
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob
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

for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  if ! json_check "$f"; then
    echo "JSON 不合法：$f"; fail=1
  fi
done

# hooks.json 结构：每个 hook 事件必须是数组、每项含 matcher 与 hooks[0].command（有 jq 才查）
if command -v jq >/dev/null 2>&1; then
  while IFS= read -r event; do
    n=$(jq -r --arg e "$event" '.hooks[$e] | length' hooks/hooks.json 2>/dev/null)
    for ((i = 0; i < n; i++)); do
      jq -e --arg e "$event" --argjson i "$i" \
        '.hooks[$e][$i].matcher and (.hooks[$e][$i].hooks[0].command | type == "string")' \
        hooks/hooks.json >/dev/null 2>&1 || { echo "hooks.json 结构不合法：$event[$i] 缺 matcher 或 hooks[0].command"; fail=1; }
    done
  done < <(jq -r '.hooks | keys[]' hooks/hooks.json 2>/dev/null)
fi

# shell 脚本语法（含测试脚本）
for f in scripts/*.sh tests/*.sh; do
  bash -n "$f" || { echo "bash 语法错误：$f"; fail=1; }
done

# demo server JS 语法（有 node 才查）
if command -v node >/dev/null 2>&1; then
  node --check tests/demo/server.js || { echo "node 语法错误：tests/demo/server.js"; fail=1; }
fi

# 版本同步：plugin.json 与 marketplace.json 的 version 必须一致（发版靠版本号识别，两处不同步 /plugin update 会被跳过）
if command -v jq >/dev/null 2>&1; then
  pv=$(jq -r '.version' .claude-plugin/plugin.json 2>/dev/null)
  mv=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  pv=$(python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['version'])")
  mv=$(python3 -c "import json;print(json.load(open('.claude-plugin/marketplace.json'))['plugins'][0]['version'])")
fi
if [ -n "${pv:-}" ] && [ "$pv" != "$mv" ]; then
  echo "版本不一致：plugin.json=$pv marketplace.json=$mv（发版需两处同步）"; fail=1
fi

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

# hook 放行回归（权限放行脚本，注入向量防回归；无 jq 时测试自身 SKIP）
bash tests/test-allow-tools.sh || fail=1

# 版本核对脚本回归（config plugin_version 与插件版本核对）
bash tests/test-version-check.sh || fail=1

[ "$fail" -eq 0 ] && echo "OK：插件结构校验通过"
exit "$fail"
