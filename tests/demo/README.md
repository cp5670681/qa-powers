# demo 被测项目（qa-powers 冒烟夹具）

启动：`node server.js` → http://localhost:8899

## 冒烟清单（对 qa-powers 插件，在新 Claude Code 会话中对 demo 目录执行）

1. `/qa-powers:init`——环境多选只勾 local，base_url=http://localhost:8899，跳过登录态，DB 用 `sqlite://<绝对路径>/demo-db.sqlite`，无后端仓库跳过脚本后端
2. `/qa-powers:design`——需求："用户可以把购物车里的测试商品A下单，数量可填；库存要正确扣减"
3. `/qa-powers:run`——应产出 evidence/<run-id>/result.yaml，正常下单 case PASS
4. `/qa-powers:report`——应产出 reports/<run-id>.md，四态统计正确
5. 回放：对同一模块再跑一次 `/qa-powers:run` → 应直接走回放模式（`cases/<模块>/<case-id>.replay.sh` 已生成，不再逐动作 snapshot 探索）；删除某条 `replay.sh` 后重跑 → 该 case 应重新探索并再次生成脚本
6. 反例：手工把 index.html 的按钮文案改掉重跑 → 对应 case FAIL 且报告含预期/实际差异
