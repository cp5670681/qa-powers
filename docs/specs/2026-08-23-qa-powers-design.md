# qa-powers 设计文档

日期：2026-08-23
状态：待审阅

## 概述

qa-powers 是一个 Claude Code 插件，让测试人员用 AI 完成 UI 自动化测试的完整闭环：**需求 → 用例 → 执行 → 沉淀 → 报告**。参考 obra/superpowers 的结构（skill 套件 + 子命令 + 交互式流程 + SessionStart hook 引导）。

核心诉求：

- 以 UI 自动化测试为主线：根据需求生成用例、跑用例、生成报告
- 用例可 AI 生成，也可人工提供（放指定目录，同一格式即插即用）
- 首次执行用裸 playwright-cli 命令驱动有头浏览器，边看边跑；跑完把稳定模式沉淀为 Playwright Test 脚本，回归时直接跑
- usql 承担数据三件套：数据验证、造数/清理、排查辅助
- 用例设计必须参考前端/后端仓库代码，重点覆盖需求分支的 diff 改动点
- 设计阶段充分交互确认，执行阶段自动
- 产出：Markdown 报告 + Playwright HTML 报告
- 环境配置集中在被测项目内配置文件

## 架构分层

```
┌─────────────────────────────────────────────┐
│ qa-powers skills（方法论层，纯提示词）        │
│  需求澄清 → 用例设计 → 执行 → 沉淀 → 报告     │
├──────────────┬──────────────┬───────────────┤
│ playwright-cli│   usql       │ git + 代码仓库 │
│ （浏览器执行） │（数据三件套） │（FE/BE 参考）  │
├──────────────┴──────────────┴───────────────┤
│ .qa-powers/ 测试资产目录（用例/脚本/报告/配置）│
└─────────────────────────────────────────────┘
```

关键决策：

- **纯 Skill 插件，无自研运行时代码**。playwright-cli（microsoft/playwright-cli）本身就是为 AI agent 设计的执行器：跨命令持久浏览器会话、每条命令后返回页面快照、`show` 仪表盘供人实时观看、`state-save/load` 沉淀登录态、tracing/video 取证。无需再写 driver。
- **不重复浏览器原语层**。playwright-cli 自带官方 skill（`playwright-cli install --skills`），qa-powers 的 skill 引用它，专注方法论。
- **回归走标准 Playwright Test**。沉淀脚本用 `npx playwright test` 执行，白拿 HTML 报告、trace 回放、重试机制。

## 子命令集

| 子命令 | 作用 | 触发方式 |
|---|---|---|
| `/qa-powers:init` | 初始化 `.qa-powers/` 目录 + 配置文件 | 手动 |
| `/qa-powers:design` | 需求 → 用例（交互式，含代码影响分析） | 手动或关键词 |
| `/qa-powers:run` | 执行用例（回归模式 / 首跑模式） | 手动或关键词 |
| `/qa-powers:report` | 汇总执行结果生成报告 | run 结束自动引导 |
| `using-qa-powers` | 入口元技能：识别测试意图，路由到对应阶段 | SessionStart hook 自动注入 |

## 核心数据流

```
需求(文本/Jira/Confluence) ──design──▶ 用例 md (.qa-powers/cases/)
                                          │
                              run ◀──────┘
                    ┌─── 有沉淀脚本 ──▶ npx playwright test ──▶ HTML 报告
                    └─── 无 ──▶ playwright-cli 边看边跑 + 命令日志
                                        │
                          run 结束引导沉淀：命令日志 ──▶ Playwright Test 脚本
                                        │
                              report ──▶ Markdown 报告 (.qa-powers/reports/)
```

## 目录结构与资产格式

被测项目内的 `.qa-powers/` 目录：

```
.qa-powers/
├── config.yaml              # 环境与仓库配置（唯一配置入口）
├── cases/                   # 用例库（AI 生成 + 人工提供，同一格式）
│   └── ORD-1234-checkout/
│       ├── case-01.md
│       ├── case-02.md
│       └── meta.yaml        # 需求来源、分支、覆盖的 diff 点
├── scripts/                 # 沉淀的 Playwright Test 脚本
│   └── ORD-1234-checkout.spec.ts
├── evidence/                # 执行取证（按 run 时间戳分目录）
│   └── 2026-08-23-1430/
│       ├── commands.log     # playwright-cli 命令日志（沉淀脚本的原料）
│       ├── screenshots/
│       └── traces/
└── reports/
    ├── 2026-08-23-1430.md
    └── html/
```

### config.yaml

敏感信息支持环境变量引用：

```yaml
env: test
base_url: https://test.example.com
auth:
  username: ${QAP_TEST_USER}
  password: ${QAP_TEST_PASS}
  state_file: .qa-powers/auth-state.json
repos:
  frontend:
    path: ~/rcc/web-app
    branch: feature/ORD-1234
    base: main
  backend:
    path: ~/rcc/api-server
    branch: feature/ORD-1234
    base: main
db:
  usql_args: "mysql://user:${QAP_DB_PASS}@host:3306/mydb"
```

