---
name: init
description: 初始化 qa-powers 测试环境。生成 .qa-powers/config.yaml 与目录骨架，配置本地(local)与/或测试(test)两套环境，校验 playwright-cli/usql/代码仓库/数据库/登录态/脚本执行后端可用，并沉淀登录态。用户说"初始化测试环境"或首次使用 qa-powers 时使用。
allowed-tools: Bash(playwright-cli:*), Bash(usql:*), Bash(git:*), Bash(mkdir:*), Bash(ssh:*), Bash(test:*), Bash(which:*), Bash(ls:*), Bash(grep:*), Read, Write, Edit, AskUserQuestion
---

# init：初始化测试环境

在**被测项目根目录**（不是 qa-powers 插件仓库）执行以下流程。

config 可同时配**本地(local)**与**测试(test)**两套环境，初始化时**多选**要配的环境、一次配齐，之后换环境由 `run` 开头选择、无需重新 init。共享项（浏览器、代码仓库路径）只收一次；环境专属项（base_url、登录、DB、脚本执行后端）按环境分别收集。允许只配一个环境。凭据（账号密码、DB 连接串、JMS 身份）**明文存入 config**，后续无需设置环境变量；init 会把敏感文件写入被测项目 `.gitignore` 防止误提交。

## 0. 已有 config 时走增量模式

`.qa-powers/config.yaml` 已存在 → **不重新初始化**：

1. 读出现有配置，列给用户看（注意脱敏，只显示结构不显示值）
2. **旧结构无法增量** → 说明需重跑 init 重新收集，先确认没有需要保留的手工改动再覆盖：① env/base_url/db/k8s 在顶层、无 `envs` 段；② 凭据字段是 `*_env` 环境变量名写法（现已改为明文直存）
3. AskUserQuestion 确认本次要补哪些**缺失的段**（如 test 环境、k8s）；已有段一律不再收集、不改动
4. 只执行与缺失段相关的收集与校验；第 4 步写文件时**合并写入**——保留全部已有内容，仅追加/更新本次收集的段，禁止整份重写
5. 目录骨架（第 3 步）`mkdir -p` 幂等，照常执行

## 1. 交互式收集信息（AskUserQuestion，一次一个问题）

**共享项（只收一次）**：

- 浏览器渠道：**先探测系统已装浏览器**（Linux/WSL：`which google-chrome google-chrome-stable msedge`；macOS：`ls /Applications | grep -E "Google Chrome|Microsoft Edge"`），探测到就直接用系统渠道（chrome/msedge，**不下载任何浏览器**）；都没有才选内置 chromium（需下载）
- 运行模式：有头 / 无头（默认有头，便于观察执行过程）
- 前端仓库绝对路径 + 基线分支（默认 main）
- 后端仓库绝对路径 + 基线分支（默认 main）；无后端可跳过

**环境选择（共享项收完后、问 base_url 之前；AskUserQuestion 多选）**：要配置哪些环境？local / test。选中几个就配几个——都选则一次 init 配齐双环境，之后换环境由 `run` 开头选择，无需重新 init。未选中的直接跳过（`envs` 只写选中的）。

**local 环境（base_url=本地地址，如 http://localhost:3000）**：

- base_url
- 登录方式（用户名密码表单 / 免登录）→ **主账号**（大部分用例都用它）：账号名（如 admin）+ 用户名、密码（明文收集，直接写入 config，作为 `auth.default`）
- 权限类需求的多账号**不在 init 收集**：`qa-powers:design` 遇权限控制需求时查库发现账号、引导补密码，增量写入 config 的 `auth.accounts`
- DB：驱动类型 + 连接串（明文，如 `postgres://user:pass@localhost/db`）；无 DB 可跳过
- 脚本执行后端：本地 runner（任意命令，在本地后端仓库目录内执行；Rails 用 `bin/rails runner`、Node 用 `node`、Python 用 `python`）；无后端仓库则跳过

**test 环境（base_url=测试环境地址）**：

- base_url
- 登录方式 + 账号（同上）
- DB：连接串（明文）；无 DB 可跳过
- 脚本执行后端固定 `k8s`：
  - 堡垒机域名 + 端口；JMS 个人身份（明文，值形如 `用户名@系统用户`）
  - 节点表（节点名 → 资产 IP）+ 默认节点
  - 应用列表，每个应用收：namespace、容器名、pod 名匹配正则（主 pod 全名长度固定，按长度锚定以排除衍生 pod，如 `^research.{,17}$`）、应用目录、脚本执行器（任意命令，Rails 用 `bin/rails runner`，非 Rails 用 node/python 等）
  - **script.app**：跑数据脚本（造数/清理/验证）归属的应用，取上面 apps 的某个键

## 2. 依赖校验（逐项执行，失败给出修复指引）

