---
name: run
description: 执行测试用例（guided-run）。逐条用例：usql 造数 → playwright-cli 按业务步骤驱动有头浏览器 → 三层断言（UI/网络/DB）→ 清理 → 产出 result.yaml。用户说"跑用例"、"执行测试"、"继续测试"时使用。
allowed-tools: Bash(playwright-cli:*), Bash(usql:*), Bash(mkdir:*), Read, Grep, Glob, Write, Edit, AskUserQuestion
---

# run：guided-run 执行用例

## 硬约束（违反即执行错误）

1. **业务意图固定，执行细节允许适配**：按 case 步骤执行；selector 可以修正（快照 ref 失效时按语义重新定位，如 getByRole 等价元素），但**禁止改变业务路径**（如绕过下单 UI 直接访问成功页）
2. **绝不 checkout 被测仓库**
3. 密码/连接串只从环境变量读
4. **页面 URL 禁止猜测**：从 config `repos.frontend.path` 的路由代码推导（router 配置 / 页面组件的 route 定义），必要时前后端代码都可参考（如定位元素结构、确认接口行为），但只读，不修改
5. **并发模式附加约束**：并发执行中禁止 `state-save`（多会话共读登录态文件，写会互相踩）；DB 写操作（造数/清理）只允许出现在声明了 `depends_on` 的用例中，无依赖用例只做只读断言；每个 subagent 只能操作自己的 `-s=qap-<case-id>` 会话

## 0. 准备

1. 读 `.qa-powers/config.yaml`
2. `run_id=$(date +%Y-%m-%d-%H%M)`；`mkdir -p .qa-powers/evidence/$run_id`。**断点续跑**：若最新 run（按 evidence 目录 mtime 取最新）下存在未完成 case（case 目录无 result.yaml），先问用户「继续该 run（复用其 run_id 与 evidence 目录，跳过已有终态 result.yaml 的 case，从第一个未完成的接着跑）还是新开 run」
3. **建立路由映射**：用 Grep/Glob 在前端仓库路由配置中查目标页面的 route 定义，得到「页面名 → URL」。用例步骤涉及导航（goto）时一律使用该映射；映射中找不到时先查前端代码确认，仍不确定才问用户，**禁止凭记忆或猜测拼 URL**
4. **执行模式选择（AskUserQuestion）**：
   - 顺序 / 并发。并发时再问并发上限（默认 3，可选 2/3/4——每个 worker 是一个独立浏览器实例）
   - **有头 / 无头（两种模式都问）**：推荐默认**无头**（证据靠截图/快照，无头更快更稳、多开不抢资源）；有头用于演示或排查单条 case 时选
   - 选择记入 commands.log 与 run 级 result.yaml（`mode: sequential|parallel`、`headed: true|false`、`workers: N`）
5. 加载登录态并开浏览器（顺序模式）：`playwright-cli open <base_url> --browser <channel> [--headed]` → `playwright-cli state-load <auth.state_file 或 auth.default 账号的 state_file>` → `playwright-cli goto <base_url>`，确认已登录（未登录 → 整个 run BLOCKED，走环境故障流程）
6. `playwright-cli tracing-start`，**并确认输出无 Error**（如 `Tracing is not started` 类报错要在开跑前处理）。注意：关键命令不要用管道截取输出（`| tail`会吞掉报错），必须看到完整成功输出再继续；tracing 确实起不来时降级为仅截图取证，在 commands.log 标注
7. 用户指定跑哪些 case（默认 cases/ 下全部，按 priority 降序）

## 1. 逐条 case 执行（顺序模式）

对每条 case，在其证据目录 `evidence/$run_id/<case-id>/` 下工作（先 mkdir，并建 screenshots/）。断点续跑时，case 目录已有终态 result.yaml 的直接跳过，在 commands.log 注明 resumed-skip。

**多账号切换**：case frontmatter 声明了 `account:` 且与当前已加载账号不同时，先切换：`playwright-cli state-load <该账号的 state_file>` → `playwright-cli goto <base_url>` → snapshot 确认登录身份已切换（页面上能看到当前用户标识时核对）。切换失败/登录态失效 → 该 case 标 blocked（reason 注明账号与失效情况），并提示用户对该账号重跑 `qa-powers:init` 步骤 5 重新沉淀登录态。切换动作记入 commands.log。

### a. 造数（有 data.setup 时）

```bash
usql "$QAP_DB_URL" -f <setup.sql 路径>
```

造数产生的 ID（如订单号/商品 ID）记入 commands.log 注释行。INSERT 报 NOT NULL/约束错误时，先一次查全该表约束再改脚本，不要逐列试错：

```sql
SELECT column_name, is_nullable, column_default FROM information_schema.columns WHERE table_name='<表名>';
```

