---
name: init
description: 初始化 qa-powers 测试环境。生成 .qa-powers/config.yaml 与目录骨架，配置本地(local)与/或测试(test)两套环境，校验 playwright-cli/usql/代码仓库/数据库/登录态/脚本执行后端可用，并沉淀登录态。用户说"初始化测试环境"或首次使用 qa-powers 时使用。
allowed-tools: Bash(playwright-cli:*), Bash(usql:*), Bash(git:*), Bash(mkdir:*), Bash(ssh:*), Bash(test:*), Bash(which:*), Bash(ls:*), Bash(grep:*), Bash(jq:*), Bash(awk:*), Bash(bash:*), Read, Write, Edit, AskUserQuestion
---

# init：初始化测试环境

在**被测项目根目录**（不是 qa-powers 插件仓库）执行以下流程。

config 可同时配**本地(local)**与**测试(test)**两套环境，初始化时**多选**要配的环境、一次配齐，之后换环境由 `run` 开头选择、无需重新 init。共享项（浏览器、代码仓库路径）只收一次；环境专属项（base_url、登录、DB、脚本执行后端）按环境分别收集。允许只配一个环境。凭据（账号密码、DB 连接串、JMS 身份）**明文存入 config**，后续无需设置环境变量；init 会把敏感文件写入被测项目 `.gitignore` 防止误提交。

**提问一律用中文**：所有 AskUserQuestion 的 question、header、选项 label 与 description 都用中文（base_url、DB、runner 等技术名词可保留英文）。

## 0. 已有 config 时走增量模式

`.qa-powers/config.yaml` 已存在 → **不重新初始化**：

1. 读出现有配置，列给用户看（注意脱敏，只显示结构不显示值）
2. **旧结构无法增量** → 说明需重跑 init 重新收集，先确认没有需要保留的手工改动再覆盖：① env/base_url/db/k8s 在顶层、无 `envs` 段；② 凭据字段是 `*_env` 环境变量名写法（现已改为明文直存）
3. AskUserQuestion 确认本次要补哪些**缺失的段**（如 test 环境、k8s、notes——顶层与各环境 `notes` 键缺失都算缺失段，可增量补，不算改动已有段；`repos.backend.type` 缺失时也按第 1 节探测补上）；已有段一律不再收集、不改动
4. 只执行与缺失段相关的收集与校验；第 4 步写文件时**合并写入**——保留全部已有内容，仅追加/更新本次收集的段，禁止整份重写
5. 目录骨架（第 3 步）`mkdir -p` 幂等，照常执行

## 1. 交互式收集信息（AskUserQuestion，一次一个问题）

**共享项（只收一次）**：

- 浏览器渠道：**先探测系统已装浏览器**（Linux/WSL：`which google-chrome google-chrome-stable msedge`；macOS：`ls /Applications | grep -E "Google Chrome|Microsoft Edge"`），探测到就直接用系统渠道（chrome/msedge，**不下载任何浏览器**）；都没有才选内置 chromium（需下载）
- 运行模式：有头 / 无头（默认有头，便于观察执行过程）
- 前端仓库绝对路径 + 基线分支（**探测默认分支**，main/master 自动识别：`git -C <path> symbolic-ref --short refs/remotes/origin/HEAD` 输出 `origin/main` 则取 `main`；探测不出（无 remote HEAD 引用）或用户想用非默认基线（如 develop）→ AskUserQuestion 问）
- 后端仓库绝对路径 + 基线分支（同上探测）；无后端可跳过
- **后端项目类型（配了后端仓库才收）**：先探测后端仓库根目录——`Gemfile` → rails、`package.json` → node、`pyproject.toml`/`requirements.txt`/`manage.py` → python；都不是或不确定 → AskUserQuestion 从 rails/node/python/other 里选。类型写入 `repos.backend.type`，后续各 skill 按它分派提示（runner 建议、schema 定义位置、密码可读的配置文件）
- **系统特殊注意点（notes，可选，全环境共享）**：收完共享项后问一句"这套被测系统有没有所有环境都适用的注意点"（如：列表页时间统一显示 UTC 断言先换算、导出有全局限流）；用户逐条说出则写入顶层 `notes`（自由文本列表，两环境共享），与各环境专属 notes 并存、冲突时以环境专属为准；没有则不写该键

