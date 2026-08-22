# qa-powers MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 qa-powers MVP——一个 Claude Code 插件，跑通"需求 → 用例 → guided-run（playwright-cli + usql）→ 报告"最小闭环。

**Architecture:** 纯提示词插件（无自研运行时代码）。5 个 skill（using-qa-powers 薄路由 + init/design/run/report）+ SessionStart 一句话 hook。执行层复用 playwright-cli（持久浏览器会话）与 usql（造数/验证）。测试资产落在被测项目 `.qa-powers/` 目录，result.yaml 作为 skill 间机器契约。

**Tech Stack:** Claude Code Plugin（skills + hooks）、playwright-cli、usql、git、Node（仅 demo 被测项目用）。

**Spec:** `docs/specs/2026-08-23-qa-powers-design.md`

## Global Constraints

- 纯提示词插件：不写任何自研运行时代码（demo 被测项目除外）
- skill 命名空间：插件名 `qa-powers`，skill 调用形式 `qa-powers:init` 等
- 绝不自动 checkout 被测仓库分支；代码分析只读工作区现状（`git branch --show-current` + `git diff <base>...HEAD`）
- guided-run 确定性边界：业务意图固定、执行细节允许适配（selector 修正），禁止修改业务路径（如绕过 UI 直接访问结果页）
- 用例状态四态：PASS / FAIL / BLOCKED（环境故障，附 reason）/ SKIPPED
- case 之间数据独立：造数 → 记录 ID → 断言 → 按 ID 清理；cleanup 失败告警但不影响 case 结果
- result.yaml 是机器契约：report 只读 result.yaml，不解析 commands.log/截图
- DB 连接全量放环境变量（`QAP_DB_URL`），config 不存明文密码
- SessionStart hook 只注入一句话（lazy loading），不塞入各 skill 内容
- 敏感信息（密码/连接串）走 `${ENV_VAR}` 引用

---

### Task 1: 插件骨架与校验脚本

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `hooks/hooks.json`
- Create: `scripts/validate.sh`
- Create: `.gitignore`

**Interfaces:**
- Produces: 插件清单（name `qa-powers`）与 hook 注册，后续所有 skill 挂在 `skills/` 下；`scripts/validate.sh` 供每个后续任务作为测试步骤调用（校验所有 skill frontmatter 与 JSON 合法性）

- [ ] **Step 1: 写 .claude-plugin/plugin.json**

```json
{
  "name": "qa-powers",
  "description": "AI 驱动的 UI 自动化测试技能库：需求 → 用例 → 执行（playwright-cli + usql）→ 报告",
  "version": "0.1.0",
  "author": {
    "name": "qa-powers contributors"
  },
  "license": "MIT",
  "keywords": [
    "qa",
    "testing",
    "ui-automation",
    "playwright",
    "usql"
  ]
}
```

- [ ] **Step 2: 写 hooks/hooks.json（一句话 lazy loading）**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "echo '[qa-powers] available. 用户提到 UI 测试/设计用例/跑用例/测试报告时，先读取 using-qa-powers skill。'"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: 写 scripts/validate.sh（本项目的"测试"——结构校验）**

```bash
#!/usr/bin/env bash
# 校验插件结构：JSON 合法 + 每个 skill 有合法 frontmatter
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

for f in .claude-plugin/plugin.json hooks/hooks.json; do
  if ! jq empty "$f" 2>/dev/null; then
    echo "INVALID JSON: $f"; fail=1
  fi
done

if ! ls skills/*/SKILL.md >/dev/null 2>&1; then
  echo "NO SKILLS FOUND (skills/*/SKILL.md)"; fail=1
fi

for skill in skills/*/SKILL.md; do
  if ! head -1 "$skill" | grep -q '^---$'; then
    echo "MISSING FRONTMATTER START: $skill"; fail=1; continue
  fi
  fm=$(awk 'NR==1{next} /^---$/{exit} {print}' "$skill")
  echo "$fm" | grep -q '^name:' || { echo "MISSING name: $skill"; fail=1; }
  echo "$fm" | grep -q '^description:' || { echo "MISSING description: $skill"; fail=1; }
done

[ "$fail" -eq 0 ] && echo "OK: plugin structure valid"
exit "$fail"
```

