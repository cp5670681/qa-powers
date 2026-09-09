# Model-invoked vs 可选安装

本仓库 skill **全部 model-invoked**（有触发用 `description`，不加 `disable-model-invocation`）。原因：入口 `using-qa-powers` 必须能 `Call the Skill tool` 把控制权交给 init/design/run/report/k8s。按 Agent Skills 约定，user-invoked skill 不能被其它 skill 调用。

可选发生在**安装层**，不是 invocation 开关：

| skill | 建议 |
|---|---|
| using-qa-powers | 始终装（路由） |
| init, design, run, report | 标准测试环，建议装 |
| k8s | 可选；只用 local、不经堡垒机则可不装 |

Codex 侧每个 skill 带 `agents/openai.yaml`（picker 文案）。全部允许 implicit invocation，与 Claude 的 model-invoked 对齐。
