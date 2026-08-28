# qa-powers

AI 驱动的 UI 自动化测试技能库（Claude Code 插件）：从需求直接生成可追溯的测试用例、驱动真实浏览器执行、产出带证据的测试报告。

> **AI 负责思考，工具负责执行，Evidence 负责证明。**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 它解决什么问题

传统 UI 自动化要么是脆的录制回放，要么是维护成本极高的代码脚本。qa-powers 把测试流程拆成四个 Claude Code skill，另附一个可选的远程环境运维 skill（k8s），让 AI 读需求、读代码 diff、设计用例、驱动浏览器执行，同时用严格的 evidence 结构（截图 / 命令日志 / result.yaml）保证每条结论可追溯：

```
需求（文本 / Jira / Confluence）
  → /qa-powers:design   读 diff 做影响分析，生成用例（每个改动点至少 1 条覆盖）
  → /qa-powers:run      playwright-cli 驱动浏览器执行，脚本路由造数/验证/清理（.sql→usql、其他脚本→本地 runner 或 k8s pod）
  → /qa-powers:report   汇总四态统计与失败详情

（可选）日常运维：/qa-powers:k8s   经堡垒机查远程 k8s 环境日志、进 pod / rails console、在容器里跑脚本、换节点；拓扑与个人身份入 config
```

核心特性：

- **改动点 → 用例 → 证据追溯链**：design 阶段强制分析前后端 diff，产出改动点清单（D1、D2...），每条用例标注 covers，报告能直接回答"这个改动测没测到"
- **业务语言用例**：用例步骤面向业务（"点击去结算"），执行细节由 AI 适配（selector 失效自动按语义重定位）
- **双环境**：init 时多选环境、一次配齐本地(local)与测试(test)，之后换环境由 `run` 开头选择、无需重新 init——local 的脚本用本地 runner 跑（任意命令：Rails 用 `bin/rails runner`，也可 node/python），test 的脚本经堡垒机在 pod 里跑；usql 两环境通用
- **通用项目类型**：init 探测后端项目类型（rails/node/python/other，写入 config `repos.backend.type`），runner 建议、schema 定义位置、密码配置文件等提示按类型分派；非 Rails 项目走同样的原理与流程，老 config 缺 type 时由 runner 命令自动推断
- **DB 级断言**：不只看 UI，usql 直连数据库做表/字段级验证，也可用 runner 做应用内脚本验证（走 ORM/业务逻辑）；测试数据自动清理
- **免环境变量**：凭据（账号密码、DB 连接串、JMS 身份）在 init 时直接明文存入 `.qa-powers/config.yaml`，无需维护 shell 环境变量；init 自动把 config 与登录态文件加入被测项目 `.gitignore`，防止误提交
- **环境特殊注意点**：init 把执行注意事项收进 config——顶层 `notes`（全环境共享，如列表页时间显示 UTC）与 `envs.<env>.notes`（环境专属，如登录页令牌留空、某库只读禁写），自由文本逐条；`run` 选定环境后读出全程遵守，并发执行也注入 subagent 共享上下文
- **四态状态机**：passed / failed / blocked / skipped，环境故障不算用例失败
- **首跑探索录制、二次起自动回放**：每条用例首次执行时把解析出的语义 locator 命令沉淀到 `cases/<模块>/<case-id>.replay.sh`；再次执行自动走回放模式直跑命令链，不再逐动作 snapshot 探索，断言/证据/造数不变。selector 失效自动单步降级探索并修脚本；删脚本即强制重新探索
- **config 记录插件版本**：`init` 把插件版本写入 `.qa-powers/config.yaml` 的 `plugin_version`，之后 design/run/report/k8s 会核对——若与当前插件 major.minor 不同（大/小版本升级）提醒重跑 `init` 更新 config，仅 patch 差异不影响、不提醒

## 安装

### 前置依赖

| 依赖 | 安装 | 说明 |
|---|---|---|
| Claude Code | https://claude.com/claude-code | 宿主 CLI |
| playwright-cli | `npm install -g @playwright/cli@latest` | 驱动浏览器；系统已装 Chrome/Edge 可直接用，无需下载 chromium |
| usql | https://github.com/xo/usql/releases | DB 造数与断言；macOS brew 可能构建失败，推荐下 release 二进制 |

### 安装插件