### 用例格式

人机共用，关键是"预期结果"可判定：

```markdown
---
id: case-01
title: 正常下单流程
priority: P0
covers: [frontend:src/checkout/OrderForm.tsx, backend:OrderController.create]
requires_data: 已上架商品 x1（造数见 setup.sql）
---

## 前置
- 已登录（state_file 登录态）
- usql 执行 setup.sql 造数

## 步骤
1. 进入购物车，点击"去结算"
2. 填写收货地址（固定测试地址）
3. 提交订单

## 预期
- UI: 出现"下单成功"，订单号可见
- DB: orders 表新增一条记录，status=pending，金额与页面一致
```

约定：

1. 人工用例即插即用：往 `cases/` 放同格式 md（AI 可协助把随手文本规整成该格式），run 一视同仁
2. 沉淀有门槛：只有模式稳定、会反复回归的用例（登录、核心流程）才转 `.spec.ts`；探索性验证留证据不沉淀

## 各阶段流程

### init

1. 交互式收集：base_url、登录方式、FE/BE 仓库路径与分支、DB 连接
2. 生成 config.yaml + 目录骨架；校验 playwright-cli、usql、仓库路径可用
3. 引导首次登录并 `state-save` 沉淀登录态

### design（交互重点阶段）

1. 读需求：文本 / Jira key / Confluence 链接（atlassian MCP）
2. **代码影响分析（强制步骤，不可跳过）**：FE/BE 各仓库 `git diff base...branch`，产出改动点清单（页面/组件、接口、SQL、配置）
3. 逐条澄清（一次一个问题）：不明确的业务规则、验收标准、边界情况
4. 生成用例：正常流 + 每个 diff 改动点至少 1 条 + 边界/异常；每条标注 covers 对应改动点（可追溯）
5. 用户确认用例集 → 写入 cases/<模块>/

### run

**回归模式**（有对应 spec.ts）：直接 `npx playwright test <spec>`，读 HTML 报告结果。

**首跑模式**（无脚本）：

1. 按用例顺序执行；执行前 usql 前置造数
2. `playwright-cli -s=<模块名>` 专用会话，逐条命令执行，每步对照快照检查与预期一致性
3. 开 tracing；关键节点截图；命令追加写入 commands.log
4. 预期环节：UI 断言看快照，DB 断言用 usql 查库比对
5. 单条用例结束记录 pass/fail → 下一条（失败不中断整体）

### 失败处理（错误分级）

| 情况 | 动作 |
|---|---|
| 元素找不到/页面不符 | snapshot 重查，重试 1 次；仍失败则取证标记 fail，继续 |
| 疑似 bug | 取证（截图+trace+当步命令），结合 FE/BE 代码和 diff 定位初步原因 |
| 环境问题（登录失败/服务 500） | 停止 run，报告环境故障，不误判为用例失败 |
| DB 断言失败 | usql 查关联表辅助判断是前端展示问题还是数据问题 |

### run 收尾

1. 清理造数数据
2. 询问哪些用例沉淀 → commands.log + 页面经验转 `.spec.ts`（用例 id 写进 test.title 保持可追溯）
3. 引导进入 report

### report

Markdown 报告：通过率、每条失败用例的"步骤-预期-实际-证据链接-初步原因（关联 diff 改动点）"；回归模式附 HTML 报告路径。

## qa-powers 自身结构（插件仓库）

参考 superpowers 仓库布局：

```
qa-powers/                   # 本插件仓库
├── skills/
│   ├── using-qa-powers/SKILL.md
│   ├── init/SKILL.md
│   ├── design/SKILL.md
│   ├── run/SKILL.md
│   └── report/SKILL.md
├── hooks/
│   └── hooks.json           # SessionStart 注入 using-qa-powers
├── plugin.json              # Claude Code 插件清单
└── tests/                   # 示例被测项目（冒烟测试用）
    ├── web/                 # 简单 web 页面
    └── .qa-powers/          # 演示配置
```

## 测试策略

1. 按 superpowers `writing-skills` 流程编写 skill，每个 skill 附 dry-run 验证
2. tests/ 内置示例被测项目（简单 web 页面 + sqlite），走通 init→design→run→report 全流程作为冒烟测试
3. 真实测试环境首次实战验收

## 非目标（YAGNI）

- 不自研浏览器 driver / 运行时
- 不做测试用例管理平台、并行执行调度、CI 集成（后续按需再加）
- 不做回写 Jira / 自动建 bug 单（用户明确不需要）
- 不做 API/接口测试主线（UI 为主，接口仅作为排查辅助时观察 network requests）
