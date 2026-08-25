---
name: init
description: 初始化 qa-powers 测试环境。生成 .qa-powers/config.yaml 与目录骨架，配置本地(local)与/或测试(test)两套环境，校验 playwright-cli/usql/代码仓库/数据库/登录态/脚本执行后端可用，并沉淀登录态。用户说"初始化测试环境"或首次使用 qa-powers 时使用。
allowed-tools: Bash(playwright-cli:*), Bash(usql:*), Bash(git:*), Bash(mkdir:*), Bash(ssh:*), Bash(test:*), Read, Write, Edit, AskUserQuestion
---

# init：初始化测试环境

在**被测项目根目录**（不是 qa-powers 插件仓库）执行以下流程。

config 可同时配**本地(local)**与**测试(test)**两套环境，`run` 开头选跑哪个。共享项（浏览器、代码仓库路径）只收一次；环境专属项（base_url、登录、DB、脚本执行后端）按环境分别收集。允许只配一个环境（跳过另一个）。

## 0. 已有 config 时走增量模式

`.qa-powers/config.yaml` 已存在 → **不重新初始化**：

1. 读出现有配置，列给用户看（注意脱敏，只显示结构不显示值）
2. **旧结构（env/base_url/db/k8s 在顶层、无 `envs` 段）无法增量** → 说明需重跑 init 生成新结构；先确认没有需要保留的手工改动再覆盖
3. AskUserQuestion 确认本次要补哪些**缺失的段**（如 test 环境、k8s）；已有段一律不再收集、不改动
4. 只执行与缺失段相关的收集与校验；第 4 步写文件时**合并写入**——保留全部已有内容，仅追加/更新本次收集的段，禁止整份重写
5. 目录骨架（第 3 步）`mkdir -p` 幂等，照常执行

## 1. 交互式收集信息（AskUserQuestion，一次一个问题）

**共享项（只收一次）**：

- 浏览器渠道：**先探测系统已装浏览器**（Linux/WSL：`which google-chrome google-chrome-stable msedge`；macOS：`ls /Applications | grep -E "Google Chrome|Microsoft Edge"`），探测到就直接用系统渠道（chrome/msedge，**不下载任何浏览器**）；都没有才选内置 chromium（需下载）
- 运行模式：有头 / 无头（默认有头，便于观察执行过程）
- 前端仓库绝对路径 + 基线分支（默认 main）
- 后端仓库绝对路径 + 基线分支（默认 main）；无后端可跳过

**local 环境（base_url=本地地址，如 http://localhost:3000）**：

- base_url
- 登录方式（用户名密码表单 / 免登录）→ 用户名、密码的**环境变量名**（不收明文，提示用户写入 shell 配置）
- 多账号（是否按权限测试多个账号）。需要则每账号收：账号名（如 admin/buyer）+ 环境变量名，每账号独立登录态文件；单账号沿用 auth 顶层写法
- DB：驱动类型 + 连接串环境变量名（如 `QAP_LOCAL_DB_URL`）；无 DB 可跳过
- 脚本执行后端：本地 runner（任意命令，在本地后端仓库目录内执行；Rails 用 `bin/rails runner`、Node 用 `node`、Python 用 `python`）；无后端仓库则跳过

**test 环境（base_url=测试环境地址）**：

- base_url
- 登录方式 + 账号（同上；环境变量名不能与 local 混用，如 `QAP_TEST_ADMIN_USER`）
- DB：连接串环境变量名（如 `QAP_TEST_DB_URL`）；无 DB 可跳过
- 脚本执行后端固定 `k8s`：
  - 堡垒机域名 + 端口；JMS 个人身份的**环境变量名**（值形如 `用户名@系统用户`，不收明文）
  - 节点表（节点名 → 资产 IP）+ 默认节点
  - 应用列表，每个应用收：namespace、容器名、pod 名匹配正则（主 pod 全名长度固定，按长度锚定以排除衍生 pod，如 `^research.{,17}$`）、应用目录、脚本执行器（任意命令，Rails 用 `bin/rails runner`，非 Rails 用 node/python 等）
  - **script.app**：跑数据脚本（造数/清理/验证）归属的应用，取上面 apps 的某个键

**环境数量**：收集完一个环境后问是否也配另一个（跳过则 `envs` 只写一个环境）。

## 2. 依赖校验（逐项执行，失败给出修复指引）

