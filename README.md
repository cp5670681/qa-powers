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

（可选）日常运维：/qa-powers:k8s   经堡垒机查远程 k8s 环境日志、进 pod / rails console、在容器里跑脚本、换节点；拓扑入 config，个人身份走环境变量
```

核心特性：

- **改动点 → 用例 → 证据追溯链**：design 阶段强制分析前后端 diff，产出改动点清单（D1、D2...），每条用例标注 covers，报告能直接回答"这个改动测没测到"
- **业务语言用例**：用例步骤面向业务（"点击去结算"），执行细节由 AI 适配（selector 失效自动按语义重定位）
- **双环境**：一份 config 同时配本地(local)与测试(test)两套环境，`run` 开头选跑哪个——local 的脚本用本地 runner 跑（任意命令：Rails 用 `bin/rails runner`，也可 node/python），test 的脚本经堡垒机在 pod 里跑；usql 两环境通用
- **DB 级断言**：不只看 UI，usql 直连数据库做表/字段级验证，也可用 runner 做应用内脚本验证（走 ORM/业务逻辑）；测试数据自动清理
- **凭据零落盘**：config 只存环境变量名，密码与连接串永远不进仓库
- **四态状态机**：passed / failed / blocked / skipped，环境故障不算用例失败

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

### 方式一：5 分钟体验（内置 demo）

```bash
node tests/demo/server.js    # 启动被测 demo：http://localhost:8899
```

在 `tests/demo/` 目录下开一个新 Claude Code 会话，依次：

1. `/qa-powers:init` —— 只配 **local** 环境（跳过 test），base_url 填 `http://localhost:8899`，免登录，DB 用 `sqlite://<绝对路径>/demo-db.sqlite`，无后端仓库跳过脚本后端
2. `/qa-powers:design` —— 需求："用户可以把购物车里的测试商品A下单，数量可填；库存要正确扣减"
3. `/qa-powers:run`
4. `/qa-powers:report`

### 方式二：接入你的项目

在**被测项目根目录**开 Claude Code 会话：

1. `/qa-powers:init` —— 收集被测地址、登录方式、前后端仓库路径、DB 连接（均为环境变量名），沉淀登录态
2. `/qa-powers:design` —— 给需求文本 / Jira key / Confluence 链接，生成 `.qa-powers/cases/<模块>/` 用例
3. `/qa-powers:run` —— 执行并产出 `.qa-powers/evidence/<run-id>/`
4. `/qa-powers:report` —— 生成 `.qa-powers/reports/<run-id>.md`

开始前把凭据写入 shell 配置（按环境分变量名，`envs` 里填的就是这些变量名）：

```bash
# local 环境
export QAP_LOCAL_TEST_USER=<本地测试账号>
export QAP_LOCAL_TEST_PASS=<本地测试密码>
export QAP_LOCAL_DB_URL=<本地数据库连接串>
# test 环境（配了才需要）
export QAP_TEST_TEST_USER=<测试环境账号>
export QAP_TEST_TEST_PASS=<测试环境密码>
export QAP_TEST_DB_URL=<测试环境数据库连接串>
export QAP_K8S_JMS_USER=用户名@系统用户   # 配了 k8s 才需要
```

## 目录结构

```
skills/          4 个测试工作流 skill + 1 个远程运维 skill + 1 个入口路由
hooks/           SessionStart 提示 hook
scripts/         validate.sh——插件结构自检
tests/demo/      本地冒烟用被测项目（Node + sqlite3，无其他依赖）
```

## 安全声明

- 凭据只从环境变量读取，`.qa-powers/config.yaml` 只存环境变量名
- 插件绝不 checkout / 修改被测仓库，只读分析
- 浏览器由 playwright-cli 管理，登录态文件 `.qa-powers/auth-state.json` 请勿提交（已默认 gitignore）

## 开发与贡献

```bash
./scripts/validate.sh    # 校验插件结构与 frontmatter
```

见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE)
