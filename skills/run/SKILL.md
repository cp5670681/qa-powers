---
name: run
description: 执行测试用例（guided-run）。逐条用例：usql 造数 → playwright-cli 按业务步骤驱动有头浏览器 → UI/DB 断言 → 清理 → 产出 result.yaml。用户说"跑用例"、"执行测试"时使用。
allowed-tools: Bash(playwright-cli:*), Bash(usql:*), Bash(mkdir:*), Read, Write, Edit, AskUserQuestion
---

# run：guided-run 执行用例

## 硬约束（违反即执行错误）

1. **业务意图固定，执行细节允许适配**：按 case 步骤执行；selector 可以修正（快照 ref 失效时按语义重新定位，如 getByRole 等价元素），但**禁止改变业务路径**（如绕过下单 UI 直接访问成功页）
2. **绝不 checkout 被测仓库**
3. 密码/连接串只从环境变量读

## 0. 准备

1. 读 `.qa-powers/config.yaml`
2. `run_id=$(date +%Y-%m-%d-%H%M)`；`mkdir -p .qa-powers/evidence/$run_id`
4. 加载登录态并开浏览器：`playwright-cli open <base_url>` → `playwright-cli state-load .qa-powers/auth-state.json` → `playwright-cli goto <base_url>`，确认已登录（未登录 → 整个 run BLOCKED，走环境故障流程）
5. `playwright-cli tracing-start`
6. 用户指定跑哪些 case（默认 cases/ 下全部，按 priority 降序）

## 1. 逐条 case 执行

对每条 case，在其证据目录 `evidence/$run_id/<case-id>/` 下工作（先 mkdir，并建 screenshots/）：

### a. 造数（有 data.setup 时）

```bash
usql "$QAP_DB_URL" -f <setup.sql 路径>
```

造数产生的 ID（如订单号/商品 ID）记入 commands.log 注释行。

### b. 按步骤执行

对 case 的每个步骤：
1. `playwright-cli snapshot` 获取页面结构
2. 按步骤语义操作（goto/click/fill/select/press...），找不到目标元素时重新 snapshot 按语义定位，**重试 1 次**
3. 每条执行的命令追加写入 commands.log，格式：`# <case-id> step N: <步骤摘要>` 换行 `<实际命令>`
4. 关键节点（提交前后、断言处）`playwright-cli screenshot --filename screenshots/step-NN.png`
5. 出现意外状态（弹窗/报错）→ snapshot 判断：可关闭的关闭后继续；疑似 bug → 截图取证、在日志标注、按用例预期判定 FAIL，继续下一条步骤或下一 case

### c. 断言（预期环节）

- UI 断言：snapshot 中查找预期文本/元素，记录实际值
- DB 断言（预期含 DB: 时）：

```bash
usql "$QAP_DB_URL" -c "SELECT ... FROM orders WHERE ..."
```

比对实际值与预期值，查询与结果追加进 commands.log。

### d. 清理（有 data.cleanup 时）

```bash
usql "$QAP_DB_URL" -f <cleanup.sql 路径>
```

cleanup 失败：在 case 级 result.yaml 的 cleanup 段记录，**不改变用例状态**，最后向用户告警残留数据。

### e. 写 case 级 result.yaml（每条 case 结束立即写）

```yaml
case: case-01
status: passed        # passed | failed | blocked | skipped
reason: ""            # blocked/skipped 必填：环境故障或跳过原因
steps_executed: 8
assertions:
  - type: ui          # ui | db
    expected: "出现下单成功"
    actual: "出现下单成功"
    status: passed
failure:              # 仅 failed 时
  step: 8
  evidence: screenshots/step-08.png
cleanup:              # 仅失败时填
  status: failed
  detail: "delete from orders where id=... 超时"
```

## 2. 状态判定规则

| 状态 | 判定 |
|---|---|
| passed | 所有断言通过 |
| failed | 任一断言未通过（UI 实际 ≠ 预期，或 DB 数据不符） |
| blocked | 环境故障：登录失败、DB 连不上、服务 5xx/超时。**不算用例失败** |
| skipped | 依赖的前置 case blocked、或用户指定跳过 |

**环境故障处理**：连续 2 条 case 因同类环境原因 blocked → 停止 run，剩余 case 全部标 blocked（reason 同），直接进入收尾。

## 3. 收尾

1. `playwright-cli tracing-stop`、`playwright-cli close`
2. 写 run 级 `evidence/$run_id/result.yaml`：

```yaml
run_id: 2026-08-23-1430
module: ORD-1234-checkout
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
