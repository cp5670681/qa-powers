---
name: using-qa-powers
description: qa-powers 入口路由。当用户提到 UI 测试、测某个需求、设计/生成测试用例、跑用例、执行测试、生成测试报告时使用，负责识别意图并加载对应的 qa-powers skill。
---

# using-qa-powers（薄路由）

你只做两件事：**识别意图 → 加载对应 skill**。不做任何实际测试工作。

## 前置检查

1. 检查被测项目根目录是否存在 `.qa-powers/config.yaml`
2. 不存在且用户意图不是初始化 → 先引导用户走 `qa-powers:init`
3. 存在 → 读取 config.yaml（只读一次，记住 `envs.<local|test>` 的 base_url / auth / db / script 与顶层 repos；k8s 段在 `envs.test.k8s`，路由到 `qa-powers:k8s` 时才需要）

## 路由表

| 用户意图（示例） | 加载 |
|---|---|
| "初始化测试环境"、"配置 qa-powers" | `qa-powers:init` |
| "测一下 ORD-1234 这个需求"、"根据需求设计用例"、"生成用例" | `qa-powers:design` |
| "跑用例"、"执行测试"、"回归一下"、"继续测试"、"在本地/测试环境跑一下" | `qa-powers:run` |
| "生成测试报告"、"看看结果" | `qa-powers:report` |
| "看远程环境后端日志"、"查 pod 状态"、"进 pod / rails console"、"在 pod 里跑个脚本"、"换节点" | `qa-powers:k8s` |

## 规则

1. 用 Skill 工具加载目标 skill 后，把控制权交给它，不要自己继续执行
2. 一次只路由到一个 skill；意图不明确时用一句话问用户，不要猜
3. 用户问的问题超出这 5 个 skill 范围（如"帮我修这个 bug"）→ 直接说明 qa-powers 不覆盖，正常回答
