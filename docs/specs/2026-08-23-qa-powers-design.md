# qa-powers 设计文档

日期：2026-08-23（v2，吸收评审意见）
状态：待审阅

## 概述

qa-powers 是一个 Claude Code 插件，让测试人员用 AI 完成 UI 自动化测试的完整闭环：**需求 → 用例 → 执行/探索 → 沉淀 → 报告**。参考 obra/superpowers 的结构（skill 套件 + 子命令 + 交互式流程 + SessionStart hook 引导）。

**核心原则：AI 负责思考，工具负责执行，Evidence 负责证明。**

```
              AI
        思考 / 决策 / 分析
                │
       ┌────────┼────────┐
       ↓        ↓        ↓
  playwright   usql     git
       │        │        │
       └────────┼────────┘
                ↓
             Evidence
                ↓
             Result
                ↓
             Report
```

核心诉求：

- 以 UI 自动化测试为主线：根据需求生成用例、跑用例、生成报告
- 用例可 AI 生成，也可人工提供（放指定目录，同一格式即插即用）
- 首次执行用 playwright-cli 驱动有头浏览器，边看边跑；稳定模式经 **stabilize** 沉淀为 Playwright Test 脚本，回归时直接跑
- usql 承担数据三件套：数据验证、造数/清理、排查辅助
- 用例设计必须参考前端/后端仓库代码，重点覆盖需求分支的 diff 改动点
- 设计阶段充分交互确认，执行阶段自动且**确定性**
- 产出：Markdown 报告（含三层 coverage）+ Playwright HTML 报告
- 环境配置集中在被测项目内配置文件

## 架构分层

```
┌─────────────────────────────────────────────┐
│ qa-powers skills（方法论层，纯提示词）        │
│  需求澄清 → 用例设计 → 执行/探索 → 沉淀 → 报告 │
├──────────────┬──────────────┬───────────────┤
│ playwright-cli│   usql       │ git + 代码仓库 │
│ （浏览器执行） │（数据三件套） │（FE/BE 参考）  │
├──────────────┴──────────────┴───────────────┤
│ .qa-powers/ 测试资产目录（用例/脚本/报告/配置）│
└─────────────────────────────────────────────┘
```

关键决策：

- **纯 Skill 插件，无自研运行时代码**。playwright-cli（microsoft/playwright-cli）本身就是为 AI agent 设计的执行器：跨命令持久浏览器会话、每条命令后返回页面快照、`show` 仪表盘供人实时观看、`state-save/load` 沉淀登录态、tracing/video 取证。
- **不重复浏览器原语层**。playwright-cli 自带官方 skill，qa-powers 的 skill 引用它，专注方法论。
- **run = deterministic，explore = autonomous**。run 验证已知答案，执行方式必须确定，禁止 AI 临场"优化"路径（否则回归不稳定）；explore 寻找未知问题，允许 AI 自由发挥。这条边界写进对应 skill 的硬约束。
- **回归走标准 Playwright Test**。沉淀脚本用 `npx playwright test` 执行，白拿 HTML 报告、trace 回放、重试机制。
- **lazy loading**。SessionStart hook 只注入一句话路由提示（"qa-powers available, 需要测试时读 using-qa-powers"），各阶段 skill 按需加载，不预先塞入上下文。

## 子命令集（v2 调整后）

```
init
 ↓
design
 ↓
┌──────────────┐
│              │
explore       run
│              │
│              ↓
│          stabilize
│              │
└───────→ debug
               ↓
             report
```

| 子命令 | 回答的问题 | 触发方式 |
|---|---|---|
| `/qa-powers:init` | 环境和配置就绪了吗？ | 手动 |
| `/qa-powers:doctor` | 哪个环节坏了？ | 手动 |
| `/qa-powers:design` | 我应该测什么？ | 手动或关键词 |
| `/qa-powers:explore` | 系统里有没有我没想到的问题？ | 手动或关键词 |
| `/qa-powers:run` | 已有用例现在是否通过？ | 手动或关键词 |
| `/qa-powers:stabilize` | 这个首跑/探索能不能变成可靠自动化？ | run/explore 结束引导 |
| `/qa-powers:debug` | 为什么失败？ | run 失败引导 |
| `/qa-powers:report` | 最终结果是什么？ | run 结束自动引导 |
| `using-qa-powers` | 意图识别 → 路由到对应 skill | SessionStart 一句话提示 |

