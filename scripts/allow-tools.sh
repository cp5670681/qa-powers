#!/usr/bin/env bash
# PreToolUse hook：playwright-cli 命令与「只读 usql 内联查询」自动放行（qa-powers 核心工具，装插件即免确认）。
# stdin 收 Claude Code 的工具调用 JSON；仅当命令拆分后每一段的首词都是同一个工具时才可能放行：
#   - 全部为 playwright-cli → 直接 allow（浏览器自动化，qa-powers 核心操作）
#   - 全部为 usql 且是单条只读内联查询（-c "SELECT/..."）→ allow（查询不改数据）
# 其余情况（写库、-f 读脚本文件、混合命令、注入向量）静默退出（exit 0 无输出 = 不干预，走默认权限流程）。
# 永不 deny、永不 exit 2（阻断）；无 jq 或 JSON 解析失败一律静默降级到默认确认。
# 只依赖 jq 是有意取舍（与 validate.sh 的 python3 双路径不同）：降级方向安全，损失仅是多几次确认。

input=$(cat)

# 判断 usql 命令是否为「单条只读内联查询」（-c 带引号，以只读关键字开头）。
# 读取 -c 的值：优先双引号、否则单引号；提取失败视为非只读（回退人工确认）。
# 防御（宁可多确认、不误放行）：
#   - 无 -c 内联（如 -f 脚本文件）→ 不放行，脚本内容无从静态判定
#   - 内嵌分号（多语句）→ 不放行；结尾单个分号允许
#   - WITH（数据修改 CTE）、INTO（SELECT INTO 建表）→ 不放行
#   - 显式写关键字（INSERT/UPDATE/DELETE/CREATE/ALTER/DROP/TRUNCATE/GRANT/REVOKE/CALL/MERGE）→ 不放行
#   - 首词不是只读关键字（SELECT/SHOW/DESC/DESCRIBE/PRAGMA/EXPLAIN/VALUES）→ 不放行
is_readonly_usql_query() {
  local cmd="$1" sql
  sql=$(printf '%s\n' "$cmd" | grep -oE '[[:space:]]-c([[:space:]]*=[[:space:]]*|[[:space:]]+)"[^"]*"' 2>/dev/null \
        | sed -E 's/^[[:space:]]*-c([[:space:]]*=[[:space:]]*|[[:space:]]+)"//; s/"$//' | head -1)
  if [ -z "$sql" ]; then
    sql=$(printf '%s\n' "$cmd" | grep -oE "[[:space:]]-c([[:space:]]*=[[:space:]]*|[[:space:]]+)'[^']*'" 2>/dev/null \
          | sed -E "s/^[[:space:]]*-c([[:space:]]*=[[:space:]]*|[[:space:]]+)'//; s/'$//" | head -1)
  fi
  [ -n "$sql" ] || return 1

  sql=${sql%;}
  sql=$(printf '%s' "$sql" | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/,""); print}' | head -1)
  [ -n "$sql" ] || return 1

  case "$sql" in *';'*) return 1 ;; esac
  # EXPLAIN 不带 ANALYZE 才只读：EXPLAIN ANALYZE（含 EXPLAIN(ANALYZE,...)）会真实执行语句，
  # DML 靠上面写关键字兜底，这里再显式拦截补刀（防写关键字漏网，如经存储过程隐藏的写）。
  if printf '%s' "$sql" | grep -qiE '^[[:space:]]*explain' && printf '%s' "$sql" | grep -qi 'analyze'; then
    return 1
  fi
  # PRAGMA 赋值（name=value 或 name(..)=value）会改动连接/文件状态，非只读；仅 PRAGMA name(...) 查询型安全。
  if printf '%s' "$sql" | grep -qiE '^[[:space:]]*pragma' && printf '%s' "$sql" | grep -q '='; then
    return 1
  fi
  if printf '%s' "$sql" | grep -qiE '(^|[^a-zA-Z_])(with|into)([^a-zA-Z_]|$)'; then
    return 1
  fi
  if printf '%s' "$sql" | grep -qiE '(^|[^a-zA-Z_])(insert|update|delete|create|alter|drop|truncate|grant|revoke|call|merge)([^a-zA-Z_]|$)'; then
    return 1
  fi
  # psql/usql 纯展示元命令白名单：命令 token 后必须跟空白或串尾，杜绝 \dup/\dump 等超长前缀被放行。
  # 仅放行无副作用（describe/list）：\d+（verbose）与 \d、\dt、\dv、\di、\dn、\df、\ds、\dp、\do、\dx、\db、\du、\l、\? 均只读。
  # 危险元命令（\! shell、\o 写文件、\copy、\c/\connect 切库、\cd、\set/\unset、\gset/\gexec、\e、\i/\ir）不以「上述命令名+边界」开头，落到下方 return 1 拦截。
  if printf '%s' "$sql" | grep -qE '^\\d\+?([[:space:]]|$)|^\\(dt|dv|di|dn|df|ds|dS|dp|do|dx|db|du|l|[?])([[:space:]]|$)'; then
    return 0
  fi
  case "$sql" in
    [Ss][Ee][Ll][Ee][Cc][Tt]*|[Ss][Hh][Oo][Ww]*|[Dd][Ee][Ss][Cc][Rr][Ii][Bb][Ee]*|[Dd][Ee][Ss][Cc][[:space:]]*|[Pp][Rr][Aa][Gg][Mm][Aa]*|[Ee][Xx][Pp][Ll][Aa][Ii][Nn]*|[Vv][Aa][Ll][Uu][Ee][Ss]*)
      return 0 ;;
    *) return 1 ;;
  esac
}

