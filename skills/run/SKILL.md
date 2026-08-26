---
name: run
description: 执行测试用例（guided-run）。开头选环境（local/test），逐条用例：脚本路由造数（.sql→usql、其他脚本→本地 runner 或 k8s pod）→ playwright-cli 按业务步骤驱动有头浏览器 → 三层断言（UI/网络/DB，DB 可 usql 或应用内脚本）→ 清理 → 产出 result.yaml。用户说"跑用例"、"执行测试"、"继续测试"时使用。
allowed-tools: Bash(playwright-cli:*), Bash(usql:*), Bash(ssh:*), Bash(cat:*), Bash(mkdir:*), Bash(date:*), Read, Grep, Glob, Write, Edit, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, Agent
---

# run：guided-run 执行用例

## 硬约束（违反即执行错误）

1. **业务意图固定，执行细节允许适配**：按 case 步骤执行；selector 可以修正（快照 ref 失效时按语义重新定位，如 getByRole 等价元素），但**禁止改变业务路径**（如绕过下单 UI 直接访问成功页）
2. **绝不 checkout 被测仓库**
3. 密码/连接串从 config 明文读；commands.log 与对话输出不得回显密码明文
4. **页面 URL 禁止猜测**：从 config `repos.frontend.path` 的路由代码推导（router 配置 / 页面组件的 route 定义），必要时前后端代码都可参考（如定位元素结构、确认接口行为），但只读，不修改
5. **并发模式附加约束**：并发执行中禁止 `state-save`（多会话共读登录态文件，写会互相踩）；DB 写操作（造数/清理）只允许操作用例自身的独立数据（自己的 setup 造出的、带模块标记的记录），跨用例共享数据（同一行/同一库存/同一账号互斥状态）靠 `depends_on` 串行化——与 design 的依赖判定口径一致：无 `depends_on` = 各自独立数据、可并发；每个 subagent 只能操作自己的 `-s=qap-<case-id>` 会话
6. **提问一律用中文**：所有 AskUserQuestion 的 question、header、选项 label 与 description 都用中文（base_url、DB、k8s、runner 等技术名词可保留英文）；向用户汇报结果也用中文

## 0. 准备

> 路径口径：本 skill 全文的 `cases/`、`evidence/` 均指被测项目根下的 `.qa-powers/cases/`、`.qa-powers/evidence/`；凡写「绝对路径」处一律为 `$PWD/.qa-powers/evidence/...`（用 `pwd` 取被测项目根拼接）。

1. 读 `.qa-powers/config.yaml`
2. **选环境（硬性步骤）**：读 `active_env`，AskUserQuestion 确认本次跑哪个 `envs` 键（local/test）或切到另一个；config 只配了一个环境时直接用它，不再问。确定 `ENV` 后，下文所有 base_url / 登录态 / DB URL / 脚本后端一律从 `envs.<ENV>` 取。记入 commands.log 与 run 级 result.yaml（`env: <ENV>`）
3. `run_id=$(date +%Y-%m-%d-%H%M%S)`；`mkdir -p .qa-powers/evidence/$run_id`。**断点续跑**：若最新 run（evidence 目录名按 `YYYY-MM-DD-HHMMSS` 字典序取最大，即最新）下存在未完成 case（case 目录无 result.yaml），先问用户「继续该 run（复用其 run_id 与 evidence 目录，跳过已有终态 result.yaml 的 case，从第一个未完成的接着跑）还是新开 run」
4. **建立路由映射**：
   - 先查 `cases/<模块>/meta.yaml` 是否已沉淀 `routes:`（「页面名 → 完整 URL」映射，见下）→ 有则直接复用，不再推导
   - 无则用 Grep/Glob 在前端仓库路由配置中查目标页面的 route 定义推导。**先确认 router mode**（`src/router/index.js` 的 `mode:` 字段）：`hash` 模式下完整 URL 带 `#/` 前缀（如 `http://host/#/works/...`），history 模式不带——拼错 `#/` 会 404。相对 path（如 `total_package_progress_remark_statistics`）要结合父路由前缀（如 `/works`）拼成完整路径
   - 推导成功后把「页面名 → 完整 URL」回写 `meta.yaml` 的 `routes:` 段，供本次 run 及下次复用（路由改动时更新）
   - 用例步骤涉及导航（goto）时一律使用该映射；映射中找不到时先查前端代码确认，仍不确定才问用户，**禁止凭记忆或猜测拼 URL**
