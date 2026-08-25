# Contributing to qa-powers

## 项目结构

- `skills/<name>/SKILL.md` —— 每个 skill 一份提示词，YAML frontmatter（name/description/allowed-tools）+ 流程正文
- `hooks/hooks.json` —— Claude Code hooks 配置
- `.claude-plugin/` —— 插件与 marketplace 清单（版本号改动需两处同步；**不 bump 版本用户的 `/plugin update` 会被跳过**）
- `tests/demo/` —— 冒烟夹具，改动 skill 后用它跑一遍四段流程

## 改动流程

1. 改 skill 前先跑 `./scripts/validate.sh`，改完再跑一次（JSON 与 frontmatter 合法性；需 jq 或 python3 任一）
2. 用 demo 冒烟：`node tests/demo/server.js`，按 `tests/demo/README.md` 清单走 init → design → run → report
3. 真实项目回归一次（建议保留一个内部实战记录作对照，**该记录不入库**）
4. 提交信息用约定式前缀：`feat:` / `fix:` / `docs:` / `test:`

## 写 skill 的约定

- 流程步骤可执行、可判定：每一步都是 AI 能直接照做的动作，不写愿景
- 硬约束与流程分开：违反即执行错误的规则放「硬约束」节
- 用例/报告模板改动要保持向后兼容：老 evidence 的 result.yaml 结构不能破坏 report 解析
- 严禁在文档与示例中放真实凭据、内网地址；示例一律用占位符（如 `<明文>`、`<连接串明文>`）

## 安全红线

- 不提交任何真实账号、密码、DB 连接串、内网主机名
- `docs/guides/`（内部实战记录）已在 .gitignore，永远不要移出忽略名单
- 发现历史泄露：先轮换凭据，再清理历史