**using-qa-powers 是薄路由**：只做意图识别 + 加载对应 skill，不做实际工作，控制 token 消耗。

## 核心数据流

```
需求(文本/Jira/Confluence) ──design──▶ 用例 md (.qa-powers/cases/)
                                          │
                     ┌── explore ◀───────┤（自由探索，产出发现+疑似bug）
                     │                    │
                     └── run ◀───────────┘
                          │
              ┌─── 有沉淀脚本 ──▶ npx playwright test ──▶ HTML 报告
              └─── 无 ──▶ playwright-cli 逐步驱动 + execution.md/commands.log
                                        │
                          stabilize（人工确认）──▶ .spec.ts
                                        │
                          debug（失败时）──▶ 定位分析
                                        │
                          report ◀── result.yaml ──▶ Markdown 报告 + coverage
```

## 三层追踪（traceability）

```
Requirement (R) ──▶ Diff 改动点 (D) ──▶ Test Case (C)
```

- design 阶段产出需求点清单（R1/R2/...）和 diff 改动点清单（D1/D2/...）
- 每条用例 front-matter 标注两个维度的覆盖：

```yaml
requirement: ORD-1234
covers:
  requirements: [R1, R3]
  changes:
    - frontend:src/checkout/OrderForm.tsx
    - backend:OrderController.create
```

- report 阶段据此输出三种 coverage：

```
Requirement Coverage: 100%
  R1 ✓ (C01, C02)   R2 ✓ (C03)   R3 ✗ (C04)

Diff Coverage: 87%
  frontend/OrderForm.tsx    ✓
  OrderController#create    ✓
  InventoryService          ✗ 未覆盖

Test Cases: 18 | PASS: 14 | FAIL: 2 | BLOCKED: 1 | SKIPPED: 1
```

## 目录结构与资产格式

被测项目内的 `.qa-powers/` 目录：

```
.qa-powers/
├── config.yaml              # 环境与仓库配置（唯一配置入口）
├── cases/                   # 用例库（AI 生成 + 人工提供，同一格式）
│   └── ORD-1234-checkout/
│       ├── case-01.md       # 纯业务用例（定义+步骤+预期，不含执行细节）
│       ├── setup.sql        # 可选：造数脚本
│       ├── cleanup.sql      # 可选：清理脚本
│       └── meta.yaml        # 需求点清单 R*、diff 改动点清单 D*
├── scripts/                 # stabilize 沉淀的 Playwright Test 脚本
│   └── ORD-1234-checkout.spec.ts
├── evidence/                # 执行取证（按 run 时间戳分目录，gitignore）
│   └── 2026-08-23-1430/
│       ├── result.yaml      # 本次 run 的结构化结果（见下）
│       └── case-01/
│           ├── execution.md # 实际执行计划：做了什么、为什么、偏差在哪
│           ├── commands.log # playwright-cli / usql 命令日志
│           ├── result.yaml  # 单用例结果（状态+预期/实际+证据引用）
│           ├── screenshots/
│           ├── traces/
│           ├── network/
│           └── db/          # DB 断言时的查询与结果
└── reports/
    ├── 2026-08-23-1430.md
    └── html/
```

### config.yaml

敏感信息一律走环境变量，skill 不理解密码拼接：

```yaml
env: test
base_url: https://test.example.com
auth:
  username: ${QAP_TEST_USER}
  password: ${QAP_TEST_PASS}
  state_file: .qa-powers/auth-state.json
repos:                        # 只声明路径和基线，不声明 branch
  frontend:
    path: ~/rcc/web-app
    base: main
  backend:
    path: ~/rcc/api-server
    base: main
db:
  driver: mysql
  url_env: QAP_DB_URL         # QAP_DB_URL=mysql://user:pass@host:3306/db
```

