# 多宿主安装与约定

qa-powers 的正文是 `skills/*/SKILL.md`（Agent Skills 标准）。Claude Code、Codex、Pi 以及其它兼容 harness 读同一套文件。宿主差异只在分发和权限，不复制流程。

## 两套安装（二选一）

**Claude Code plugin**（只读订阅，随版本更新）：

```
/plugin marketplace add https://github.com/cp5670681/qa-powers
/plugin install qa-powers@qa-powers
```

**其它 agent（Codex、Pi、Cursor 等）**：用 [skills.sh](https://skills.sh) 把 skill 文件拷进项目或用户 skill 目录，可勾选子集：

```bash
npx skills@latest add cp5670681/qa-powers
```

安装时可选 skill。`k8s` 仅远程测试环境需要，可跳过。入口路由 `using-qa-powers` 建议始终安装。拷文件后自行编辑；更新用 `npx skills update`。

不要两套同时装，否则每个 skill 会出现两次。

## 插件根与脚本

`scripts/version-check.sh`、`scripts/allow-tools.sh` 在仓库根，不在单个 skill 目录里。

- Claude plugin：`$CLAUDE_PLUGIN_ROOT` 指向插件缓存，hook 与 version-check 直接可用。
- 其它宿主（Codex / Pi 等）：设置 `$QA_POWERS_ROOT` 为本仓库克隆路径。skills.sh 只拷 skill 目录，**不会**带上仓库根的 `scripts/`。
- 版本核对必须带守卫，禁止直接拼 `"$VAR/scripts/..."`（两变量都空会变成 `/scripts/...`）：

```bash
root="${QA_POWERS_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
[ -n "$root" ] && [ -f "$root/scripts/version-check.sh" ] && bash "$root/scripts/version-check.sh" .qa-powers/config.yaml
```

`root` 空或脚本不存在 → 跳过，不阻断。读 `plugin.json` 版本同样：`[ -n "$root" ] && [ -f "$root/.claude-plugin/plugin.json" ]` 才 `jq`，否则不写 `plugin_version`。
- PreToolUse 自动放行只读 usql / playwright-cli **仅 Claude hook**。其它宿主按各自 allowlist 或每次确认。

## 调用其它 skill

写 `Call the Skill tool with "run"`，不要写 `/qa-powers:run`（那是 Claude slash 语法）。Skill 工具一次一个名字。

`k8s` 未安装时不要调用：提示用户补装或改用本机日志。

## 向用户确认

有结构化提问工具（Claude 的 AskUserQuestion 等）就用；没有则普通问答。一次一个问题，中文。