5. **执行模式选择（AskUserQuestion）**：
   - 顺序 / 并发。并发时再问并发上限（默认 3，可选 2/3/4——每个 worker 是一个独立浏览器实例）
   - **有头 / 无头（两种模式都问）**：推荐默认**无头**（证据靠截图/快照，无头更快更稳、多开不抢资源）；有头用于演示或排查单条 case 时选。**有头 + 并发提示**：每个 worker 是有头浏览器窗口（3 worker = 3 窗口抢资源），有头并发建议把上限降到 2
   - 选择记入 commands.log 与 run 级 result.yaml（`mode: sequential|parallel`、`headed: true|false`、`workers: N`）
6. 加载登录态并开浏览器（顺序模式）：`playwright-cli open <envs.<ENV>.base_url> --browser <channel> [--headed]` → `playwright-cli state-load <envs.<ENV>.auth.default 账号的 state_file>`（初始加载 default 主账号；无 auth 段=免登录，跳过登录态加载） → `playwright-cli goto <envs.<ENV>.base_url>`，确认已登录（未登录 → 先按 §1 多账号切换的**自动登录**流程重新登录沉淀；仍失败 → 整个 run BLOCKED，走环境故障流程）
7. `playwright-cli tracing-start`，**并确认输出无 Error**（如 `Tracing is not started` 类报错要在开跑前处理）。注意：关键命令不要用管道截取输出（`| tail`会吞掉报错），必须看到完整成功输出再继续；tracing 确实起不来时降级为仅截图取证，在 commands.log 标注
8. 用户指定跑哪些 case（默认 cases/ 下全部，按 priority 降序）
9. **分支核对（仅 local；test 跑 pod 内代码，跳过）**：本地脚本/浏览器对着工作区执行，前后端仓库都须在特性分支上。对本次要执行的每个模块，读 `cases/<模块>/meta.yaml` 的 `feature_branches`，逐仓库核对 `git -C <path> branch --show-current`：
   - 当前分支 ≠ 特性分支 → 停下提示，请**用户自己切**（`! git -C <path> switch <特性分支>`；本地没有先 `git fetch` 再 `git switch --track origin/<特性分支>`），**AI 绝不 checkout**。用户坚持用当前分支 → 放行并在 commands.log 注明「分支不符：current vs feature」。提醒用户切分支前本地改动需已提交或 stash
   - meta 无 `feature_branches`（旧用例）→ AskUserQuestion 问本次特性分支，或用户确认跳过核对

## 0.5 脚本执行路由（造数/清理/DB 断言共用）

`ENV`（§0.2）决定执行后端；脚本载体决定走 usql 还是 runner：

| 载体 | local 环境 | test 环境（k8s） |
|---|---|---|
| `.sql` 文件 | `usql "<envs.<ENV>.db.url>" -f <file>`（两环境通用） | 同左 |
| 其他脚本文件（.rb/.py/.js/.sh…） | `cd <repos.backend.path> && <envs.local.script.runner> <file>`（本地 runner，任意命令） | **本地脚本 stdin 管道进 pod**（app=`envs.<ENV>.script.app`；ssh 三项取 `envs.<ENV>.k8s.jms` 与 `nodes` 表、app 四项取该 app，禁止猜）：`cat <file> \| ssh -p <envs.<ENV>.k8s.jms.port> '<envs.<ENV>.k8s.jms.user>@<nodes 表目标节点 IP>@<envs.<ENV>.k8s.jms.host>' 'kubectl exec -i -n <ns> $(kubectl get pods -n <ns> \| grep Running \| awk "{print \$1}" \| grep -E "<pod_pattern>") -c <container> -- <runner> -'` |
| 内联脚本 | `cd <repos.backend.path> && <runner> <内联参数> '<code>'`（local 无 ssh 层，引号简单，可用） | **禁止内联**——ssh+kubectl 多层引号嵌套会吃掉插值/特殊字符（Ruby `#{}`、shell `$var`）；一律写本地脚本文件走上一行管道模式 |

内联参数按 runner 语言取（Rails/Node 用 `-e`，Python 用 `-c`）；管道模式 runner 用 `-` 从 stdin 读脚本（`bin/rails runner -` / `node -` / `python -` 均支持，不确定先跑 hello 探测）；test 环境一律落盘/管道，最稳。

规则：