- [ ] **Step 4: 写 .gitignore**

```
node_modules/
demo-db.sqlite
*.log
```

- [ ] **Step 5: 运行校验（预期失败——还没有 skill）**

Run: `chmod +x scripts/validate.sh && ./scripts/validate.sh`
Expected: FAIL，输出 `NO SKILLS FOUND`（红灯确认脚本有效）

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin hooks scripts/validate.sh .gitignore
git commit -m "feat: 插件骨架——plugin.json、SessionStart hook、结构校验脚本"
```

---

### Task 2: using-qa-powers 薄路由 skill

**Files:**
- Create: `skills/using-qa-powers/SKILL.md`

**Interfaces:**
- Consumes: 无（入口）
- Produces: 路由到 `qa-powers:init` / `qa-powers:design` / `qa-powers:run` / `qa-powers:report`（通过 Skill 工具调用）

- [ ] **Step 1: 写 SKILL.md（全文如下）**

```markdown
---
name: using-qa-powers
description: qa-powers 入口路由。当用户提到 UI 测试、测某个需求、设计/生成测试用例、跑用例、执行测试、生成测试报告时使用，负责识别意图并加载对应的 qa-powers skill。
---

# using-qa-powers（薄路由）

你只做两件事：**识别意图 → 加载对应 skill**。不做任何实际测试工作。

## 前置检查

1. 检查被测项目根目录是否存在 `.qa-powers/config.yaml`
2. 不存在且用户意图不是初始化 → 先引导用户走 `qa-powers:init`
3. 存在 → 读取 config.yaml（只读一次，记住 base_url / repos / db 配置）

## 路由表

| 用户意图（示例） | 加载 |
|---|---|
| "初始化测试环境"、"配置 qa-powers" | `qa-powers:init` |
| "测一下 ORD-1234 这个需求"、"根据需求设计用例"、"生成用例" | `qa-powers:design` |
| "跑用例"、"执行测试"、"回归一下" | `qa-powers:run` |
| "生成测试报告"、"看看结果" | `qa-powers:report` |

## 规则

1. 用 Skill 工具加载目标 skill 后，把控制权交给它，不要自己继续执行
2. 一次只路由到一个 skill；意图不明确时用一句话问用户，不要猜
3. 用户问的问题超出这 4 个 skill 范围（如"帮我修这个 bug"）→ 直接说明 qa-powers 不覆盖，正常回答
```

- [ ] **Step 2: 运行校验**

Run: `./scripts/validate.sh`
Expected: PASS（`OK: plugin structure valid`）——若 Task 1 后中途跑过应见此 skill 通过 frontmatter 检查

- [ ] **Step 3: Commit**

```bash
git add skills/using-qa-powers/SKILL.md
git commit -m "feat: using-qa-powers 薄路由 skill"
```

---

### Task 3: init skill

**Files:**
- Create: `skills/init/SKILL.md`

**Interfaces:**
- Consumes: 无
- Produces: 被测项目 `.qa-powers/config.yaml`（格式见下方，design/run/report 依赖）、目录骨架 `cases/ evidence/ reports/`、登录态 `auth-state.json`

- [ ] **Step 1: 写 SKILL.md（全文如下）**

```markdown
---
name: init
description: 初始化 qa-powers 测试环境。生成 .qa-powers/config.yaml 与目录骨架，校验 playwright-cli/usql/代码仓库/数据库/登录态可用，并沉淀登录态。用户说"初始化测试环境"或首次使用 qa-powers 时使用。
allowed-tools: Bash(playwright-cli:*), Bash(usql:*), Bash(git:*), Bash(mkdir:*), Read, Write, Edit, AskUserQuestion
---

# init：初始化测试环境

在**被测项目根目录**（不是 qa-powers 插件仓库）执行以下流程。