**qa-powers 绝不 checkout 分支**。代码分析时读工作区现状：`git branch --show-current` + `git diff <base>...HEAD`，由用户自己管理分支和未提交修改。

### 用例与执行分离

用例 md 只描述业务事实（目标、前置、步骤、预期），**不包含执行细节**（state-load、会话名、重试策略等）。执行时 AI 动态生成 execution plan，记录在 evidence 的 `execution.md`——实际做了什么、为什么这么执行、哪里发生偏差。业务用例不被执行细节污染，后续 debug 直接读结构化 execution.md。

```markdown
---
id: case-01
title: 正常下单流程
priority: P0
requirement: ORD-1234
covers:
  requirements: [R1]
  changes: [frontend:src/checkout/OrderForm.tsx, backend:OrderController.create]
data:
  setup: setup.sql
  cleanup: cleanup.sql
  isolation: case
---

## 前置
- 已登录（auth state）
- 存在 1 个已上架测试商品

## 步骤
1. 进入购物车，点击"去结算"
2. 填写收货地址（固定测试地址）
3. 提交订单

## 预期
- UI: 出现"下单成功"，订单号可见
- DB: orders 新增一条，status=pending，金额与页面一致
```

### 测试数据生命周期

每条 case 默认**独立数据生命周期**，case 之间不共享、不依赖：

```
setup（usql 造数）→ snapshot/记录生成的 ID → test → assert → cleanup
```

- `isolation: case` 为默认值；确需跨 case 共享时显式声明 `isolation: suite` 并在 meta.yaml 说明
- 造数生成的 ID 记录进 execution.md，cleanup 按 ID 精确清理，避免残留污染后续 case
- cleanup 失败要记录并报警，不能静默

### 用例状态（四态）

| 状态 | 含义 |
|---|---|
| PASS | 预期达成 |
| FAIL | 预期未达成（疑似 bug 或用例错误） |
| BLOCKED | 环境故障（登录失败/DB 连不上/服务 500），不算 FAIL |
| SKIPPED | 前置 case 失败导致跳过，或用户指定跳过 |

### run 级 result.yaml

每次 run 产出结构化结果，report 直接消费，无需重新理解日志：

```yaml
run_id: 2026-08-23-1430
status: failed
cases:
  - id: case-01
    status: passed
  - id: case-02
    status: failed
    reason: assertion_failed
    evidence: case-02/result.yaml
  - id: case-03
    status: blocked
    reason: environment
summary:
  total: 3
  passed: 1
  failed: 1
  blocked: 1
  skipped: 0
```

case 级 result.yaml 额外含预期/实际值与证据引用（screenshot/trace/db/command 行号），debug 时直接读。

## 各阶段流程

### init

1. 交互式收集：base_url、登录方式、FE/BE 仓库路径与基线分支、DB 连接（写入环境变量指引）
2. 生成 config.yaml + 目录骨架；调 doctor 逐项校验
3. 引导首次登录并 `state-save` 沉淀登录态

### doctor

逐项检查并给出修复指引：

```
✓ Node.js 24    ✓ playwright-cli    ✓ usql
✓ frontend repo ~/rcc/web-app (main)
✓ backend repo  ~/rcc/api-server (feature/ORD-1234)
✓ Database connection
✗ Login state (expired)  → 建议: /qa-powers:init --auth
✗ Playwright browser 未安装 → 建议: playwright-cli install-browser
```

### design（交互重点阶段）

1. 读需求：文本 / Jira key / Confluence 链接（atlassian MCP），拆出需求点 R1/R2/...
2. **代码影响分析（强制步骤）**：各仓库 `git diff <base>...HEAD`，产出改动点清单 D1/D2/...（页面/组件、接口、SQL、配置），写入 meta.yaml
3. 逐条澄清（一次一个问题）：不明确的业务规则、验收标准、边界情况
4. 生成用例：正常流 + 每个 D 至少 1 条 + 边界/异常；标注 covers（R + D 双维度）
5. 用户确认用例集 → 写入 cases/<模块>/

### run（deterministic）