# 按 shell 分隔符（&& || ; |）拆段，但跳过单/双引号内的分隔符（否则 -c "SELECT 1;" 会被拆断）。
# 引号内不处理转义分隔符则一律按普通字符；仅剥离一层成对的引号所在区域。
split_segments() {
  printf '%s\n' "$1" | awk '
  {
    line=$0; n=length(line); i=1; seg=""; q=""
    while (i<=n) {
      c=substr(line,i,1)
      if (q=="") {
        if (c=="\"") { q="\""; seg=seg c; i++; continue }
        if (c==sprintf("%c",39)) { q=sprintf("%c",39); seg=seg c; i++; continue }
        if (c=="&" && substr(line,i+1,1)=="&") { if (seg!="") print seg; seg=""; i+=2; continue }
        if (c=="|" && substr(line,i+1,1)=="|") { if (seg!="") print seg; seg=""; i+=2; continue }
        if (c=="|") { if (seg!="") print seg; seg=""; i++; continue }
        if (c==";") { if (seg!="") print seg; seg=""; i++; continue }
        seg=seg c; i++
      } else {
        if (c==q) { q=""; seg=seg c; i++; continue }
        if (c=="\\" && i+1<=n) { seg=seg c substr(line,i+1,1); i+=2; continue }
        seg=seg c; i++
      }
    }
    if (seg!="") print seg
  }'
}

# 是否有「引号内的分号」（如 playwright-cli eval "click(); submit()"）。
# 这类多语句行为有意 fail-closed 不放行（原始 naive 拆段会把它拆成非统一工具而跳过，此处显式保留该语义）。
has_quote_inner_semicolon() {
  printf '%s\n' "$1" | awk '
  { line=$0; n=length(line); q=""; i=1
    while (i<=n) {
      c=substr(line,i,1)
      if (q=="") {
        if (c=="\"") q="\""
        else if (c==sprintf("%c",39)) q=sprintf("%c",39)
        else if (c=="\\" && i+1<=n) i++
      } else {
        if (c=="\\" && i+1<=n) { i++; i++; continue }
        if (c==q) q=""
        else if (c==";") print "HAS"
      }
      i++
    }
  }' | grep -q HAS
}