**环境选择（共享项收完后、问 base_url 之前；AskUserQuestion 多选）**：要配置哪些环境？local / test。选中几个就配几个——都选则一次 init 配齐双环境，之后换环境由 `run` 开头选择，无需重新 init。未选中的直接跳过（`envs` 只写选中的）。

**密码收集方式（账号密码、DB 密码、JMS 身份通用）**：AskUserQuestion 的选项要求 ≥2 项且答案会留在对话里，**不要**为收密码凑选项（"Enter Password..."之类）；改用以下顺序——① 被测项目已有本地配置文件里能读到的直接读（按项目类型找：rails 看 `config/database.yml` 等、node/python 看 `.env`，读前告知用户取自哪里）；② 读不到就问用户要非敏感项（用户名等），密码请用户**直接在下一条消息里明文给**；同一批账号密码相同时问一句"是否同主账号密码"。

**local 环境（base_url=本地地址，如 http://localhost:3000）**：

- base_url
- 登录方式（用户名密码表单 / 免登录）→ **主账号**（大部分用例都用它）：账号名（如 admin）+ 用户名、密码（明文收集，直接写入 config，作为 `auth.default`）
- 权限类需求的多账号**不在 init 收集**：`qa-powers:design` 遇权限控制需求时查库发现账号、引导补密码，增量写入 config 的 `auth.accounts`
- DB：**多库探测收集**——先读后端仓库数据库配置（按 `repos.backend.type`：rails 看 `config/database.yml` 各环境段、node 看 `.env`/prisma 的 `DATABASE_URL*`、python 看 settings/.env），列出代码里出现的所有库，逐个归纳用途说明（哪个是主业务库=默认库、哪个是已发布/只读库、哪个是日志/分析库）。默认库写 `db.url`，其余库用语义别名写 `db.dbs`（`{ url, desc }`，desc 写明"哪些情况用这个库"）。代码里只有单库或读不到 → 只收 `db.url`；无 DB 可跳过。密码含特殊字符需 URL 编码（同 test 环境）
- 脚本执行后端：本地 runner（任意命令，在本地后端仓库目录内执行；rails 用 `bin/rails runner`、node 用 `node`、python 用 `python`）；无后端仓库则跳过
- **环境特殊注意点（notes，可选）**：收完上述各项后问一句"这个环境测试执行时有没有要特别注意的点"（常见如：登录页令牌/多因子字段留空不填、某个库是只读从库禁止写入、列表页数据量大需先加筛选）；用户逐条说出则原样写入该环境 `notes`（自由文本列表，条目含英文冒号+空格时整体加引号，防止 YAML 解析成 map）；没有则不写该键

**test 环境（base_url=测试环境地址）**：

- base_url
- 登录方式 + 账号（同上）
- DB：连接串（明文），多库探测收集同 local——**代码配置只用来列出有哪些库、归纳各库用途说明，连接串一律以用户给的测试环境真实连接串为准**（代码里的 production 段可能是真实生产库，不能照抄）；无 DB 可跳过。**密码含特殊字符（`& ! # ? %` 等）必须 URL 编码**（如 `&`→`%26`），否则连接报 bad connection
- 脚本执行后端固定 `k8s`：
  - JMS 通道：**优先让用户直接给完整四段身份串** `用户名@系统用户@资产IP@堡垒机域名`（如 `alice@root@172.16.4.23@jump.example.com`——用户通常能从既有命令或同事的脚本里拷到完整串），从串中解析出 user（前两段）、host（末段）、默认节点 IP（第三段）；**完整串不含端口，端口（如 22222）单独收**；用户只给零散信息时再分开收集域名+端口+JMS 个人身份
  - 节点表（节点名 → 资产 IP）+ 默认节点：多节点时逐个收；单节点可只写一条。**用途**：k8s 操作时拼完整通道串 `user@节点IP@host`、换节点时按表取 IP——不是摆设，别写占位值
  - 应用列表，每个应用收：namespace、容器名、pod 名匹配正则（主 pod 全名长度固定，按长度锚定以排除衍生 pod，如 `^research.{,17}$`）、应用目录（pod 工作目录已是应用目录时留空）、脚本执行器（任意命令，Rails 用 `bin/rails runner`，非 Rails 用 node/python 等）
  - **script.app**：跑数据脚本（造数/清理/验证）归属的应用，取上面 apps 的某个键
- 环境特殊注意点（notes，可选）：收集方式同 local

## 2. 依赖校验（逐项执行，失败给出修复指引）

