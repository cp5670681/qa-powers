#!/usr/bin/env bash
# PreToolUse hook：playwright-cli 命令自动放行（qa-powers 核心工具，装插件即免确认）。
# stdin 收 Claude Code 的工具调用 JSON；仅当命令拆分后每一段的首词都是 playwright-cli 时
# 输出 allow 决策，其余情况静默退出（exit 0 无输出 = 不干预，走默认权限流程）。
# 永不 deny、永不 exit 2（阻断）；无 jq 或 JSON 解析失败一律静默降级到默认确认。
# 只依赖 jq 是有意取舍（与 validate.sh 的 python3 双路径不同）：降级方向安全，损失仅是多几次确认。

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# fail-closed 元字符防线：&, <, >, `, $( 能在 playwright-cli 之外执行命令 / 写任意文件
# （后台执行 &、命令替换、进程替换、重定向）。含任一即不放行。&& 是已拆段的合法分隔符，先剔除再查；
# URL 查询串里的 & 会被误伤退回人工确认——宁可多确认，不误放行。
if printf '%s' "$cmd" | sed 's/&&//g' | grep -qE '[&<>`]|\$\('; then
  exit 0
fi

allow=1
# 按 shell 分隔符（&& || ; |）拆段；剥离段首环境变量赋值前缀后，首词必须是 playwright-cli
while IFS= read -r seg; do
  seg=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)+//')
  [ -n "$seg" ] || continue
  first=${seg%%[[:space:]]*}
  if [ "$first" != "playwright-cli" ]; then
    allow=0
    break
  fi
done < <(printf '%s\n' "$cmd" | sed -E 's/&&/\n/g; s/\|\|/\n/g; s/;/\n/g; s/\|/\n/g')

if [ "$allow" -eq 1 ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"qa-powers: playwright-cli 命令自动放行"}}'
fi
exit 0