## 1. 交互式收集信息（AskUserQuestion，一次一个问题）

- base_url（被测系统地址）
- 登录方式（用户名密码表单 / 免登录）→ 用户名、密码的**环境变量名**（不收明文，提示用户写入 shell 配置）
- 前端仓库绝对路径 + 基线分支（默认 main）
- 后端仓库绝对路径 + 基线分支（默认 main）；无后端可跳过
- DB：驱动类型 + 连接串环境变量名（如 `QAP_DB_URL`）；无 DB 可跳过

## 2. 依赖校验（逐项执行，失败给出修复指引）

| 检查 | 命令 | 失败提示 |
|---|---|---|
| playwright-cli | `playwright-cli --version` | `npm install -g @playwright/cli@latest` |
| 浏览器 | `playwright-cli install-browser chromium`（幂等） | 同上 |
| usql | `usql --version` | `brew install usql` |
| 前端仓库 | `git -C <path> rev-parse --is-inside-work-tree` | 检查路径 |
| 后端仓库 | 同上（配置了才查） | 同上 |
| DB 连接 | `usql "$QAP_DB_URL" -c 'select 1'` | 检查环境变量与网络 |
| 环境变量存在 | `test -n "$QAP_TEST_USER"` 等 | 提示用户 export 后重试 |

## 3. 生成目录骨架

```bash
mkdir -p .qa-powers/cases .qa-powers/evidence .qa-powers/reports
```

## 4. 写 .qa-powers/config.yaml（用收集到的值）

```yaml
env: test
base_url: <收集值>
auth:
  username_env: QAP_TEST_USER
  password_env: QAP_TEST_PASS
  state_file: .qa-powers/auth-state.json
repos:
  frontend: { path: <收集值>, base: <基线分支> }
  backend:  { path: <收集值>, base: <基线分支> }   # 无则删除此行
db:
  url_env: QAP_DB_URL   # 无则删除整个 db 段
```

注意：config 里只存**环境变量名**，不存明文。

## 5. 沉淀登录态（免登录跳过）

1. `playwright-cli open <base_url>`
2. `playwright-cli snapshot` 找到登录入口，引导完成登录（凭据从环境变量读，不要让用户在对话里发明文）
3. 登录成功后：`playwright-cli state-save .qa-powers/auth-state.json`
4. `playwright-cli close`

## 6. 收尾

输出校验结果清单（✓/✗）+ 提示用户把 `QAP_TEST_USER` / `QAP_TEST_PASS` / `QAP_DB_URL` 加入 shell 配置。全部通过后提示：可以运行 `qa-powers:design` 设计用例了。
```

- [ ] **Step 2: 运行校验**

Run: `./scripts/validate.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/init/SKILL.md
git commit -m "feat: init skill——环境配置、依赖校验、登录态沉淀"
```

---

### Task 4: design skill

**Files:**
- Create: `skills/design/SKILL.md`

**Interfaces:**
- Consumes: `.qa-powers/config.yaml`（Task 3 产出；repos 段）
- Produces: `.qa-powers/cases/<模块>/case-NN.md`（frontmatter 格式如下，run/report 依赖）+ 可选 `setup.sql` / `cleanup.sql` + `meta.yaml`

- [ ] **Step 1: 写 SKILL.md（全文如下）**

```markdown
---
name: design
description: 根据需求设计 UI 测试用例。读取需求（文本/Jira/Confluence），强制做前后端仓库 diff 影响分析，交互式澄清后生成用例到 .qa-powers/cases/。用户说"设计用例"、"测一下 XX 需求"时使用。
allowed-tools: Read, Write, Edit, Bash(git:*), AskUserQuestion, WebFetch
---

# design：需求 → 用例

## 1. 读需求

按用户给的形式获取需求内容：
- 文本：直接使用
- Jira key（如 ORD-1234）：用 atlassian MCP 拉取 issue 描述与验收标准
- Confluence 链接：用 WebFetch/MCP 拉取
- 用户提供了本地用例文档：读取并规整为标准格式

把需求拆成需求点 R1、R2、...（每条可独立验证）。