| 检查 | 命令 | 失败提示 |
|---|---|---|
| playwright-cli | `playwright-cli --version` | `npm install -g @playwright/cli@latest` |
| 浏览器 | 探测（Linux/WSL）：`which google-chrome google-chrome-stable msedge`；（macOS）：`ls /Applications \| grep -E "Google Chrome\|Microsoft Edge"`；有 → `playwright-cli open about:blank --browser <chrome\|msedge> --<模式>` 后 `close`；无系统浏览器才 `playwright-cli install-browser chromium`（幂等，会下载） | 系统浏览器在但打不开：检查版本与权限；chromium 下载失败：确认网络后重试 |
| usql | `usql --version` | 到 https://github.com/xo/usql/releases 下对应平台二进制（macOS brew 构建可能失败，不推荐） |
| 前端仓库 | `git -C <path> rev-parse --is-inside-work-tree` | 检查路径 |
| 后端仓库 | 同上（配置了才查） | 同上 |
| 每环境 DB 连接 | `usql "<对应 envs.<env>.db.url>" -c 'select 1'`；配了 `db.dbs` 时每个别名库也 `usql "<dbs.<别名>.url>" -c 'select 1'` | 检查连接串与网络；报 bad connection/driver 错先查密码特殊字符是否漏 URL 编码（`&`→`%26` 等） |
| 本地 runner（local 配了 script.runner 才查） | `cd <repos.backend.path> && <envs.local.script.runner> <最小测试脚本>`（按 type：rails `-e 'puts 1'`、node `-e 'console.log(1)'`、python `-c 'print(1)'`） | runner 不存在/不能跑：核对 runner 路径与后端目录 |
| k8s 通道（test 配了才查） | 校验 `envs.test.k8s.jms.user` 非空；**用完整四段串实测一次**（不要只查字段非空）：<br>`ssh -p <port> '<user>@<default_node 的 IP>@<host>' 'kubectl get pods -n <某 app 的 namespace> \| head -3'`<br>能列出 pod 即通 | 核对四段格式（`用户名@系统用户@资产IP@堡垒机域名`，缺一段都连不上）；**认证失败别连续重试——会锁号**，逐段核对后最多再试一次 |

## 3. 生成目录骨架

```bash
mkdir -p .qa-powers/cases .qa-powers/evidence .qa-powers/reports
```

**gitignore 防泄漏（必做）**：目标是 `.qa-powers/config.yaml` 与 `.qa-powers/auth-*.json`（config 明文存凭据、登录态含会话 cookie，绝不能提交）被忽略——**先检查是否已有更宽规则**（如整目录 `.qa-powers`、`.qa-powers/*`）：`grep -n "qa-powers" .gitignore`，已有宽规则覆盖即跳过写入；没有则追加这两行（无 `.gitignore` 则创建）；被测项目不是 git 仓库时跳过本步并在收尾提示。**已被 git 跟踪的文件加 .gitignore 不生效**：`git ls-files --error-unmatch <文件>` 能查到时，提示用户确认后 `git rm --cached <文件>` 移出跟踪。cases/evidence/reports 不含凭据，可按团队需要提交。

## 4. 写 .qa-powers/config.yaml（用收集到的值；已有 config 时按第 0 节增量合并，只动本次收集的段）