### b. 按步骤执行

对 case 的每个步骤：
1. `playwright-cli snapshot` 获取页面结构
2. 按步骤语义操作（goto/click/fill/select/press...），找不到目标元素时重新 snapshot 按语义定位，**重试 1 次**。语义等价元素找到但文案与用例引用不一致（如按钮名变了）→ 可用该元素完成操作以验证后续行为，但必须补一条 ui 断言：expected=用例引用的文案、actual=页面实际文案、status=failed——文案漂移是 UI 回归，不属于可适配的 selector 差异
3. 每条执行的命令追加写入 commands.log，格式：`# <case-id> step N: <步骤摘要>` 换行 `<实际命令>`
4. 关键节点（提交前后、断言处）`playwright-cli screenshot --filename screenshots/step-NN.png`
5. 出现意外状态（弹窗/报错）→ snapshot 判断：可关闭的关闭后继续；疑似 bug → 截图取证、在日志标注、按用例预期判定 FAIL，继续下一条步骤或下一 case

### c. 断言（预期环节）

三层验证，可信度递增，**结论以下层为准**（快照会骗人：异步未返回、缓存都可能让快照失真）：

1. **UI**：snapshot 中查找预期文本/元素，记录实际值
2. **网络**（凡涉及提交/接口交互的断言必查；纯静态展示可略）：`playwright-cli requests` + `response-body <n>` ——请求是否发出、参数、真实返回（注意 HTTP 2xx ≠ 成功，错误响应也可能 200/201，必看响应体的 message/数据）
3. **DB**（预期含 DB: 时）：`usql "$QAP_DB_URL" -c "SELECT ... FROM orders WHERE ..."` ——落库字段与副作用

快照结论与网络/DB 冲突时以下层为准；只凭快照判 PASS 前，先确认不需要下层佐证。比对实际值与预期值，查询与结果追加进 commands.log。

- **瞬态元素断言（toast/一闪而过的提示）**：snapshot 往往来不及抓取，按以下优先级降级，并在 result.yaml 的 actual 中注明断言方式：
  1. 操作后立即 snapshot / screenshot（1 次重试）
  2. **行为断言**：预期"被拦截"时，验证「关键网络请求未发出」（requests 中无对应 POST）+「页面状态未变」（弹窗未关/数据未创建）
  3. console 日志中查找前端报错/业务日志
- **量化预期先取真值再比对**：排序/Top-N/计数/默认值类预期，先按实现逻辑（改动代码中的查询/排序）在库里跑一遍得出期望值，再与页面实际比对——不以页面展示反推预期。查库所得与用例声明的需求口径冲突（如实现按 updated_at 排序、需求要求 created_at）时，**以用例预期为准判 FAIL 并备注「需求偏差」**，不拿实现现状当预期
- **校验类用例「意外成功」**：预期"被拦截/报错"却通过了 → 先查 DB 确认是否真的写入。未写入则按断言正常判定；已写入即误创建：立即 usql 按记录 ID 清理，在 result.yaml 的 cleanup 段如实注明「执行中误创建并已清理」，然后复测该用例

### d. 清理（有 data.cleanup 时）

```bash
usql "$QAP_DB_URL" -f <cleanup.sql 路径>
```

cleanup 失败：在 case 级 result.yaml 的 cleanup 段记录，**不改变用例状态**，最后向用户告警残留数据。

### e. 写 case 级 result.yaml（每条 case 结束立即写）

```yaml
case: case-01
title: 正常下单流程     # 取自 case frontmatter
account: admin          # 取自 case frontmatter（多账号时记录实际使用的账号；单账号省略）
covers:                 # 取自 case frontmatter，供 report 展示覆盖改动点
  - frontend:src/checkout/OrderForm.tsx
  - backend:OrderController.create
status: passed        # passed | failed | blocked | skipped
reason: ""            # blocked/skipped 必填：环境故障或跳过原因
steps_executed: 8
assertions:
  - type: ui          # ui | net | db（三层断言，见 §1c）
    expected: "页面出现「下单成功」"
    actual: "页面出现「下单成功」"
    status: passed
  - type: net
    expected: "POST /api/orders 响应体 result=success"
    actual: "POST /api/orders 响应体 result=success"
    status: passed
  - type: db
    expected: "orders 表新增 1 行，status=paid"
    actual: "orders 表新增 1 行，status=paid"
    status: passed
failure:              # 仅 failed 时
  step: 8
  step_desc: 提交订单   # 失败步骤的语义摘要（取自 case 步骤，供 report 展示）
  evidence: screenshots/step-08.png
cleanup:              # cleanup 失败或执行中误创建并已清理时填
  status: failed
  detail: "delete from orders where id=... 超时"
```

