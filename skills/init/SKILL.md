---
name: init
description: 初始化 qa-powers 测试环境。生成 .qa-powers/config.yaml 与目录骨架，校验 playwright-cli/usql/代码仓库/数据库/登录态可用，并沉淀登录态。用户说"初始化测试环境"或首次使用 qa-powers 时使用。
allowed-tools: Bash(playwright-cli:*), Bash(usql:*), Bash(git:*), Bash(mkdir:*), Bash(ssh:*), Bash(test:*), Read, Write, Edit, AskUserQuestion
---

# init：初始化测试环境

在**被测项目根目录**（不是 qa-powers 插件仓库）执行以下流程。

## 0. 已有 config 时走增量模式

`.qa-powers/config.yaml` 已存在 → **不重新初始化**：

1. 读出现有配置，列给用户看（注意脱敏，只显示结构不显示值）
2. AskUserQuestion 确认本次要补哪些**缺失的段**（如 k8s）；已有段（base_url / auth / repos / db 等）一律不再收集、不改动
3. 只执行与缺失段相关的收集与校验；第 4 步写文件时**合并写入**——保留全部已有内容，仅追加/更新本次收集的段，禁止整份重写
4. 目录骨架（第 3 步）`mkdir -p` 幂等，照常执行

## 1. 交互式收集信息（AskUserQuestion，一次一个问题）

- base_url（被测系统地址）
- 登录方式（用户名密码表单 / 免登录）→ 用户名、密码的**环境变量名**（不收明文，提示用户写入 shell 配置）
- **多账号**：是否需要按权限测试多个账号（如管理员/普通用户/只读）。需要则为每个账号收集：账号名（如 admin/buyer/viewer）+ 该账号的环境变量名，每个账号沉淀独立登录态文件；单账号时沿用 auth 顶层写法
- 浏览器渠道：**先探测系统已装浏览器**（Linux/WSL：`which google-chrome google-chrome-stable msedge`；macOS：`ls /Applications | grep -E "Google Chrome|Microsoft Edge"`），探测到就直接用系统渠道（chrome/msedge，**不下载任何浏览器**）；都没有才选内置 chromium（需下载）
- 运行模式：有头 / 无头（默认有头，便于用户观察执行过程）
- 前端仓库绝对路径 + 基线分支（默认 main）
- 后端仓库绝对路径 + 基线分支（默认 main）；无后端可跳过
- DB：驱动类型 + 连接串环境变量名（如 `QAP_DB_URL`）；无 DB 可跳过
- **远程 k8s 环境（可选，不需要则跳过，config 不写 k8s 段）**：堡垒机域名 + 端口；JMS 个人身份的**环境变量名**（值形如 `用户名@系统用户`，不收明文）；节点表（节点名 → 资产 IP）+ 默认节点；应用列表，每个应用收集：namespace、容器名、pod 名匹配正则（主 pod 全名长度固定，按长度锚定以排除衍生 pod，如 `^research.{,17}$`）、应用目录、脚本执行器（如 `bin/rails runner`，非 Rails 可空）

## 2. 依赖校验（逐项执行，失败给出修复指引）

| 检查 | 命令 | 失败提示 |
|---|---|---|
| playwright-cli | `playwright-cli --version` | `npm install -g @playwright/cli@latest` |
| 浏览器 | 探测（Linux/WSL）：`which google-chrome google-chrome-stable msedge`；（macOS）：`ls /Applications \| grep -E "Google Chrome\|Microsoft Edge"`；有 → `playwright-cli open about:blank --browser <chrome\|msedge> --<模式>` 后 `close`；无系统浏览器才 `playwright-cli install-browser chromium`（幂等，会下载） | 系统浏览器在但打不开：检查版本与权限；chromium 下载失败：确认网络后重试 |
| usql | `usql --version` | `brew install usql` |
| 前端仓库 | `git -C <path> rev-parse --is-inside-work-tree` | 检查路径 |
| 后端仓库 | 同上（配置了才查） | 同上 |
| DB 连接 | `usql "$QAP_DB_URL" -c 'select 1'` | 检查环境变量与网络 |
| 环境变量存在 | `test -n "$QAP_TEST_USER"` 等 | 提示用户 export 后重试 |
| k8s 通道（配置了才查） | `test -n "$QAP_K8S_JMS_USER"`；连通性：按 `qa-powers:k8s` 的 pod 解析模板查一次任一应用的 pod 名 | 核对四段格式与环境变量；**认证失败别连续重试——会锁号** |

## 3. 生成目录骨架

```bash
mkdir -p .qa-powers/cases .qa-powers/evidence .qa-powers/reports
```

## 4. 写 .qa-powers/config.yaml（用收集到的值；已有 config 时按第 0 节增量合并，只动本次收集的段）

```yaml
env: test
base_url: <收集值>
browser:
  channel: chrome        # chrome | msedge | chromium
  headed: true           # 有头模式
auth:                    # 单账号写法（向后兼容）
  username_env: QAP_TEST_USER
  password_env: QAP_TEST_PASS
  state_file: .qa-powers/auth-state.json
# 多账号写法：auth 顶层只有 default + accounts
# auth:
#   default: admin       # 不指定 account 的用例用哪个账号
#   accounts:
#     admin: { username_env: QAP_ADMIN_USER, password_env: QAP_ADMIN_PASS, state_file: .qa-powers/auth-admin.json }
#     buyer: { username_env: QAP_BUYER_USER, password_env: QAP_BUYER_PASS, state_file: .qa-powers/auth-buyer.json }
repos:
  frontend: { path: <收集值>, base: <基线分支> }
  backend:  { path: <收集值>, base: <基线分支> }   # 无则删除此行
db:
  url_env: QAP_DB_URL   # 无则删除整个 db 段
k8s:                    # 无远程环境则删除整个 k8s 段
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
      runner: <脚本执行器>        # 非 Rails 应用删除此行
```

注意：config 里只存**环境变量名**，不存明文。

## 5. 沉淀登录态（免登录跳过）

对每个账号（单账号即默认账号）：

1. `playwright-cli open <base_url> --browser <config的channel> --<headed时加 --headed>`
2. `playwright-cli snapshot` 找到登录入口，引导完成登录（凭据从该账号的环境变量读，不要让用户在对话里发明文）
3. 登录成功后：`playwright-cli state-save <该账号的 state_file>`
4. `playwright-cli close`（每个账号登录完关一次，避免会话串号）

多账号提示：各账号凭据环境变量名不能相同；登录态文件按账号分文件存。

## 6. 收尾

输出校验结果清单（✓/✗）+ 提示用户把 `QAP_TEST_USER` / `QAP_TEST_PASS` / `QAP_DB_URL`（配置了 k8s 则加 `QAP_K8S_JMS_USER`）加入 shell 配置。全部通过后提示：可以运行 `qa-powers:design` 设计用例了。