| 检查 | 命令 | 失败提示 |
|---|---|---|
| playwright-cli | `playwright-cli --version` | `npm install -g @playwright/cli@latest` |
| 浏览器 | 探测（Linux/WSL）：`which google-chrome google-chrome-stable msedge`；（macOS）：`ls /Applications \| grep -E "Google Chrome\|Microsoft Edge"`；有 → `playwright-cli open about:blank --browser <chrome\|msedge> --<模式>` 后 `close`；无系统浏览器才 `playwright-cli install-browser chromium`（幂等，会下载） | 系统浏览器在但打不开：检查版本与权限；chromium 下载失败：确认网络后重试 |
| usql | `usql --version` | `brew install usql` |
| 前端仓库 | `git -C <path> rev-parse --is-inside-work-tree` | 检查路径 |
| 后端仓库 | 同上（配置了才查） | 同上 |
| 每环境 DB 连接 | `usql "<对应 envs.<env>.db.url>" -c 'select 1'` | 检查连接串与网络 |
| 本地 runner（local 配了 script.runner 才查） | `cd <repos.backend.path> && <envs.local.script.runner> <最小测试脚本>`（Rails 可 `-e 'puts 1'`） | runner 不存在/不能跑：核对 runner 路径与后端目录 |
| k8s 通道（test 配了才查） | 校验 `envs.test.k8s.jms.user` 非空；连通性：按 `qa-powers:k8s` 的 pod 解析模板查一次任一应用的 pod 名 | 核对四段格式；**认证失败别连续重试——会锁号** |

## 3. 生成目录骨架

```bash
mkdir -p .qa-powers/cases .qa-powers/evidence .qa-powers/reports
```

**gitignore 防泄漏（必做）**：确保被测项目 `.gitignore` 包含 `.qa-powers/config.yaml` 与 `.qa-powers/auth-*.json`（config 明文存凭据、登录态含会话 cookie，绝不能提交）；无 `.gitignore` 则创建，已含则跳过；被测项目不是 git 仓库时跳过本步并在收尾提示。**已被 git 跟踪的文件加 .gitignore 不生效**：`git ls-files --error-unmatch <文件>` 能查到时，提示用户确认后 `git rm --cached <文件>` 移出跟踪。cases/evidence/reports 不含凭据，可按团队需要提交。

## 4. 写 .qa-powers/config.yaml（用收集到的值；已有 config 时按第 0 节增量合并，只动本次收集的段）

```yaml
browser:                 # 两环境共享
  channel: chrome        # chrome | msedge | chromium
  headed: true           # 有头模式
repos:                   # 共享：本地 checkout
  frontend: { path: <收集值>, base: <基线分支> }
  backend:  { path: <收集值>, base: <基线分支> }   # 无则删除此行
active_env: local        # 所选环境中的第一个（只选 test 时为 test）；run 开头可切换
envs:
  local:
    base_url: <收集值>
    auth:
      default: admin     # 不指定 account 的用例用哪个账号（init 只配这一个主账号）
      accounts:          # 结构固定：key=账号名；免登录可删除整个 auth 段
        admin: { username: <明文>, password: <明文>, state_file: .qa-powers/auth-local-admin.json }
        # 权限测试账号由 design 发现后增量追加（key=账号名，如 buyer/readonly），init 不收集
    db: { url: <连接串明文> }             # 无则删除整个 db 段
    script:              # 无后端仓库则删除整个 script 段
      runner: bin/rails runner   # 本地脚本执行器，任意命令（Node: node、Python: python、Rails: bin/rails runner）
  test:
    base_url: <收集值>
    auth:
      default: admin
      accounts:
        admin: { username: <明文>, password: <明文>, state_file: .qa-powers/auth-test-admin.json }
    db: { url: <连接串明文> }
    script:
      app: research      # 跑数据脚本归属的应用（取下方 apps 的键；脚本经堡垒机在该 app 的 pod 里执行）
    k8s:
      jms:
        host: <堡垒机域名>
        port: 22222
        user: <用户名@系统用户>  # 明文，值形如 alice@root
      default_node: <节点名>
      nodes: { <节点名>: <资产IP>, ... }
      apps:
        <app>:
          namespace: <收集值>
          container: <收集值>
          pod_pattern: "<按主 pod 全名长度锚定的正则>"
          workdir: <应用目录>
          runner: <脚本执行器>        # 任意命令（Rails: bin/rails runner、Node: node、Python: python）；应用无脚本执行能力才删除此行
```

注意：config **明文**存凭据（免去维护环境变量），必须已被 `.gitignore` 覆盖（见第 3 步）。登录态文件按 `auth-<env>-<account>.json` 分文件。

## 5. 沉淀登录态（免登录跳过；对 config 已配账号逐个做——init 后即主账号；design 后续追加的权限账号由 run 首次用到时自动登录沉淀，无需手工）

对每个环境的每个账号：

1. `playwright-cli open <该环境 base_url> --browser <config的channel> --<headed时加 --headed>`
2. `playwright-cli snapshot` 找到登录入口，引导完成登录（凭据从 config 该账号的 username/password 读，不在对话里回显密码）
3. 登录成功后：`playwright-cli state-save <该账号的 state_file>`
4. `playwright-cli close`（每个账号登录完关一次，避免会话串号）

多账号提示：不同环境的同名账号（local-admin / test-admin）要用不同 state_file。

## 6. 收尾

输出校验结果清单（✓/✗）+ 确认 `.gitignore` 已覆盖 config 与登录态文件（凭据已明文入 config，无需设置环境变量）。全部通过后提示：可以运行 `qa-powers:design` 设计用例了；`qa-powers:run` 开头会确认用哪个环境。
