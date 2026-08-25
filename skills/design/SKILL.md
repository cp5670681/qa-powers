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

**拉取失败降级**：MCP 报错（认证失效/连接失败）或 WebFetch 被拦时，直接请用户把需求内容粘贴到对话里，不要卡在重试上；同时提示用户可用 `claude mcp auth <server>` 重新授权。

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

**权限差异处理**：config 当前环境为多账号（`envs.<env>.auth.accounts`）时，权限相关的需求点要按账号拆用例——每个账号至少 1 条"该权限下可见/可操作"的正向用例，差异点补"无权限账号不可见/被拦截"的用例；每条用例在 frontmatter 用 `account:` 声明使用哪个账号（缺省用 `envs.<env>.auth.default`）。

## 4. 生成用例

覆盖矩阵：正常流 1 条 + 每个改动点 D 至少 1 条 + 后端错误分支（无权限/重复/超限/不存在）中 UI 可达的逐条至少 1 条 + 边界/异常按澄清结果。每条用例写入 `.qa-powers/cases/<模块>/case-NN.md`：

```markdown
---
id: case-01
title: 正常下单流程
priority: P0
requirement: ORD-1234
covers: [D1, D2]          # meta.yaml 里的改动点 id
account: admin            # 多账号时使用的账号名（config envs.<env>.auth.accounts 的 key）；单账号/默认账号可省略
depends_on: []            # 依赖的前置用例 id；无依赖（可并发）时省略此行
data: { setup: setup.sql, cleanup: cleanup.sql }  # 无 DB 需求则删除；也可用脚本文件（.rb/.py 等，非 .sql 走 runner）
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
- **文案溯源（强制）**：用例中出现的每个按钮名、提示语、错误文案必须来自真实代码（前后端 diff 原文），不凭需求文档想象——文案写错，执行时就找不到元素
- 预期必须可判定：有明确文本/状态/数据，不写"页面正常"。量化预期（排序/Top-N/计数）写清判定口径（按什么字段什么顺序、取前几条、满足什么条件计数），具体期望值由 run 阶段按实现逻辑查库得出再比对
- **预期以需求为准，不迁就实现**：读 diff 发现实现与需求不一致时，预期仍写需求要求的值，并在该用例下备注「需求偏差：实现现状 + 代码位置」——执行时判 FAIL 正是要抓的问题；严禁为了让用例通过把预期改成实现现状
- **依赖声明（供并发执行）**：用例间共享可变测试数据（同一条记录的造数/消耗/清理）、或存在业务先后关系时，用 frontmatter `depends_on: [case-XX]` 声明前置；**无依赖的用例不写此字段**（即视为可并发）。判定口径：操作同一行数据/同一库存/同一账号互斥状态 → 有依赖；只读、各自独立数据、不同账号 → 无依赖
- **预期可达性审查（强制）**：每条 UI 预期对照改动的组件代码确认 UI 上可触发。重点检查：控件是否有 `clearable`/`disabled`（能否清空/操作）、输入框 `maxlength`（长度校验是否被前端拦截）、默认值是否总有值（拦截分支是否可达）。UI 不可达的拦截分支不写成用例预期，可在 meta.yaml 或报告备注中标注为"防御性代码，UI 不可达"
- 需要造数/清理时，同目录写 setup/cleanup 脚本（幂等）。**载体按执行后端选**：`.sql` 走 usql（原始 SQL，插入/清理直接）；脚本文件（`.rb`/`.py`/`.js` 等，非 `.sql`）走 runner（应用内造数，需 ORM/回调/业务逻辑时用）。local 用本地 runner，test 走 k8s pod（执行细节由 run 阶段按 config 路由，design 只决定脚本内容）。造数用 `INSERT`（usql）或应用内建数（runner）并注明如何取回生成的 ID；造数记录的业务名称带模块标记（如 `ORD-1234测试商品（勿动）`），便于识别、复测保留与清理排查

## 5. 用户确认

列出用例清单（id/title/priority/covers），问用户是否需要增删改。确认后收尾提示：可运行 `qa-powers:run` 执行。

## Common Mistakes

| 错误 | 后果 | 对策 |
| --- | --- | --- |
| 只读需求不读 diff | 用例文案与实际 UI 对不上，执行时找不到按钮 | 代码影响分析不可跳过，文案取自 diff 原文 |
| 把预期写成实现现状 | 用例恒过，需求偏差被洗白 | 预期只写需求值；实现不一致时备注「需求偏差」 |
| 编造测试数据 ID | 数据不存在，用例无法执行 | 用特征描述 + setup.sql 造数，ID 执行时取回 |
| 预期写"正常展示" | 无法判定通过与否 | 写具体文案/值/数量 |
| 遗漏负面场景 | 校验逻辑漏测 | 后端 UI 可达的错误分支逐条配用例 |