- **只读直接跑、写数据必须确认（任何环境都适用）**：纯查询——usql 单条 `SELECT/SHOW/DESC/DESCRIBE/PRAGMA(查询型)/EXPLAIN(不含 ANALYZE)`，或脚本/runner 内只有只读逻辑（查询/puts）——直接执行，**不需 AskUserQuestion**；usql 只读内联查询已由 PreToolUse hook 自动放行、免确认。一旦涉及写（`INSERT/UPDATE/DELETE/CREATE/ALTER/DROP/TRUNCATE/GRANT`、`PRAGMA name=值`、`EXPLAIN ANALYZE`、或脚本含写入逻辑/副作用），执行前必须 AskUserQuestion 确认（test/k8s 环境同 k8s skill：动哪些表/数据、量级、是否可回滚）
- 未配 script 段 / 无后端仓库 → 只允许 `.sql`（usql）；执行中遇到脚本文件停下，提示配置 runner 或改用 `.sql`
- **多库**：`envs.<ENV>.db` 配了 `dbs: { 别名: { url, desc } }` 时，usql 目标库按 case frontmatter `dbs:` 声明的别名取 `dbs.<别名>.url`；用哪个库先看该别名的 `desc` 说明。用例 SQL 引用了别名而未声明 → 停下问用户或用 `db.url` 默认库
- local 环境：runner 与 workdir（= repos.backend.path）取 config，**禁止猜**；runner 启动慢**不等于卡死**，不要提前杀掉重试
- local 首次执行 runner 命令会被权限拦截 → 授权放行（或把 `Bash(cd:*<runner>:*)` 写入 settings 白名单）

## 1. 逐条 case 执行（顺序模式）

对每条 case，在其证据目录 `evidence/$run_id/<case-id>/` 下工作（先 mkdir，并建 screenshots/）。断点续跑时，case 目录已有终态 result.yaml 的直接跳过，在 commands.log 注明 resumed-skip。

**多账号切换**：case frontmatter 声明了 `account:` 且与当前已加载账号不同时，先切换：`playwright-cli state-load <envs.<ENV>.auth.accounts.<该账号>.state_file>` → `playwright-cli goto <envs.<ENV>.base_url>` → snapshot 确认登录身份已切换（页面上能看到当前用户标识时核对）。state_file 不存在或加载后未登录 → **自动登录**（先 snapshot 识别登录页类型）：
- **普通登录页**：定位登录入口 → 用 config 该账号的 username/password fill 提交
- **SSO 登录页**（识别：URL 跳转到独立认证域名——URL 含 auth/oauth/sso 且非业务域名，页面是统一认证入口）：填 username/password 提交；页面出现额外多因子字段（令牌/验证码等）且非必填（有「忘记/暂不」类跳过入口）时留空跳过；登录成功按 redirect/return_to 参数自动回跳业务页。具体域名与页面文案以实际系统为准，勿套用固定文案
- 登录成功后 `state-save <该账号 state_file>` 沉淀 → 回到目标页继续（fill 密码的命令记入 commands.log 时密码值脱敏为 `***`）。自动登录仍失败 → 该 case 标 blocked（reason 注明账号与原因）。切换/登录动作记入 commands.log。

### a. 造数（有 data.setup 时）

按 §0.5 路由执行 setup 文件：

```bash
usql "<envs.<ENV>.db.url>" -f <setup.sql 路径>      # .sql 载体；多库时目标库取 db.dbs.<别名>.url（别名见 case frontmatter dbs:）
# 或
cd <repos.backend.path> && <runner> <setup 脚本路径>   # 脚本文件（local）
```

造数产生的 ID（如订单号/商品 ID）记入 commands.log 注释行。INSERT 报 NOT NULL/约束错误时，先一次查全该表约束再改脚本，不要逐列试错（按 DB 方言选，SQLite 没有 information_schema）：

```sql
-- PostgreSQL / MySQL
SELECT column_name, is_nullable, column_default FROM information_schema.columns WHERE table_name='<表名>';
-- SQLite
PRAGMA table_info('<表名>');
```

### b. 按步骤执行

先查本 case 是否有回放脚本 `cases/<模块>/<case-id>.replay.sh`：