```bash
# 在 Claude Code 会话中
/plugin marketplace add https://github.com/cp5670681/qa-powers
/plugin install qa-powers@qa-powers
```

更新：`/plugin marketplace update qa-powers` 刷新源后执行 `/plugin update qa-powers@qa-powers`（脚本/CLI：`claude plugin update qa-powers@qa-powers`），按提示 `/reload-plugins` 或重开会话生效；无需卸载重装。发版靠版本号识别，仓库有新改动但版本未变时 update 会被跳过。

## 快速开始

在**被测项目根目录**开 Claude Code 会话：

1. `/qa-powers:init` —— 收集被测地址、登录方式、前后端仓库路径、DB 连接（凭据明文存入 config，之后无需设置环境变量），沉淀登录态
2. `/qa-powers:design` —— 给需求文本 / Jira key / Confluence 链接，生成 `.qa-powers/cases/<模块>/` 用例
3. `/qa-powers:run` —— 执行并产出 `.qa-powers/evidence/<run-id>/`
4. `/qa-powers:report` —— 生成 `.qa-powers/reports/<run-id>.md`

凭据在 init 时直接明文收集进 `.qa-powers/config.yaml`（init 会自动把该文件与登录态 `auth-*.json` 写入被测项目 `.gitignore`），无需预先设置任何环境变量。

## 目录结构

```
skills/          4 个测试工作流 skill + 1 个远程运维 skill + 1 个入口路由
hooks/           SessionStart 提示 hook；PreToolUse hook 自动放行 playwright-cli 命令与 usql 只读查询
scripts/         validate.sh 插件结构自检；allow-tools.sh 权限放行 hook 脚本；version-check.sh config 版本核对
tests/           开发用：test-allow-tools.sh / test-version-check.sh——hook 放行与版本核对回归测试；demo/ 冒烟夹具（见 CONTRIBUTING.md）
```

## 安全声明

- 凭据明文存于 `.qa-powers/config.yaml`（明换便利，属用户选择）；init 自动写入被测项目 `.gitignore`（覆盖 `config.yaml` 与 `auth-*.json`），请勿移出忽略名单
- 插件绝不 checkout / 修改被测仓库，只读分析
- 插件自带 PreToolUse hook：`playwright-cli` 命令（含纯 playwright-cli 组成的复合命令）与 **usql 只读内联查询**自动放行、免权限确认。只读判定覆盖：单条 `SELECT/SHOW/DESC/DESCRIBE/PRAGMA(查询型)/EXPLAIN(不含 ANALYZE)/VALUES`，以及 **psql 展示元命令**（`\d`、`\d+`、`\dt`、`\dS`、`\dv`、`\di`、`\dn`、`\df`、`\ds`、`\dp`、`\do`、`\dx`、`\db`、`\du`、`\l`、`\?`，命令 token 后只跟空白/表名/串尾）；`-c` 带引号、**仅单个 `-c`**、无 `-f`/`--file`（含与 `-c` 并存）、无写关键字/多语句/WITH/INTO/EXPLAIN ANALYZE，取参按 bash 语义解码（单引号内 `\` 字面、双引号内 `\"` 转义，引号跨行不闭合一律不放行）。元字符防线为**引号感知**——SQL/URL/填充值在引号内的 `& < > \` $(` 视为字面量（如 `?a=1&b=2`、`2>&1`）：单引号内全字面；双引号内 `& < >` 为字面量、但 `$(` 与反引号仍是命令替换、照拦不误（如 `"SELECT $(id)"`）；引号外的 `\` 转义下一字符（`\"` 不开启引号），引号外的 `& < > \` $(`` 才拦截后台执行/重定向/命令替换；`&&` 与 fd 重定向（`N>&N`）豁免。写库、psql 危险元命令（`\!`、`\o`、`\copy`、`\c`、`\cd`、`\set`、`\gset` 等）、usql `-f` 脚本、ssh、脚本执行等仍走正常确认。机器无 jq 时自动退回默认确认流程
- 浏览器由 playwright-cli 管理，登录态文件 `.qa-powers/auth-*.json` 含会话 cookie，同样在忽略名单内

## 开发与贡献

```bash
./scripts/validate.sh    # 校验插件结构与 frontmatter
```

见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 致谢

受 [obra/superpowers](https://github.com/obra/superpowers) 启发。

## License

[MIT](LICENSE)