## 2. 代码影响分析（强制步骤，不可跳过）

读 `.qa-powers/config.yaml` 的 repos 段，对每个仓库：

```bash
git -C <path> branch --show-current          # 只读，绝不 checkout
git -C <path> diff <base>...HEAD --stat     # 改动概览
git -C <path> diff <base>...HEAD            # 详细 diff（大仓库按目录分批看）
```

产出**改动点清单** D1、D2、...：涉及的页面/组件、接口、SQL/数据变更、配置。写入 `.qa-powers/cases/<模块>/meta.yaml`：

```yaml
module: <模块名，如 ORD-1234-checkout>
requirement_source: jira://ORD-1234
requirements: [R1: 正常下单, R2: 库存扣减]
base_branches: { frontend: main, backend: main }
changes:
  - id: D1
    repo: frontend
    ref: src/checkout/OrderForm.tsx
  - id: D2
    repo: backend
    ref: OrderController.create
```

## 3. 交互式澄清（AskUserQuestion，一次一个问题）

对以下内容不明确时逐条问：业务规则、验收标准、边界情况（空值/极值/并发）、权限差异。每个问题给选项。用户答"差不多就行"时按行业常规约定并在用例里标注假设。

## 4. 生成用例

覆盖矩阵：正常流 1 条 + 每个改动点 D 至少 1 条 + 边界/异常按澄清结果。每条用例写入 `.qa-powers/cases/<模块>/case-NN.md`：

```markdown
---
id: case-01
title: 正常下单流程
priority: P0
requirement: ORD-1234
covers: [D1, D2]          # meta.yaml 里的改动点 id
data: { setup: setup.sql, cleanup: cleanup.sql }   # 无 DB 需求则删除
---

## 前置
- 已登录（auth state）
- <业务前置，如：存在 1 个已上架测试商品>

## 步骤
1. <可在 UI 上执行的业务步骤>

## 预期
- UI: <页面上可观察、可判定的结果>
- DB: <表/字段级断言>（无则删除此行）
```

用例规则：
- 步骤是**业务语言**（"点击去结算"），不含执行细节（selector、会话名）
- 预期必须可判定：有明确文本/状态/数据，不写"页面正常"
- 需要造数/清理时，同目录写 setup.sql / cleanup.sql（幂等；造数 SQL 用 `INSERT ... ` 并注明如何取回生成的 ID）

## 5. 用户确认

