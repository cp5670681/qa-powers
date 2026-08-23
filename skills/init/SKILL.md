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
- **多账号**：是否需要按权限测试多个账号（如管理员/普通用户/只读）。需要则为每个账号收集：账号名（如 admin/buyer/viewer）+ 该账号的环境变量名，每个账号沉淀独立登录态文件；单账号时沿用 auth 顶层写法
- 浏览器渠道：系统 Chrome / 系统 Edge / 内置 chromium（默认系统 Chrome，避免不必要的浏览器下载）
- 运行模式：有头 / 无头（默认有头，便于用户观察执行过程）
- 前端仓库绝对路径 + 基线分支（默认 main）
- 后端仓库绝对路径 + 基线分支（默认 main）；无后端可跳过
- DB：驱动类型 + 连接串环境变量名（如 `QAP_DB_URL`）；无 DB 可跳过

## 2. 依赖校验（逐项执行，失败给出修复指引）

| 检查 | 命令 | 失败提示 |
|---|---|---|
| playwright-cli | `playwright-cli --version` | `npm install -g @playwright/cli@latest` |
| 浏览器 | 选系统渠道（chrome/msedge）：`playwright-cli open about:blank --browser <渠道> --<模式>` 后 `close`；选 chromium：`playwright-cli install-browser chromium`（幂等） | 系统渠道：检查本机是否安装该浏览器；chromium：`npm install -g @playwright/cli@latest` |
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

输出校验结果清单（✓/✗）+ 提示用户把 `QAP_TEST_USER` / `QAP_TEST_PASS` / `QAP_DB_URL` 加入 shell 配置。全部通过后提示：可以运行 `qa-powers:design` 设计用例了。