- **回归模式**（有对应 spec.ts）：直接 `npx playwright test <spec>`，读 HTML 报告结果
- **首跑模式**（无脚本）：
  1. 逐条 case：usql 前置造数并记录 ID → `playwright-cli -s=<模块>` 会话执行 → 预期环节 UI 断言看快照、DB 断言 usql 查库比对 → cleanup
  2. 每步对照快照检查与预期一致性；开 tracing；关键节点截图；命令追加写入 commands.log
  3. 生成 execution.md（执行计划 + 偏差记录）
  4. 失败/阻塞按状态分级记录，失败不中断整体（环境故障除外——停止 run，全部未跑 case 标 BLOCKED）
- run 结束产出 result.yaml，引导进入 report / stabilize / debug

### explore（autonomous）

与 run 严格区分：AI 像测试人员一样自由探索系统，寻找未预期的问题（边界输入、缺失校验、状态不一致），结合 diff 改动点重点试探。产出"发现清单"（疑似 bug + 复现步骤 + 截图），不产出 pass/fail。有价值的探索路径可经 stabilize 沉淀。

### stabilize（沉淀，人工确认）

```
首跑/探索的 commands.log + 页面快照经验
  ↓ AI 分析每个操作目标元素的语义
  ↓ 生成稳定 locator（getByRole/getByText，禁止脆弱的 nth-child 链）
  ↓ 生成 Playwright Test 脚本（含 DB 断言步骤，test.title 带用例 id）
  ↓ 自动跑一次验证 PASS
  ↓ 人工确认后保存到 scripts/
```

预览确认（Generate / Edit / Skip）：

```
case-01: 12 steps, 8 stable locators, 2 DB assertions
[Y] Generate  [E] Edit  [N] Skip
```

沉淀有门槛：只有模式稳定、会反复回归的用例才转 `.spec.ts`；探索性验证留证据不沉淀。

### debug（失败分析）

读取 case 级 result.yaml + execution.md + 证据（截图/trace/网络/DB 记录），结合 FE/BE 代码与 diff 定位：前端展示问题 / 后端数据问题 / 环境问题 / 用例本身错误。产出初步原因分析（关联 diff 改动点），写入报告。

### report

Markdown 报告：四态统计 + 三层 coverage（Requirement/Diff/Case）+ 每条失败用例的"步骤-预期-实际-证据链接-初步原因"；回归模式附 HTML 报告路径。

## qa-powers 自身结构（插件仓库）

```
qa-powers/
├── skills/
│   ├── using-qa-powers/SKILL.md   # 薄路由
│   ├── init/SKILL.md
│   ├── doctor/SKILL.md
│   ├── design/SKILL.md
│   ├── explore/SKILL.md
│   ├── run/SKILL.md
│   ├── stabilize/SKILL.md
│   ├── debug/SKILL.md
│   └── report/SKILL.md
├── hooks/
│   └── hooks.json                 # SessionStart 仅一句话提示（lazy loading）
├── plugin.json
└── tests/                         # 示例被测项目（冒烟测试用）
    ├── web/
    └── .qa-powers/
```

## 版本规划

| 版本 | 内容 |
|---|---|
| V0.1 | init + doctor + design + run（首跑/回归）+ report，支持 playwright-cli + usql |
| V0.2 | + explore |
| V0.3 | + stabilize（playwright-cli → Playwright Test，稳定 locator 生成） |
| V0.4 | + debug（UI + DB + Code + Git diff + Trace 自动分析） |

## 测试策略

1. 按 superpowers `writing-skills` 流程编写 skill，每个 skill 附 dry-run 验证
2. tests/ 内置示例被测项目（简单 web 页面 + sqlite），走通 init→design→run→report 全流程作为冒烟测试
3. 真实测试环境首次实战验收

## 非目标（YAGNI）

- 不自研浏览器 driver / 运行时
- 不做测试用例管理平台、并行执行调度、CI 集成（后续按需再加）
- 不做回写 Jira / 自动建 bug 单
- 不做 API/接口测试主线（UI 为主，接口仅作排查辅助）
- 不自动 checkout/切换被测仓库分支