# 引号感知的 fail-closed 元字符防线：&(非 &&)、<、>、`、$(
# 引号内的这些字符一律当字面量（SQL 里的 a='x&y'、URL 查询串 ?a=1&b=2、playwright-cli 的填充值都是字面量）。
# 引号外的单个 & 是后台执行，< > 是输入/输出重定向，` $() 是命令替换——含任一即不放行。
# 与旧版「整串无脑 grep」不同：旧版把引号内字面量也误伤（URL &、SQL &、2>&1）；新版只扫引号外。
# 豁免：&& 是已拆段的合法分隔符（跳过）；N>&N / N>&- 是 fd 重定向（无副作用，预替换成安全占位）。
has_danger_metachars() {
  local cleaned
  cleaned=$(printf '%s\n' "$1" | sed -E 's/[0-9]>(&[0-9]|&-)/{FD}/g')
  printf '%s\n' "$cleaned" | awk '
  { line=$0; n=length(line); i=1; q=""
    while (i<=n) {
      c=substr(line,i,1)
      if (q=="") {
        if (c=="\\" && i+1<=n) { i+=2; continue }   # 引号外 \ 转义：\" \& \$ 不触发下文
        if (c=="\"") { q="\""; i++; continue }
        if (c==sprintf("%c",39)) { q=sprintf("%c",39); i++; continue }
        if (c=="&") {
          if (substr(line,i+1,1)=="&") { i+=2; continue }   # && 合法分隔符
          print "BAD"; exit
        }
        if (c=="<" || c==">" || c=="`") { print "BAD"; exit }
        if (c=="$" && substr(line,i+1,1)=="(") { print "BAD"; exit }
        i++
      } else if (q=="\"") {
        if (c=="\\" && i+1<=n) { i+=2; continue }   # 双引号内 \ 转义字面（\" \` \$ \\）
        if (c=="\"") { q=""; i++; continue }
        if (c=="`") { print "BAD"; exit }            # 双引号内反引号 = 命令替换
        if (c=="$" && substr(line,i+1,1)=="(") { print "BAD"; exit }  # 双引号内 $() = 命令替换
        i++
      } else {  # 单引号：全部字面，读到单引号闭合（内里反斜杠不转义）
        if (c==q) { q="" }
        i++
      }
    }
  }' | grep -q BAD
}

command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# fail-closed 元字符防线（引号感知）：引号外的 &(非 &&)、<、>、`、$( 能在目标工具之外执行命令 / 写任意文件
# （后台执行 &、单/双输入输出重定向、命令替换、进程替换）。含任一即不放行。&& 是合法分隔符、N>&N 是 fd 重定向，二者豁免。
# URL / SQL 字面量里的这些字符（引号内）是数据不是注入，不再误伤。宁可多确认，不误放行。
if has_danger_metachars "$cmd"; then
  exit 0
fi

# 按 shell 分隔符（&& || ; |）拆段；剥离段首环境变量赋值前缀后，段首词必须统一为同一个工具
tool=""
same=1
while IFS= read -r seg; do
  seg=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)+//')
  [ -n "$seg" ] || continue
  first=${seg%%[[:space:]]*}
  if [ -z "$tool" ]; then
    tool="$first"
  elif [ "$tool" != "$first" ]; then
    same=0
    break
  fi
done < <(split_segments "$cmd")

if [ "$same" -eq 0 ] || [ -z "$tool" ]; then
  exit 0
fi

case "$tool" in
  playwright-cli)
    if has_quote_inner_semicolon "$cmd"; then
      exit 0
    fi
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"qa-powers: playwright-cli 命令自动放行"}}'
    ;;
  usql)
    if is_readonly_usql_query "$cmd"; then
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"qa-powers: 只读查询自动放行（不改数据）"}}'
    fi
    ;;
esac
exit 0