- **有 → 回放模式（首跑已沉淀，无需探索）**：直接逐条执行脚本里的命令（已是语义 locator，如 `playwright-cli click "getByRole('button', { name: '提交' })"`）。命令间**不主动 snapshot**，只在断言处、关键节点、命令报错时才 snapshot。命令失败（元素找不到/超时）→ 对该步回退探索模式重定位，并**更新 replay.sh 对应命令**。回放脚本只含 UI 操作链；造数/清理/断言照常走 §a/§0.5/§c。并行模式每行命令前加 `-s=qap-<case-id>`（同硬约束 5）；跨环境回放时 goto 行 host 替换为当前 ENV 的 base_url
- **无 → 探索+录制模式**：走下方探索流程，同时把解析出的稳定命令沉淀到 `cases/<模块>/<case-id>.replay.sh`（下次自动回放）；删除该脚本即强制重新探索

探索流程（对 case 的每个步骤）：
1. `playwright-cli snapshot` 获取页面结构
2. 按步骤语义操作（goto/click/fill/select/press...），找不到目标元素时重新 snapshot 按语义定位，**重试 1 次**。语义等价元素找到但文案与用例引用不一致（如按钮名变了）→ 可用该元素完成操作以验证后续行为，但必须补一条 ui 断言：expected=用例引用的文案、actual=页面实际文案、status=failed——文案漂移是 UI 回归，不属于可适配的 selector 差异
3. **录制**：操作成功后用 `playwright-cli --raw generate-locator <ref>` 把元素 ref 转成语义 locator，对应命令写入 replay.sh（`playwright-cli click "getByRole(...)"`）；fill/select 的值、goto 的 URL 原样记入。**用语义 locator 不用 ref**——ref 每次 snapshot 会变，role locator 稳定
4. 每条执行的命令追加写入 commands.log，格式：`# <case-id> step N: <步骤摘要>` 换行 `<实际命令>`
5. 关键节点（提交前后、断言处）`playwright-cli screenshot --filename <$PWD/.qa-powers/evidence/$run_id/<case-id>/screenshots/step-NN.png 的绝对路径>`——**一律用绝对路径**：会话 cwd 常在被测仓库根，相对路径会把截图写进仓库根污染工作区；不带 `--filename` 时 playwright-cli 用默认命名 `qap-<session>-stepNN.png` 也落在 cwd。收尾核对 screenshots/ 目录截图齐全、被测仓库根无残留 png（误落根目录的移到证据目录或删除）
6. 出现意外状态（弹窗/报错）→ snapshot 判断：可关闭的关闭后继续；疑似 bug → 截图取证、在日志标注、按用例预期判定 FAIL，继续下一条步骤或下一 case

### c. 断言（预期环节）

三层验证，可信度递增，**结论以下层为准**（快照会骗人：异步未返回、缓存都可能让快照失真）：

1. **UI**：snapshot 中查找预期文本/元素，记录实际值
2. **网络**（凡涉及提交/接口交互的断言必查；纯静态展示可略）：`playwright-cli requests` + `response-body <n>` ——请求是否发出、参数、真实返回（注意 HTTP 2xx ≠ 成功，错误响应也可能 200/201，必看响应体的 message/数据）
3. **DB**（预期含 DB: 时）：按 §0.5 路由，usql 原始 SQL 或应用内脚本验证二选一（脚本走 runner 更能反映业务逻辑/关联，usql 看落库原值）。落库字段与副作用：
   - **多库选择**：跨库断言（如内部库 + 已发布库）时，config 的 `envs.<ENV>.db` 可配多库（`dbs: { 别名: { url, desc } }`），case frontmatter 用 `dbs:` 声明所需库；usql 按别名取 `dbs.<别名>.url`（用哪个库看 desc），无别名默认 `db.url`。subagent 派发时把 case 需要的 DSN 全部给出（见 §2b）

```bash
usql "<envs.<ENV>.db.url>" -c "SELECT ... FROM orders WHERE ..."   # 多库时目标库取 db.dbs.<别名>.url（别名见 case frontmatter dbs:）
# 或（local，应用内脚本验证，runner 任意命令）
cd <repos.backend.path> && <runner> -e 'puts Order.find_by(...).attributes'
```

快照结论与网络/DB 冲突时以下层为准；只凭快照判 PASS 前，先确认不需要下层佐证。比对实际值与预期值，查询与结果追加进 commands.log。

- **瞬态元素断言（toast/一闪而过的提示）**：snapshot 往往来不及抓取，按以下优先级降级，并在 result.yaml 的 actual 中注明断言方式：
  1. 操作后立即 snapshot / screenshot（1 次重试）
  2. **行为断言**：预期"被拦截"时，验证「关键网络请求未发出」（requests 中无对应 POST）+「页面状态未变」（弹窗未关/数据未创建）
  3. console 日志中查找前端报错/业务日志
