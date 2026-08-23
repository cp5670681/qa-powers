---
name: report
description: 生成测试报告。读取 .qa-powers/evidence/<run-id>/result.yaml（机器契约），汇总四态统计与失败详情，输出 Markdown 报告。用户说"生成报告"、"看看测试结果"时使用。
allowed-tools: Read, Write, Bash(ls:*), AskUserQuestion
---

# report：生成测试报告

## 1. 选 run

`ls .qa-powers/evidence/` 列出可选 run-id；用户没指定就用最新的一个。

## 2. 读取（只读 result.yaml，不解析日志/截图）

- run 级 `evidence/<run-id>/result.yaml`：用例列表与 summary
- 每条 case 的 `evidence/<run-id>/<case-id>/result.yaml`：断言详情、失败证据引用

## 3. 生成 `.qa-powers/reports/<run-id>.md`

结构（固定）：

```markdown
# 测试报告 <run-id>

模块：<module>　　时间：<生成时间>

## 总览

| 状态 | 数量 |
|---|---|
| 总数 | 2 |
| PASS | 1 |
| FAIL | 1 |
| BLOCKED | 0 |
| SKIPPED | 0 |

## 用例明细

| 用例 | 状态 | 失败原因 |
|---|---|---|
| case-01 正常下单流程 | ✅ PASS | |

case result.yaml 带 `account:` 时，用例名后附账号（如 `case-02 下单 [buyer]`）；多账号 run 建议在总览后加一节「账号覆盖」：每个账号跑了哪些 case、通过率。

## 失败详情（每条 FAIL 一节）

### case-02 库存扣减验证 ❌

- **步骤**: step 8（提交订单）
- **预期**: UI 出现"下单成功"
- **实际**: 出现"系统异常"
- **证据**: `evidence/<run-id>/case-02/screenshots/step-08.png`（tracing 见 run 会话）
- **覆盖改动点**: case result.yaml 的 covers（如 `backend:OrderController.create`）→ 初步判断方向：<结合预期/实际差异给一句话假设，如"提交接口报错，建议查后端日志与 OrderController.create" >

## BLOCKED 说明（有才写）

<case-id>: <reason>
```

## 4. 收尾

输出报告文件路径 + 一段话摘要（总数、通过率、最需要关注的失败）。提示：需要深入分析失败原因可继续对话排查（MVP 无独立 debug skill）。
