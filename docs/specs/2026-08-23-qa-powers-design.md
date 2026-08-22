# qa-powers 设计文档（MVP）

日期：2026-08-23（v4，收敛为 MVP）
状态：待审阅

## MVP 目标

跑通一条最小闭环：**需求 → 用例 → guided-run（playwright-cli + usql）→ 报告**。

**核心原则：AI 负责思考，工具负责执行，Evidence 负责证明。**

限定：1 个前端 repo + 1 个后端 repo + 1 个 DB；用例 AI 生成或人工提供，统一格式。

## 架构

```
qa-powers skills（方法论层，纯提示词，无自研运行时）
├── playwright-cli   浏览器执行（持久会话、快照、state-save 登录态）
├── usql             造数 / 数据验证 / 排查
└── git + FE/BE 代码  diff 影响分析
        ↓
.qa-powers/ 测试资产目录
```

确定性边界：guided-run 为 **AI-assisted**——按 case 步骤执行，业务意图固定、执行细节允许适配（selector 修正），**禁止修改业务路径**（如绕过 UI 直接访问结果页）。

## 子命令（MVP 仅 4 + 路由）

| 子命令 | 职责 |
|---|---|
| `/qa-powers:init` | 生成 config.yaml + 目录骨架 + 依赖校验（playwright-cli/usql/仓库/DB/登录态） |
| `/qa-powers:design` | 需求（文本/Jira/Confluence）→ 交互澄清 → 结合 diff 影响分析 → 生成用例 |
| `/qa-powers:run` | guided-run：逐条 case 造数 → playwright-cli 执行 → 断言 → 清理 → result.yaml |
| `/qa-powers:report` | 读 result.yaml → Markdown 报告 |
| `using-qa-powers` | 薄路由：识别意图，加载对应 skill（SessionStart 只注入一句话） |

## 目录结构（被测项目内）

```
.qa-powers/
├── config.yaml
├── cases/<模块>/
│   ├── case-01.md       # 业务用例（定义+步骤+预期，不含执行细节）
│   ├── setup.sql        # 可选
│   └── cleanup.sql      # 可选
├── evidence/<run-id>/
│   ├── result.yaml      # run 级结果（机器契约，report 只读它）
│   └── case-01/
│       ├── result.yaml  # 状态 + 预期/实际 + 证据引用
│       ├── commands.log
│       └── screenshots/
└── reports/<run-id>.md
```

## config.yaml

```yaml
env: test
base_url: https://test.example.com
auth:
  username_env: QAP_TEST_USER
  password_env: QAP_TEST_PASS
  state_file: .qa-powers/auth-state.json
repos:
  frontend: { path: ~/rcc/web-app, base: main }
  backend:  { path: ~/rcc/api-server, base: main }
db:
  url_env: QAP_DB_URL        # 全量连接串放环境变量
```

规则：**绝不自动 checkout 分支**，代码分析只读工作区现状（`git branch --show-current` + `git diff <base>...HEAD`）。

## 用例格式

```markdown
---
id: case-01
title: 正常下单流程
priority: P0
requirement: ORD-1234
covers: [frontend:src/checkout/OrderForm.tsx, backend:OrderController.create]
data: { setup: setup.sql, cleanup: cleanup.sql }
---

## 前置
- 已登录；存在 1 个已上架测试商品

## 步骤
1. 进入购物车，点击"去结算"
2. 填写收货地址（固定测试地址）
3. 提交订单

## 预期
- UI: 出现"下单成功"，订单号可见
- DB: orders 新增一条，status=pending，金额与页面一致
```

约定：case 之间数据独立、互不依赖（造数 → 记录 ID → 断言 → 按 ID 清理）；cleanup 失败记录告警但不影响 case 结果。

## run 流程（guided-run）

1. 逐条 case：usql 造数并记录 ID → `playwright-cli -s=<模块>` 会话按步骤执行 → 每步对照快照与预期 → UI 断言看快照、DB 断言 usql 查库 → cleanup
2. tracing + 关键节点截图，命令写入 commands.log
3. 状态四态：**PASS / FAIL / BLOCKED（环境故障，附 reason）/ SKIPPED**；用例失败不中断整体，环境故障停止 run 并把余下标 BLOCKED
4. 结束产出 result.yaml，引导 report

## report

Markdown：通过率（四态统计）+ 失败用例的"步骤-预期-实际-证据链接-初步原因（关联 covers 改动点）"。

## 插件仓库结构

```
qa-powers/
├── skills/{using-qa-powers,init,design,run,report}/SKILL.md
├── hooks/hooks.json        # SessionStart 一句话提示（lazy loading）
├── plugin.json
└── tests/                  # 示例被测项目（web 页面 + sqlite）冒烟测试
```

## 测试策略

1. 按 superpowers `writing-skills` 流程编写，每个 skill 附 dry-run 验证
2. tests/ 示例项目走通 init→design→run→report 冒烟
3. 真实项目实战验收

## 非目标（MVP 不做）

- 不自研浏览器 driver / 运行时
- 不做 CI 集成、回写 Jira、自动建 bug 单
- 不做 API 测试主线
- 不自动 checkout 分支

## 后续演进（按需启用，MVP 不实现）

- explore（autonomous 探索）/ stabilize（稳定 locator 沉淀为 Playwright Test，解锁 scripted-run 回归）/ debug（UI+DB+Code+Trace 综合分析）
- design 变化检测（旧 meta + 新 diff → 用例增删改建议）
- 三层追踪与 coverage 报告（Requirement/Diff/Case）
- BLOCKED reason code 分类统计、manifest.yaml schema 版本、case 版本管理、stability score、人工接管点（Pause/Take control）