- **量化预期先取真值再比对**：排序/Top-N/计数/默认值类预期，先按实现逻辑（改动代码中的查询/排序）在库里跑一遍得出期望值，再与页面实际比对——不以页面展示反推预期。查库所得与用例声明的需求口径冲突（如实现按 updated_at 排序、需求要求 created_at）时，**以用例预期为准判 FAIL 并备注「需求偏差」**，不拿实现现状当预期
- **校验类用例「意外成功」**：预期"被拦截/报错"却通过了 → 先查 DB 确认是否真的写入。未写入则按断言正常判定；已写入即误创建：立即按记录 ID 清理，在 result.yaml 的 cleanup 段如实注明「执行中误创建并已清理」，然后复测该用例

### d. 清理（有 data.cleanup 时）

按 §0.5 路由执行 cleanup 文件。

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
    carrier: usql     # usql | runner（用应用内脚本断言时标注，供 report 展示）
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
| hash 路由 URL 拼错 | goto `http://host/works/...` 404/白屏 | 先确认 router mode，hash 模式 URL 带 `#/` 前缀；用 meta.yaml `routes:` 沉淀的完整 URL（§0.4） |
| 截图写错位置 | 截图落在仓库根（相对路径/默认命名落在 cwd） | 截图命令用绝对路径写 evidence 目录（§1b 第 5 点），收尾核对仓库根无残留 png |
| ref 过期 | `Ref xxx not found` | 重新 snapshot 按语义定位（§1b 重试 1 次） |
| 误创建数据 | 校验用例意外写入 | 见 §1c「意外成功」：查库 → 清理 → 注明 → 复测 |
| local 环境服务没起 | 页面 5xx/连接拒绝 | 本地环境无 k8s，提示用户起服务/看本地日志；不是用例失败（blocked） |

## 2. 并发执行（依赖图调度，参考 superpowers subagent-driven-development 模式）

选并发模式时，主会话只做 **orchestrator**（分组/派发/收集），不亲自操作浏览器：

### a. 建依赖图

- 每条入选 case 用 TaskCreate 建任务；case frontmatter 的 `depends_on` 映射为 TaskUpdate 的 `blockedBy`
- 无 `depends_on` 的用例之间不建依赖（即全部同时可跑）
- 依赖声明的用例若前置未入选/已失败 → 该 case 标 skipped（reason 注明前置缺失）

### b. 派发循环

- **账号预沉淀（派发前）**：汇总入选 case 声明的全部 `account`，state_file 缺失或未登录的，先在主会话按 §1 多账号切换的自动登录流程逐个沉淀——并发执行中禁止 state-save，必须提前备好
- **生成共享上下文（派发前）**：写 `.qa-powers/evidence/<run-id>/context.md`，含 ENV（base_url、登录态文件路径、浏览器 channel/headless）、DB DSN 列表（按各 case frontmatter `dbs:` 声明从 `envs.<ENV>.db` 取，含多库别名及 desc）、路由映射、会话隔离约定（`-s=qap-<case-id>`）、执行协议（§1b/c/d）。subagent prompt 只需引用该文件 + case 全文/测试数据，不再逐条重复环境信息（减少写错与冗长）
- **滚动派发（保持 N 并发，不等整批）**——参考 p-queue / worker pool 的并发队列语义，任务完成事件触发补位：
   - **机制（关键）**：subagent 一律用 `run_in_background: true` 派发（Agent 工具后台运行），完成后自动收到 task-notification，主会话**不被阻塞**。这是滚动与「分批等整批」的分水岭——阻塞式 Agent 调用一次派 N 个后必须等全部返回，快的会空等慢的（实测 case-01 20 分钟期间，仅 6 分钟的第二批 case 完全没开始）。宿主 Agent 工具不支持 `run_in_background` 时退回阻塞式派发、按批等整批（机制降级，不改变正确性）
  - **初始派发**：一次派发 `min(N, 待跑 case 数)` 个（同一响应内多个 Agent 调用 = 并行）
  - **补位**：每收到一个完成通知 → 校验该 case 的 result.yaml → 立即从「pending 且无 blockedBy」中按 priority 取下一个补派，**维持在跑 ≤ N**；禁止等整批完成再派下一批
  - **结束**：pending 空且无在跑 → 进入收尾（§4）。等待期间不轮询、不 sleep（完成通知自动到达）；确需等时用 bounded wait，间隔只发一行状态
  - **故障**：连续 2 个在跑用例同类环境原因 blocked → 停止补派（§2c）