```yaml
plugin_version: <从 $CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json 读（jq -r '.version' 或 awk）；仅本插件安装后 config 与流程核对版本用，不参与任何流程逻辑>
browser:                 # 两环境共享
  channel: chrome        # chrome | msedge | chromium
  headed: true           # 有头模式（run 以此为浏览器模式问题的默认值，执行时仍可现场切换）
repos:                   # 共享：本地 checkout
  frontend: { path: <收集值>, base: <探测的默认分支> }   # base 用第 1 节探测出的默认分支（main/master）
  backend:  { path: <收集值>, base: <探测的默认分支>, type: rails }   # 无后端则删除此行；type=rails|node|python|other（第 1 节探测写入）
notes:                   # 可选：全环境共享的系统注意点（第 1 节问出才写，逐条自由文本；没有则删除此段）
  - <如：所有列表页时间显示为 UTC，断言前先换算>
active_env: local        # 所选环境中的第一个（只选 test 时为 test）；run 开头可切换
envs:
  local:
    base_url: <收集值>
    notes:                             # 可选：环境专属注意点（第 1 节问出才写，逐条自由文本；与顶层 notes 并存；没有则删除此段）
      - <如：登录页令牌输入框留空不填，只用账号密码>
    auth:
      default: admin     # 不指定 account 的用例用哪个账号（init 只配这一个主账号）
      accounts:          # 结构固定：key=账号名；免登录可删除整个 auth 段
        admin: { username: <明文>, password: <明文>, state_file: .qa-powers/auth-local-admin.json }
        # 权限测试账号由 design 发现后增量追加（key=账号名，如 buyer/readonly），init 不收集
    db:                                # 无 DB 则删除整个 db 段
      url: <默认库连接串明文>            # 主库；usql 不带别名时默认用
      dbs:                             # 跨库时追加，key=语义别名；desc 说明哪些情况用这个库
        published: { url: <连接串明文>, desc: <用途说明，如"已发布内容库——查线上已发布数据"> }
    script:              # 无后端仓库则删除整个 script 段
      runner: bin/rails runner   # 本地脚本执行器，任意命令（Node: node、Python: python、Rails: bin/rails runner）
  test:
    base_url: <收集值>
    notes:                             # 可选：环境专属注意点，同 local；没有则删除此段
      - <如：登录页令牌输入框留空不填，只用账号密码>
    auth:
      default: admin
      accounts:
        admin: { username: <明文>, password: <明文>, state_file: .qa-powers/auth-test-admin.json }
    db:
      url: <默认库连接串明文>            # 主库；usql 不带别名时默认用
      dbs:                             # 跨库时追加，同 local
        published: { url: <连接串明文>, desc: <用途说明> }
    script:
      app: research      # 跑数据脚本归属的应用（取下方 apps 的键；脚本经堡垒机在该 app 的 pod 里执行）
    k8s:
      jms:
        host: <堡垒机域名>
        port: 22222
        user: <用户名@系统用户>  # 明文，值形如 alice@root；实际连接要拼完整四段：user@节点IP@host（见 k8s skill）
      default_node: <节点名>    # 默认用的节点，对应 nodes 里的键
      nodes: { <节点名>: <资产IP>, ... }   # 拼完整通道串/换节点时取 IP 用，禁止写占位值
      apps:
        <app>:
          namespace: <收集值>
          container: <收集值>
          pod_pattern: "<按主 pod 全名长度锚定的正则>"
          workdir: <应用目录>    # pod 工作目录已是应用目录时可留空；模板仅在非空时加 cd
          runner: <脚本执行器>        # 任意命令（rails: bin/rails runner、node: node、python: python）；应用无脚本执行能力才删除此行
```

注意：config **明文**存凭据（免去维护环境变量），必须已被 `.gitignore` 覆盖（见第 3 步）。登录态文件按 `auth-<env>-<account>.json` 分文件。老 config 缺 `repos.backend.type`：design/run 从已配的 runner 命令推断（含 rails→rails、node→node、python→python），推断不出按 other 处理，也可重跑 init 增量补上。`plugin_version` 记录写文件时插件的版本（从 `$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json` 读）；后续各流程（design/run/report/k8s）会核对它——若与当前插件 major.minor 不同（大/小版本升级）会提醒重跑 init，仅 patch 差异不提醒，因此**每次 init（含第 0 节增量合并）都把 `plugin_version` 更新为当前插件版本**。

## 5. 沉淀登录态（免登录跳过；对 config 已配账号逐个做——init 后即主账号；design 后续追加的权限账号由 run 首次用到时自动登录沉淀，无需手工）

对每个环境的每个账号：

1. `playwright-cli open <该环境 base_url> --browser <config的channel> --<headed时加 --headed>`
2. `playwright-cli snapshot` 找到登录入口，引导完成登录（凭据从 config 该账号的 username/password 读，不在对话里回显密码；顶层 `notes` 与该环境 `notes` 有登录相关注意点——如令牌留空——按 notes 执行）
3. 登录成功后：`playwright-cli state-save <该账号的 state_file>`
4. `playwright-cli close`（每个账号登录完关一次，避免会话串号）

多账号提示：不同环境的同名账号（local-admin / test-admin）要用不同 state_file。

## 6. 收尾

输出校验结果清单（✓/✗）+ 确认 `.gitignore` 已覆盖 config 与登录态文件（凭据已明文入 config，无需设置环境变量）。全部通过后提示：可以运行 `qa-powers:design` 设计用例了；`qa-powers:run` 开头会确认用哪个环境。
