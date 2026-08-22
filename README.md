# qa-powers

AI 驱动的 UI 自动化测试技能库（Claude Code 插件）。

> **AI 负责思考，工具负责执行，Evidence 负责证明。**

## 工作流

需求（文本/Jira/Confluence）→ `/qa-powers:design` 用例 → `/qa-powers:run` 执行
（playwright-cli 驱动有头浏览器 + usql 造数/验证）→ `/qa-powers:report` 报告

## 安装

```bash
/plugin marketplace add <本仓库>
/plugin install qa-powers
```

前置依赖：`npm install -g @playwright/cli@latest`、usql、环境变量 QAP_TEST_USER / QAP_TEST_PASS / QAP_DB_URL。

## 快速开始

在被测项目根目录：

1. `/qa-powers:init` —— 初始化 `.qa-powers/` 配置与登录态
2. `/qa-powers:design` —— 给需求文本或 Jira key，生成用例
3. `/qa-powers:run` —— 执行用例，产出 evidence
4. `/qa-powers:report` —— 生成报告

## 设计文档

见 `docs/specs/`。MVP 边界与后续演进（explore/stabilize/debug）见设计文档"后续演进"节。