- 每条 case spawn 一个 general-purpose subagent（一次消息里可同时派多个），prompt **必须自包含**：
  1. 用例全文 + 测试数据（具体 ID/账号等，subagent 没有主会话上下文）
  2. **ENV**（`envs.<ENV>` 的 base_url、登录态文件路径、浏览器 channel/headless 选择）、脚本后端（local：`envs.local.script.runner`；test：`envs.<ENV>.script.app` 及其 k8s runner）、DB DSN（引用 context.md 或按 case frontmatter `dbs:` 给出全部所需库）
  3. **会话隔离**：所有 playwright-cli 命令一律带 `-s=qap-<case-id>`，禁止操作其他会话
  4. 执行协议：snapshot→按语义操作→重试 1 次；三层断言（快照/网络/查库）结论以下层为准；瞬态断言降级；校验用例意外成功先查库；截图用**绝对路径**写入自己的 `.qa-powers/evidence/<run-id>/<case-id>/screenshots/`（同 §1b 第 5 点，禁止相对路径）；**探索成功后把稳定命令沉淀到 `cases/<模块>/<case-id>.replay.sh`**（同 §1b 录制规则，下次自动回放）；结束幂等关闭自己的会话（close 报 not open 可忽略）
  5. 产出：按 case 级 result.yaml 模板写入 `evidence/<run-id>/<case-id>/result.yaml`，并在返回消息里报告一行结果摘要
  6. 禁止：state-save、checkout 被测仓库、改用例业务路径
- subagent 返回后：校验 result.yaml 存在且结构合法（缺失/畸形 → blocked，reason 注明 subagent 未产出有效结果）；**核对证据目录截图齐全、被测仓库根无残留 png、replay.sh 已生成**（replay.sh 缺失 → 提醒补沉淀，不改变用例状态）；TaskUpdate 完成，释放后继依赖

### c. 故障与收束

- **2 个在跑用例因同类环境原因 blocked → 停止派发新 subagent**，等在跑的收尾，随后按 §3 环境故障处理（含 k8s 排查与恢复判定）
- 全部结束后进入收尾（§4），run 级 result.yaml 增加 `mode: parallel`、`workers: N`

## 3. 状态判定规则

| 状态 | 判定 |
|---|---|
| passed | 所有断言通过 |
| failed | 任一断言未通过（UI 实际 ≠ 预期，或 DB 数据不符） |
| blocked | 环境故障：登录失败、DB 连不上、服务 5xx/超时。**不算用例失败** |
| skipped | 用户指定跳过 |

**环境故障处理**：连续 2 条 case 因同类环境原因 blocked → 停止派发。若当前 `ENV` 是 test 且 config 该环境配了 `k8s` 段，先加载 `qa-powers:k8s` 查后端日志 / pod 状态定位环境原因（结论记入 run 级 result.yaml；修复类操作按该 skill 规则需用户确认），排除后可恢复则继续 run；仍无法恢复 → 停止 run，剩余 case 全部标 blocked（reason 同），直接进入收尾。当前 `ENV` 是 local → 无 k8s，提示用户起本地服务/看本地日志定位。

## 4. 收尾

1. `playwright-cli tracing-stop`、`playwright-cli close`
2. **核对证据完整性**：每个 case 证据目录截图齐全；`git status` 检查被测仓库根无残留 png/临时文件（subagent 截图误落根目录的移到证据目录或删除）。缺截图/残留不改变用例状态，但收尾向用户一并说明
3. 写 run 级 `evidence/$run_id/result.yaml`：

```yaml
run_id: 2026-08-23-143015
module: ORD-1234-checkout
env: local              # local | test（§0.2 所选）
mode: parallel          # sequential | parallel
workers: 3              # 并发模式时有效
env_diagnosis: ""       # 走过环境故障处理时必填：原因结论 + 排查动作（如 k8s 日志片段）
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

4. 向用户报告一句话结果（如 `共 2 条用例：1 通过，1 失败`），cleanup 残留告警，提示运行 `qa-powers:report` 生成报告

断点续跑收尾时：run 级 result.yaml 的 summary 汇总该 run **全部** case（含 resumed-skip 的，状态沿用其已有 result.yaml，不丢历史）
