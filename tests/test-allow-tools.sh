#!/usr/bin/env bash
# scripts/allow-tools.sh 的表驱动回归测试。
# 这是权限放行脚本，注入向量会演化——新增绕过手法时先把向量加进 skip 组再修脚本。
# 用法：bash tests/test-allow-tools.sh（依赖 jq；缺 jq 时脚本本身降级，本测试跳过）
set -u
cd "$(dirname "$0")/.."

command -v jq >/dev/null 2>&1 || { echo "SKIP：无 jq"; exit 0; }

pass=0
fail=0

check() { # check <allow|skip> <命令字符串>
  local expect=$1 cmd=$2 out verdict
  out=$(printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | bash scripts/allow-tools.sh)
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
check allow 'playwright-cli open "http://x?a=1&b=2"'          # URL 查询串 &（引号内字面量，方向1放行）
check allow 'playwright-cli fill "a|b" "a>b"'                 # 填充值含 | >（引号内字面量，方向1放行）

# ---- 不放行：混合命令 / 其他工具 ----
check skip 'cd /repo && playwright-cli goto http://x'
check skip 'playwright-cli requests | grep POST'
check skip 'playwright-cli a; rm -rf /tmp/x'
check skip 'playwright-cli close && echo done'
check skip 'bash scripts/other.sh'

# ---- 应放行：只读 usql 内联查询（查询不改数据）----
check allow 'usql "sqlite:///x.db" -c "SELECT * FROM orders WHERE id=1"'
check allow 'usql "sqlite:///x" -c "select count(*) from t"'
check allow 'usql "sqlite:///x" -c "SHOW TABLES"'
check allow 'usql "sqlite:///x" -c "PRAGMA table_info(orders)"'
check allow 'usql "sqlite:///x" -c "EXPLAIN SELECT 1"'
check allow 'usql "sqlite:///x" -c "SELECT 1;"'
check allow "usql \"sqlite:///x\" -c 'SELECT id FROM users WHERE city = '\''Paris'\'''"
check allow 'usql "sqlite:///x" -c "SELECT id FROM orders WHERE flags & 8 = 8"'   # 引号内 &（位运算，方向1放行）
check allow 'usql "sqlite:///x" -c "\d employees"'            # psql 展示元命令（方向2）
check allow 'usql "sqlite:///x" -c "\dt"'
check allow 'usql "sqlite:///x" -c "\l"'
check allow 'usql "sqlite:///x" -c "\du"'
check allow 'usql "sqlite:///x" -c "\dS"'
check allow 'usql "sqlite:///x" -c "\d+ users"'

# ---- 不放行：usql 写库 / 脚本文件 / 无法静态判定的查询 ----
check skip 'usql "sqlite:///x" -f s.sql'
check skip 'usql "sqlite:///x" -c "DELETE FROM orders WHERE id=1"'
check skip 'usql "sqlite:///x" -c "INSERT INTO orders VALUES (1)"'
check skip 'usql "sqlite:///x" -c "UPDATE orders SET a=1 WHERE id=2"'
check skip 'usql "sqlite:///x" -c "DROP TABLE orders"'
check skip 'usql "sqlite:///x" -c "CREATE TABLE t (id int)"'
check skip 'usql "sqlite:///x" -c "SELECT * FROM a; DELETE FROM b"'
check skip 'usql "sqlite:///x" -c "WITH del AS (DELETE FROM t RETURNING *) SELECT * FROM del"'
check skip 'usql "sqlite:///x" -c "SELECT * INTO newt FROM t"'
check skip 'usql "sqlite:///x" -c "TRUNCATE TABLE t"'
check skip 'usql "sqlite:///x" -c "GRANT ALL ON t TO x"'
check skip 'usql "sqlite:///x" -c "EXPLAIN ANALYZE DELETE FROM orders"'
check skip 'usql "sqlite:///x" -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM t"'
check skip 'usql "sqlite:///x" -c "PRAGMA writable_schema=ON"'
check skip 'usql "sqlite:///x" -c "SELECT 1" && rm -rf /tmp/x'
check skip 'usql "sqlite:///x" -c "SELECT 1" | tee /tmp/out.txt'
check skip 'usql "sqlite:///x" -c "\! rm -rf /"'              # \! shell 转义
check skip 'usql "sqlite:///x" -c "\copy employees to /tmp/out.csv"'   # \copy 写文件
check skip 'usql "sqlite:///x" -c "\c otherdb"'              # \c 切库
check skip 'usql "sqlite:///x" -c "\o /tmp/out.txt"'         # \o 输出重定向
check skip 'usql "sqlite:///x" -c "\gset"'                    # \gset 执行
check skip 'usql "sqlite:///x" -c "\cd /tmp"'                # \cd shell cd
check skip 'usql "sqlite:///x" -c "\set var 1"'              # \set 会话变量
check skip 'usql "sqlite:///x" -c "\dup"'                     # 超长前缀伪装（\d* 边界：命令名后必跟空白/串尾）
check skip 'usql "sqlite:///x" -c "\dump t"'                  # 同上
check skip 'usql "sqlite:///x" -c "\delete"'                  # \d + 非白名单命令名（de 不在白名单）

# ---- 不放行：注入向量（安全边界，最高优先级防回归）----
check skip 'playwright-cli a & rm -rf /'                     # & 后台执行
check skip 'playwright-cli a&rm -rf /'                       # 无空格 &
check skip 'playwright-cli `id`'                             # 反引号命令替换
check skip 'playwright-cli $(rm -rf /tmp/x)'                 # $() 命令替换
check skip 'playwright-cli <(rm -rf /tmp/x)'                 # 进程替换
check skip 'playwright-cli a > /etc/passwd'                  # 重定向写文件
check skip 'playwright-cli screenshot >> ~/.bashrc'          # 追加写 shell 配置
check skip 'playwright-cli foo "$(id)"'                        # 双引号内 $() 仍是命令替换（方向1回归防漏）
check skip 'usql "sqlite:///x" -c "SELECT $(id)"'              # 同上，usql 读参被替换
check skip 'playwright-cli foo "`id`"'                         # 双引号内反引号命令替换
check skip 'playwright-cli a\" & rm -rf /'                     # 引号外 \" 转义不开启引号 + 后台 &
check skip 'playwright-cli a\" > /etc/passwd'                  # 引号外 \" 转义不开启引号 + 重定向
check skip 'playwright-cli a\" ; rm -rf /tmp/x'                # 引号外 \" 后的分号必须照常拆段（不能藏进"引号内"）
check skip "playwright-cli a\\' ; rm -rf /tmp/x"               # 引号外 \' 同上
check skip 'playwright-cli a\" | rm -rf /tmp/x'                # 引号外 \" 后的管道同上
check skip 'playwright-cli a\" || rm -rf /tmp/x'               # 引号外 \" 后的 || 同上
check skip 'usql "sqlite:///x" -c "SELECT 1" \" | rm -rf /tmp/x'   # usql 只读放行同样不许夹带隐藏段

# ---- 不放行：CR-2026-08 绕过向量（引号状态机/取参与 bash 语义脱节，均已实证复现过）----
check skip "usql \"sqlite:///x\" -c 'SELECT 1\\' && rm -rf /tmp"    # 单引号内反斜杠+引号在 bash 已闭合引号，&& 后是独立命令
check skip "usql \"sqlite:///x\" -c 'SELECT 1\\'; rm -rf /tmp"      # 同上，分号变体
check skip 'usql "sqlite:///x" -c "SELECT 1" -c "DROP TABLE t"'     # 多个 -c 依次执行，只检第一个会漏写语句
check skip "usql \"sqlite:///x\" -c 'SELECT 1' -c 'DROP TABLE t'"   # 多个 -c（单引号形式）
check skip 'usql "sqlite:///x" -c "SELECT 1" -f evil.sql'           # -c 与 -f 并存：usql 先跑文件内容（不受检）
check skip 'usql "sqlite:///x" --file=evil.sql -c "SELECT 1"'       # --file= 长选项变体
check skip 'usql "sqlite:///x" -f=evil.sql -c "SELECT 1"'           # -f= 变体
check skip 'usql "sqlite:///x" -c "SELECT 1 \"x\" ; DELETE FROM t"' # 旧提取被 \" 截断，分号+写语句藏在截断点后
check skip 'usql "sqlite:///x" --command "SELECT 1"'                # --command 长选项不受检，不放行
check skip 'usql "sqlite:///x" -c "SELECT 1" && usql "sqlite:///x" -c "DROP TABLE t"'   # 段统一为 usql，多 -c 检查兜底

# ---- 应放行：CR-2026-08 修复保住的合法路径（防止后续"修复"成误伤）----
check allow 'usql "sqlite:///x" -c "SELECT 1" 2>&1'             # 引号外 N>&N fd 重定向豁免（引号感知版）
check allow 'usql "sqlite:///x" -c="SELECT 1"'                  # -c= 无空格形式（Go flag 语义，bash 分词为单一 token）

# ---- 不放行：fail-closed 误伤（可接受，记录在案防"修复"成放行）----
check skip 'playwright-cli eval "click(); submit()"'       # 引号内多语句（有意 fail-closed，方向1不放开分号）
check skip 'playwright-cli eval "a\; b"'                    # 双引号内 \; 非 bash 转义，分号仍字面量须 fail-closed（防回归）

# ---- 降级路径：畸形输入 / 空命令（应无输出且退出码 0）----
if out=$(echo 'not-json' | bash scripts/allow-tools.sh) && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL 畸形 JSON 应静默退出，实际: $out"
fi
if out=$(echo '{"tool_input":{}}' | bash scripts/allow-tools.sh) && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL 空命令应静默退出，实际: $out"
fi
# 换行夹带命令：JSON 里 \n 转义、经 jq 还原为真实换行。注意用 printf %s——
# 旧实现裸 printf 会把格式串里的 \n 输出成裸换行产生非法 JSON，用例在 jq 解析处静默退出，
# 测的是"畸形 JSON 降级"而非"多行命令拆段"。
if out=$(printf '%s' '{"tool_input":{"command":"playwright-cli a\nrm -rf /"}}' | bash scripts/allow-tools.sh) && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL 换行夹带命令应不放行，实际: $out"
fi
# 引号跨行未闭合（-c 的 SQL 带真实换行）：tokenize 输出 UNTERM，fail-closed 不放行
if out=$(printf '%s' '{"tool_input":{"command":"usql \"sqlite:///x\" -c \"SELECT 1\nFROM t\""}}' | bash scripts/allow-tools.sh) && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL 引号跨行未闭合应不放行，实际: $out"
fi

echo "hook 放行回归：$pass 通过，$fail 失败"
[ "$fail" -eq 0 ]
