---
name: k8s
description: 远程 k8s 环境日常操作。用户要看后端日志、查 pod 状态、进 pod 或 rails console、在容器里跑脚本、换节点，或测试执行中疑似远程环境故障需排查时使用；经 JumpServer 堡垒机 ssh 通道访问。
allowed-tools: Bash(ssh:*), Bash(cat:*), Read, AskUserQuestion
---

# k8s：远程 k8s 环境操作（经堡垒机）

## 0. 准备

1. 读 `.qa-powers/config.yaml` 的 `k8s` 段；不存在 → 引导用户运行 `qa-powers:init`
2. 拼装 JMS 通道串（个人身份从环境变量读，不落盘）：

```bash
JMS="${QAP_K8S_JMS_USER}@<k8s.nodes 里目标节点的IP>@<k8s.jms.host>"
```

3. `QAP_K8S_JMS_USER` 未设置 → 停下，提示用户 export 后重试，值形如 `alice@root`
4. 涉及删除/修改类操作（k8sdel、k8sedit、删 pod、改线上资源）**以及会写数据的脚本**（数据修复/迁移/删除），必须先 AskUserQuestion 确认

## 1. 通道规则

- 格式固定四段 `JMS用户@系统用户@资产IP@堡垒机域名`，**别乱试变体——认证失败多次会锁号**
- 非交互：`ssh -p <k8s.jms.port> "$JMS" '<节点命令>'`（免菜单、免密码）
- 交互需真实终端，加 `-t`。**Claude 的 Bash 无 TTY**，交互式命令（节点 shell / pod 内 bash / rails console）给出命令让用户用 `! ` 前缀自己跑
- 遇到 `Unable to use a TTY` 属预期，不是故障：改用非交互方式

## 2. pod 动态解析（每次现解析，禁止缓存 pod 名）

```bash
# <app> 为 config k8s.apps 里的键
ssh -p <port> "$JMS" 'kubectl get pods -n <app.namespace> | grep Running | awk "{print \$1}" | grep -E "<app.pod_pattern>"'
```

要点（每条都踩过坑）：

- **先取名字列再匹配**：正则锚定行尾，`grep -E` 放 `awk` 前面匹配不到
- `pod_pattern` 按名字长度锚定（如 `^research.{,17}$`），用于排除 sidekiq/listener 等衍生 pod
- pod 名后缀 hash 随重启变，**绝不写死 pod 全名**
- `kubectl exec` **必须带 `-c <app.container>`**：pod 是多容器的，缺省会落错容器或直接报错

## 3. 常用操作（POD = 上一步解析结果；下文简写 `<ns>`=`<app.namespace>`、`<container>`=`<app.container>`、`<port>`=`<k8s.jms.port>`，`<workdir>`/`<runner>` 取该应用 config）

```bash
# 文件日志（含 SQL，最后 N 行）
ssh -p <port> "$JMS" "kubectl exec -n <ns> $POD -c <container> -- tail -10 <workdir>/log/production.log"

# 容器 stdout 日志
ssh -p <port> "$JMS" "kubectl logs -n <ns> $POD -c <container> --tail=100"

# pod 概览（复用节点 alias）
ssh -p <port> "$JMS" "bash -ic 'k8slist <app>'"
```

### 跑脚本三式

```bash
# bash 脚本：stdin 直通
cat fix.sh | ssh -p <port> "$JMS" "kubectl exec -i -n <ns> $POD -c <container> -- bash -s"

# ruby 脚本：先落盘再 runner，跑完清理
cat x.rb | ssh -p <port> "$JMS" "kubectl exec -i -n <ns> $POD -c <container> -- bash -c 'cat > /tmp/x.rb && cd <workdir> && <runner> /tmp/x.rb; rm -f /tmp/x.rb'"

# 内联片段（无需本地文件）
ssh -p <port> "$JMS" "kubectl exec -n <ns> $POD -c <container> -- <runner> -e 'puts 1'"
```

- `<runner>`（如 `bin/rails runner`）与 `<workdir>`（如 `/var/www/research`）一律取 config，**禁止猜**（`/app`、`/srv` 都不对；PATH 里通常没有全局 rails）
- rails runner 启动约 1 分钟，**慢不等于卡死**，不要提前杀掉重试
- 脚本含**写操作**（INSERT/UPDATE/DELETE、改文件）→ 执行前把要点给用户确认：动哪些表/数据、量级、是否可回滚；纯只读脚本（select/puts）直接跑

## 4. 交互式（给用户自己跑，命令前加 `! `）

```bash
ssh -t -p <port> "$JMS"                                                    # 节点 root shell
ssh -t -p <port> "$JMS" "kubectl exec -it -n <ns> $POD -c <container> -- bash"          # pod 内 bash
ssh -t -p <port> "$JMS" "kubectl exec -it -n <ns> $POD -c <container> -- bin/rails c"   # rails console
ssh -t -p <port> "$JMS" "bash -ic 'k8s <app>'"                             # 节点快捷命令进主 pod
```

## 5. 节点自带 alias（`bash -ic '...'` 调用）

| alias | 作用 | 危险 |
|---|---|---|
| `k8s <app>` | 进主 pod | |
| `k8slist <app>` | pod 概览 | |
| `k8slog <app>` | stdout 日志 | |
| `k8sname <app> <容器>` | 指定容器 | |
| `k8sfind <app>` | 所在节点 | |
| `k8sdesc` / `k8swatch` | 详情 / 监听 | |
| `k8sdel` | 删 pod 重启 | ⚠️ 需确认 |
| `k8sedit` | 编辑资源 | ⚠️ 需确认 |
| `k8sn <ns> <app>` | 通用版 | |

## 6. 换节点

目标节点不在当前 JMS 里：查 config `k8s.nodes` 表取 IP，重新拼 JMS 串即可；`default_node` 是默认值。

## 7. 兜底：直连不灵时走交互菜单（给用户自己跑，`! ` 前缀）

`! ssh -p <port> "${QAP_K8S_JMS_USER}@<k8s.jms.host>"` → 回车出资产列表 → 输资产名回车登录（四段格式去掉资产段即菜单模式）。

## 常见错误对照

| 症状 | 原因与处理 |
|---|---|
| `Unable to use a TTY` | 无终端，改非交互执行，或让用户 `! ssh -t ...` 自己跑 |
| exec 报多容器 / 落错容器 | 漏了 `-c <container>` |
| pod 匹配不到 | awk 与 grep 顺序反了；或 pod 非 Running；或 pod_pattern 与实际命名不符 |
| 认证失败 / 被锁 | 四段格式被改动乱试过——逐段核对，别再重试 |
| runner 迟迟无输出 | 启动本来就要约 1 分钟，等，别杀 |