| 检查 | 命令 | 失败提示 |
|---|---|---|
| playwright-cli | `playwright-cli --version` | `npm install -g @playwright/cli@latest` |
| 浏览器 | 探测（Linux/WSL）：`which google-chrome google-chrome-stable msedge`；（macOS）：`ls /Applications \| grep -E "Google Chrome\|Microsoft Edge"`；有 → `playwright-cli open about:blank --browser <chrome\|msedge> --<模式>` 后 `close`；无系统浏览器才 `playwright-cli install-browser chromium`（幂等，会下载） | 系统浏览器在但打不开：检查版本与权限；chromium 下载失败：确认网络后重试 |
| usql | `usql --version` | `brew install usql` |
| 前端仓库 | `git -C <path> rev-parse --is-inside-work-tree` | 检查路径 |
| 后端仓库 | 同上（配置了才查） | 同上 |
| 每环境 DB 连接 | `usql "$<对应 envs.<env>.db.url_env>" -c 'select 1'` | 检查环境变量与网络 |
| 本地 runner（local 配了 script.runner 才查） | `cd <repos.backend.path> && <envs.local.script.runner> <最小测试脚本>`（Rails 可 `-e 'puts 1'`） | runner 不存在/不能跑：核对 runner 路径与后端目录 |
| 环境变量存在 | `test -n "$QAP_LOCAL_TEST_USER"` 等（按收集到的每个变量名） | 提示用户 export 后重试 |
| k8s 通道（test 配了才查） | `test -n "$QAP_K8S_JMS_USER"`；连通性：按 `qa-powers:k8s` 的 pod 解析模板查一次任一应用的 pod 名 | 核对四段格式与环境变量；**认证失败别连续重试——会锁号** |

## 3. 生成目录骨架

```bash
mkdir -p .qa-powers/cases .qa-powers/evidence .qa-powers/reports
```

## 4. 写 .qa-powers/config.yaml（用收集到的值；已有 config 时按第 0 节增量合并，只动本次收集的段）

```yaml
browser:                 # 两环境共享
  channel: chrome        # chrome | msedge | chromium
  headed: true           # 有头模式
repos:                   # 共享：本地 checkout
  frontend: { path: <收集值>, base: <基线分支> }
  backend:  { path: <收集值>, base: <基线分支> }   # 无则删除此行
active_env: local        # 第一个配置的环境；run 开头可切换
envs:
  local:
    base_url: <收集值>
    auth:
      default: admin     # 不指定 account 的用例用哪个账号
      accounts:          # 单账号可简写为 { username_env, password_env, state_file }
        admin: { username_env: QAP_LOCAL_ADMIN_USER, password_env: QAP_LOCAL_ADMIN_PASS, state_file: .qa-powers/auth-local-admin.json }
        buyer: { username_env: QAP_LOCAL_BUYER_USER, password_env: QAP_LOCAL_BUYER_PASS, state_file: .qa-powers/auth-local-buyer.json }
    db: { url_env: QAP_LOCAL_DB_URL }      # 无则删除整个 db 段
    script:              # 无后端仓库则删除整个 script 段
      runner: bin/rails runner   # 本地脚本执行器，任意命令（Node: node、Python: python、Rails: bin/rails runner）
  test:
    base_url: <收集值>
    auth:
      default: admin
      accounts:
        admin: { username_env: QAP_TEST_ADMIN_USER, password_env: QAP_TEST_ADMIN_PASS, state_file: .qa-powers/auth-test-admin.json }
    db: { url_env: QAP_TEST_DB_URL }
    script:
      app: research      # 跑数据脚本归属的应用（取下方 apps 的键；脚本经堡垒机在该 app 的 pod 里执行）
    k8s:
      jms:
        host: <堡垒机域名>
        port: 22222
        user_env: QAP_K8S_JMS_USER   # 值形如 用户名@系统用户，只存变量名不存明文
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

注意：config 里只存**环境变量名**，不存明文。登录态文件按 `auth-<env>-<account>.json` 分文件。

## 5. 沉淀登录态（免登录跳过；每个环境每个账号）

对每个环境的每个账号：

1. `playwright-cli open <该环境 base_url> --browser <config的channel> --<headed时加 --headed>`
2. `playwright-cli snapshot` 找到登录入口，引导完成登录（凭据从该账号的环境变量读，不要让用户在对话里发明文）
3. 登录成功后：`playwright-cli state-save <该账号的 state_file>`
4. `playwright-cli close`（每个账号登录完关一次，避免会话串号）

多账号提示：各账号凭据环境变量名不能相同；不同环境的同名账号（local-admin / test-admin）也要用不同变量名与不同 state_file。

## 6. 收尾

输出校验结果清单（✓/✗）+ 提示用户把各环境的环境变量（用户名/密码/DB URL；test 配了 k8s 则加 `QAP_K8S_JMS_USER`）加入 shell 配置。全部通过后提示：可以运行 `qa-powers:design` 设计用例了；`qa-powers:run` 开头会确认用哪个环境。