列出用例清单（id/title/priority/covers），问用户是否需要增删改。确认后收尾提示：可运行 `qa-powers:run` 执行。
```

- [ ] **Step 2: 运行校验**

Run: `./scripts/validate.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/design/SKILL.md
git commit -m "feat: design skill——需求解析、diff 影响分析、用例生成"
```

---

### Task 5: run skill

**Files:**
- Create: `skills/run/SKILL.md`

**Interfaces:**
- Consumes: `.qa-powers/config.yaml`、`.qa-powers/cases/**`（Task 4 产出格式）、`auth-state.json`
- Produces: `.qa-powers/evidence/<run-id>/result.yaml`（run 级，格式如下）、`evidence/<run-id>/case-NN/{result.yaml, commands.log, screenshots/}`——report 只读这些 result.yaml

- [ ] **Step 1: 写 SKILL.md（全文如下）**

```markdown
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
usql "$QAP_DB_URL" -c "SELECT ... FROM orders WHERE ..." -W
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
```

- [ ] **Step 2: 运行校验**

Run: `./scripts/validate.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/run/SKILL.md
git commit -m "feat: run skill——guided-run 执行、四态判定、result.yaml 契约"
```

---

### Task 6: report skill

**Files:**
- Create: `skills/report/SKILL.md`

**Interfaces:**
- Consumes: `.qa-powers/evidence/<run-id>/result.yaml` + 各 case 级 result.yaml（Task 5 产出格式，**只读这两个**，不解析 commands.log/截图）
- Produces: `.qa-powers/reports/<run-id>.md`

- [ ] **Step 1: 写 SKILL.md（全文如下）**

```markdown
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

## 失败详情（每条 FAIL 一节）

### case-02 库存扣减验证 ❌

- **步骤**: step 8（提交订单）
- **预期**: UI 出现"下单成功"
- **实际**: 出现"系统异常"
- **证据**: `evidence/<run-id>/case-02/screenshots/step-08.png`（tracing 见 run 会话）
- **覆盖改动点**: D2（backend:OrderController.create）→ 初步判断方向：<结合预期/实际差异给一句话假设，如"提交接口报错，建议查后端日志与 OrderController.create" >

## BLOCKED 说明（有才写）

<case-id>: <reason>
```

## 4. 收尾

输出报告文件路径 + 一段话摘要（总数、通过率、最需要关注的失败）。提示：需要深入分析失败原因可继续对话排查（MVP 无独立 debug skill）。
```

- [ ] **Step 2: 运行校验**

Run: `./scripts/validate.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/report/SKILL.md
git commit -m "feat: report skill——四态统计与失败详情报告"
```

---

### Task 7: 示例被测项目（冒烟夹具）

**Files:**
- Create: `tests/demo/server.js`（Node http 服务：结账页 + sqlite 落库）
- Create: `tests/demo/public/index.html`（购物车→下单页）
- Create: `tests/demo/README.md`（启动说明 + 冒烟清单）

**Interfaces:**
- Produces: 本地可跑的被测系统（http://localhost:8899），供 Task 8 冒烟走通 init→design→run→report。订单写入 `demo-db.sqlite` 的 orders 表（usql 可查）

- [ ] **Step 1: 写 server.js**

```javascript
// 依赖：Node 18+、sqlite3 CLI（macOS 自带）。仅供 qa-powers 冒烟测试用。
const http = require("http");
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const PORT = 8899;
const DB = path.join(__dirname, "..", "demo-db.sqlite");
const exec = (sql) => execFileSync("sqlite3", [DB, sql], { encoding: "utf8" });

// 初始化表与测试商品（幂等）
exec("CREATE TABLE IF NOT EXISTS orders (id INTEGER PRIMARY KEY AUTOINCREMENT, product TEXT, amount INTEGER, status TEXT)");
exec("CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, stock INTEGER)");
if (!exec("SELECT COUNT(*) FROM products").trim().startsWith("1")) {
  exec("INSERT INTO products (name, stock) VALUES ('测试商品A', 10)");
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  if (req.method === "POST" && url.pathname === "/api/order") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const { product, amount } = JSON.parse(body || "{}");
      if (!product || !amount || amount < 1) {
        res.writeHead(400, { "Content-Type": "application/json" });
        return res.end(JSON.stringify({ error: "参数错误" }));
      }
      const id = exec(
        `INSERT INTO orders (product, amount, status) VALUES ('${product.replace(/'/g, "''")}', ${parseInt(amount, 10)}, 'pending'); SELECT last_insert_rowid();`
      ).trim();
      exec(`UPDATE products SET stock = stock - ${parseInt(amount, 10)} WHERE name = '${product.replace(/'/g, "''")}'`);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true, orderId: id }));
    });
    return;
  }
  const file = url.pathname === "/" ? "index.html" : url.pathname.replace(/\.\./g, "");
  try {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(fs.readFileSync(path.join(__dirname, "public", file)));
  } catch {
    res.writeHead(404);
    res.end("not found");
  }
});

server.listen(PORT, () => console.log(`demo: http://localhost:${PORT}  db: ${DB}`));
```

- [ ] **Step 2: 写 public/index.html**

```html
<!doctype html>
<html lang="zh">
<head><meta charset="utf-8"><title>测试商城</title></head>
<body>
  <h1>购物车</h1>
  <p>测试商品A x <input id="amount" value="1"> 件</p>
  <button id="checkout" onclick="submitOrder()">提交订单</button>
  <p id="result"></p>
  <script>
    async function submitOrder() {
      const amount = document.getElementById("amount").value;
      const r = await fetch("/api/order", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ product: "测试商品A", amount: Number(amount) }),
      });
      const data = await r.json();
      document.getElementById("result").textContent = data.ok
        ? `下单成功，订单号 ${data.orderId}`
        : `下单失败：${data.error}`;
    }
  </script>
</body>
</html>
```

- [ ] **Step 3: 验证 demo 可用（本任务测试）**

Run:
```bash
cd tests/demo && node server.js &
sleep 1
curl -s -X POST http://localhost:8899/api/order -H 'Content-Type: application/json' -d '{"product":"测试商品A","amount":1}'
usql sqlite://../demo-db.sqlite -c 'SELECT id, product, status FROM orders' -W
kill %1
```
Expected: curl 返回 `{"ok":true,"orderId":"N"}`；usql 能看到 status=pending 的订单行

- [ ] **Step 4: 写 tests/demo/README.md（冒烟清单）**

```markdown
# demo 被测项目（qa-powers 冒烟夹具）

启动：`node server.js` → http://localhost:8899

## 冒烟清单（对 qa-powers 插件，在新 Claude Code 会话中对 demo 目录执行）

1. `/qa-powers:init`——base_url=http://localhost:8899，跳过登录态，DB 用 `sqlite://<绝对路径>/demo-db.sqlite`
2. `/qa-powers:design`——需求："用户可以把购物车里的测试商品A下单，数量可填；库存要正确扣减"
3. `/qa-powers:run`——应产出 evidence/<run-id>/result.yaml，正常下单 case PASS
4. `/qa-powers:report`——应产出 reports/<run-id>.md，四态统计正确
5. 反例：手工把 index.html 的按钮文案改掉重跑 → 对应 case FAIL 且报告含预期/实际差异
```

- [ ] **Step 5: Commit**

```bash
git add tests/
git commit -m "test: demo 被测项目与冒烟清单"
```

---

### Task 8: README 与全量收尾验证

**Files:**
- Create: `README.md`
- Modify: 无

**Interfaces:**
- Consumes: 全部前序产出
- Produces: 项目文档 + 全量验证通过

- [ ] **Step 1: 写 README.md**

```markdown
# qa-powers

AI 驱动的 UI 自动化测试技能库（Claude Code 插件）。

> **AI 负责思考，工具负责执行，Evidence 负责证明。**

## 工作流

需求（文本/Jira/Confluence）→ `/qa-powers:design` 用例 → `/qa-powers:run` 执行
（playwright-cli 驱动有头浏览器 + usql 造数/验证）→ `/qa-powers:report` 报告

## 安装

```bash
/plugin marketplace add <本仓库>
/plugin install qa-powers
```

前置依赖：`npm install -g @playwright/cli@latest`、usql、环境变量 QAP_TEST_USER / QAP_TEST_PASS / QAP_DB_URL。

## 快速开始

在被测项目根目录：

1. `/qa-powers:init` —— 初始化 `.qa-powers/` 配置与登录态
2. `/qa-powers:design` —— 给需求文本或 Jira key，生成用例
3. `/qa-powers:run` —— 执行用例，产出 evidence
4. `/qa-powers:report` —— 生成报告

## 设计文档

见 `docs/specs/`。MVP 边界与后续演进（explore/stabilize/debug）见设计文档"后续演进"节。
```

- [ ] **Step 2: 全量结构校验**

Run: `./scripts/validate.sh`
Expected: PASS，`OK: plugin structure valid`

- [ ] **Step 3: 结构盘点（人工核对）**

Run: `ls skills/ hooks/ scripts/ tests/ .claude-plugin/`
Expected: skills 下 5 个目录（using-qa-powers/init/design/run/report），其余如计划所列

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README——安装与快速开始"
```

- [ ] **Step 5: 冒烟验收（真实执行，按 tests/demo/README.md 清单）**

在新的 Claude Code 会话中把本插件装入，对 `tests/demo/` 完整走一遍冒烟清单 1–5。全部通过即 MVP 验收完成。此项不在本计划内自动执行，需人工/agent 会话进行。
