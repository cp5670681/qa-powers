#!/usr/bin/env bash
# scripts/allow-playwright-cli.sh 的表驱动回归测试。
# 这是权限放行脚本，注入向量会演化——新增绕过手法时先把向量加进 skip 组再修脚本。
# 用法：bash tests/test-allow-playwright-cli.sh（依赖 jq；缺 jq 时脚本本身降级，本测试跳过）
set -u
cd "$(dirname "$0")/.."

command -v jq >/dev/null 2>&1 || { echo "SKIP：无 jq"; exit 0; }

pass=0
fail=0

check() { # check <allow|skip> <命令字符串>
  local expect=$1 cmd=$2 out verdict
  out=$(printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | bash scripts/allow-playwright-cli.sh)
  if [ "$expect" = allow ]; then
    [[ "$out" == *'"permissionDecision":"allow"'* ]] && verdict=ok || verdict=bad
  else
    [ -z "$out" ] && verdict=ok || verdict=bad
  fi
  if [ "$verdict" = ok ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL 期望=%s 实际输出=%s 命令: %s\n' "$expect" "${out:-（无输出）}" "$cmd"
  fi
}

# ---- 应放行：纯 playwright-cli（含复合、env 前缀、中文 locator、hash 路由 URL）----
check allow 'playwright-cli snapshot'
check allow 'playwright-cli click "getByRole(button, { name: 提交 })"'
check allow 'playwright-cli open about:blank --browser chrome --headed'
check allow 'playwright-cli goto http://x/#/works/list'
check allow 'playwright-cli snapshot && playwright-cli fill "#user" "admin"'
check allow 'DEBUG=1 playwright-cli snapshot'
check allow 'A=1 playwright-cli a && B=2 playwright-cli b'

# ---- 不放行：混合命令 / 其他工具 ----
check skip 'cd /repo && playwright-cli goto http://x'
check skip 'usql "sqlite:///x" -f s.sql'
check skip 'playwright-cli requests | grep POST'
check skip 'playwright-cli a; rm -rf /tmp/x'
check skip 'playwright-cli close && echo done'
check skip 'bash scripts/other.sh'

# ---- 不放行：注入向量（安全边界，最高优先级防回归）----
check skip 'playwright-cli a & rm -rf /'                     # & 后台执行
check skip 'playwright-cli a&rm -rf /'                       # 无空格 &
check skip 'playwright-cli `id`'                             # 反引号命令替换
check skip 'playwright-cli $(rm -rf /tmp/x)'                 # $() 命令替换
check skip 'playwright-cli <(rm -rf /tmp/x)'                 # 进程替换
check skip 'playwright-cli a > /etc/passwd'                  # 重定向写文件
check skip 'playwright-cli screenshot >> ~/.bashrc'          # 追加写 shell 配置
check skip 'playwright-cli open "http://x?a=1&b=2"'          # URL 查询串 &（误伤，走确认）

# ---- 不放行：fail-closed 误伤（可接受，记录在案防"修复"成放行）----
check skip 'playwright-cli eval "click(); submit()"'
check skip 'playwright-cli fill "a|b" "a>b"'

# ---- 降级路径：畸形输入 / 空命令（应无输出且退出码 0）----
if out=$(echo 'not-json' | bash scripts/allow-playwright-cli.sh) && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL 畸形 JSON 应静默退出，实际: $out"
fi
if out=$(echo '{"tool_input":{}}' | bash scripts/allow-playwright-cli.sh) && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL 空命令应静默退出，实际: $out"
fi
if out=$(printf '{"tool_input":{"command":"playwright-cli a\nrm -rf /"}}' | bash scripts/allow-playwright-cli.sh) && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL 换行夹带命令应不放行，实际: $out"
fi

echo "hook 放行回归：$pass 通过，$fail 失败"
[ "$fail" -eq 0 ]