## 陷阱与对策（实战总结，执行 case 时对照）

| 陷阱 | 现象 | 对策 |
|---|---|---|
| HTTP 2xx ≠ 成功 | 错误响应也返回 200/201 | 断言以 response-body 为准，不看状态码（§1c 第 2 层） |
| 异步未返回就断言 | 下拉"暂无数据"，稍后又出现了 | 先查 requests/response-body 再下结论 |
| 两次结果不一致 | 同一步骤重跑结果不同 | 大概率前端异步竞态：换输入方式（一次性完整输入替代逐键输入）复测，区分竞态与后端行为 |
| 组件状态残留 | 上一条 case 的选中项/表单值还在 | 每条 case 开始先导航到目标页重置状态，确认初始状态符合前置再操作 |
| hash 路由不重载 | URL 变了内容还是旧页 | goto 后快照确认，必要时 reload 再断言 |
| ref 过期 | `Ref xxx not found` | 重新 snapshot 按语义定位（§1b 重试 1 次） |
| 误创建数据 | 校验用例意外写入 | 见 §1c「意外成功」：查库 → 清理 → 注明 → 复测 |

## 2. 并发执行（依赖图调度，参考 superpowers subagent-driven-development 模式）

选并发模式时，主会话只做 **orchestrator**（分组/派发/收集），不亲自操作浏览器：

### a. 建依赖图

- 每条入选 case 用 TaskCreate 建任务；case frontmatter 的 `depends_on` 映射为 TaskUpdate 的 `blockedBy`
- 无 `depends_on` 的用例之间不建依赖（即全部同时可跑）
- 依赖声明的用例若前置未入选/已失败 → 该 case 标 skipped（reason 注明前置缺失）

### b. 派发循环

- 维持在跑 subagent 数 ≤ 用户选的并发上限；每有空位，从「pending 且无 blockedBy」的用例中按 priority 派发
- 每条 case spawn 一个 general-purpose subagent（一次消息里可同时派多个），prompt **必须自包含**：
  1. 用例全文 + 测试数据（具体 ID/账号等，subagent 没有主会话上下文）
  2. base_url、登录态文件路径、浏览器 channel/headless 选择
  3. **会话隔离**：所有 playwright-cli 命令一律带 `-s=qap-<case-id>`，禁止操作其他会话
  4. 执行协议：snapshot→按语义操作→重试 1 次；三层断言（快照/网络/查库）结论以下层为准；瞬态断言降级；校验用例意外成功先查库；截图与 commands.log 写入自己的 evidence 目录；结束幂等关闭自己的会话（close 报 not open 可忽略）
  5. 产出：按 case 级 result.yaml 模板写入 `evidence/<run-id>/<case-id>/result.yaml`，并在返回消息里报告一行结果摘要
  6. 禁止：state-save、checkout 被测仓库、改用例业务路径
- subagent 返回后：校验 result.yaml 存在且结构合法（缺失/畸形 → blocked，reason 注明 subagent 未产出有效结果）；TaskUpdate 完成，释放后继依赖

### c. 故障与收束

- **2 个在跑用例因同类环境原因 blocked → 停止派发新 subagent**，未开始的全部标 blocked（reason 同），等在跑的收尾
- 全部结束后进入收尾（§3），run 级 result.yaml 增加 `mode: parallel`、`workers: N`

## 3. 状态判定规则

| 状态 | 判定 |
|---|---|
| passed | 所有断言通过 |
| failed | 任一断言未通过（UI 实际 ≠ 预期，或 DB 数据不符） |
| blocked | 环境故障：登录失败、DB 连不上、服务 5xx/超时。**不算用例失败** |
| skipped | 用户指定跳过 |

**环境故障处理**：连续 2 条 case 因同类环境原因 blocked → 停止 run，剩余 case 全部标 blocked（reason 同），直接进入收尾。

## 4. 收尾

1. `playwright-cli tracing-stop`、`playwright-cli close`
2. 写 run 级 `evidence/$run_id/result.yaml`：

```yaml
run_id: 2026-08-23-1430
module: ORD-1234-checkout
mode: parallel        # sequential | parallel
workers: 3            # 并发模式时有效
cases:
  - case: case-01
    status: passed
    reason: ""
summary:
  total: 2
  passed: 1
  failed: 1
  blocked: 0
  skipped: 0
```

3. 向用户报告一句话结果（`2 cases: 1 passed, 1 failed`），cleanup 残留告警，提示运行 `qa-powers:report` 生成报告

断点续跑收尾时：run 级 result.yaml 的 summary 汇总该 run **全部** case（含 resumed-skip 的，状态沿用其已有 result.yaml，不丢历史）
