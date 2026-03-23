# cc-connect Weixin OpenCode Docker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让当前 `opencode-docker` 镜像默认集成 `cc-connect@beta`，并通过映射出的 `/home/devuser/.cc-connect/config.toml` 支持微信个人号控制 `/workspace/weixin` 下的 OpenCode。

**Architecture:** 保持单容器双进程方案：entrypoint 先初始化 `.cc-connect`、模板配置和 `/workspace/weixin`，再同时托管 `opencode serve` 与 `cc-connect`。真实微信凭证与扫码登录态只落在映射出的 `.cc-connect` 目录，仓库仅提供模板与运行示例。

**Tech Stack:** Dockerfile、Bash entrypoint、TOML 配置模板、Docker Compose YAML、README Markdown

---

### Task 1: 扩展镜像安装 cc-connect beta 与模板资源

**Files:**
- Modify: `Dockerfile`
- Create: `examples/cc-connect.config.toml`

- [ ] **Step 1: 写出需要验证的构建断言**

记录本任务的关键验证命令：`cc-connect --version`、`opencode --version`、`test -f /usr/local/share/cc-connect/config.toml`。

- [ ] **Step 2: 更新 Dockerfile 安装 cc-connect@beta**

在现有全局 npm 安装阶段增加 `cc-connect@beta`，并把模板配置复制到镜像内稳定路径，例如 `/usr/local/share/cc-connect/config.toml`。

- [ ] **Step 3: 创建微信 + OpenCode 示例模板**

新建 `examples/cc-connect.config.toml`，固定项目名 `weixin`、`agent.type = "opencode"`、`work_dir = "/workspace/weixin"`、`mode = "yolo"`、`model = "openai/gpt-5.4"`，并给 `weixin` 平台保留占位敏感字段。

- [ ] **Step 4: 运行最小构建验证**

Run: `docker build -t opencode-docker:cc-connect-test .`
Expected: 构建成功，日志中无 `cc-connect` 安装失败。

- [ ] **Step 5: 运行镜像内版本验证**

Run: `docker run --rm opencode-docker:cc-connect-test bash -lc "cc-connect --version && opencode --version && test -f /usr/local/share/cc-connect/config.toml"`
Expected: 三项都成功退出。

### Task 2: 扩展 entrypoint 完成初始化与双进程托管

**Files:**
- Modify: `entrypoint.sh`

- [ ] **Step 1: 写出需要验证的运行时行为**

记录本任务的关键行为：自动创建 `/home/devuser/.cc-connect`、首次复制模板、确保 `/workspace/weixin` 存在、同时拉起 `opencode serve` 和 `cc-connect`、任一进程退出时容器退出。

- [ ] **Step 2: 实现目录与模板初始化**

在 `entrypoint.sh` 中增加：
- `ensure_owned_dir /home/devuser/.cc-connect`
- 若 `/home/devuser/.cc-connect/config.toml` 不存在，则从 `/usr/local/share/cc-connect/config.toml` 复制
- 确保 `/workspace/weixin` 目录存在且归属 `devuser:devgroup`

- [ ] **Step 3: 实现双进程启动逻辑**

让 entrypoint 负责前台托管 `opencode serve ...`。若 `/home/devuser/.cc-connect/config.toml` 中已经存在真实 `token`，则后台启动 `cc-connect -config /home/devuser/.cc-connect/config.toml`，并用 `trap` / `wait -n` 在 `cc-connect` 异常退出后清理 `opencode` 并返回非零状态；若尚未完成扫码，则仅启动 OpenCode 并输出明确提示。

- [ ] **Step 4: 增加未扫码时的可恢复提示**

如果模板配置缺少真实 `token`，不要尝试自动拉起 `cc-connect`；日志中明确提示用户必须在容器启动后手动执行 `cc-connect weixin setup --project weixin`，且该步骤不由 Dockerfile、entrypoint、Compose 自动代办。

- [ ] **Step 5: 运行容器初始化验证**

Run: `docker run --rm -d --name opencode-cc-init -p 4096:4096 -v "${PWD}/tmp/cc-connect:/home/devuser/.cc-connect" -v "${PWD}/tmp/workspace:/workspace" opencode-docker:cc-connect-test`
Expected: 容器保持运行，宿主机 `tmp/cc-connect/config.toml` 与 `tmp/workspace/weixin` 被创建。

- [ ] **Step 6: 验证未扫码时 OpenCode 仍可用**

Run: `docker exec opencode-cc-init bash -lc "python3 - <<'PY'
import socket
s=socket.socket()
s.connect(('127.0.0.1', 4096))
print('ok')
PY" && docker logs opencode-cc-init`
Expected: 端口 `4096` 可连接，日志包含手动执行 `cc-connect weixin setup --project weixin` 的提示。

- [ ] **Step 7: 清理临时容器**

Run: `docker rm -f opencode-cc-init`
Expected: 容器被移除。

### Task 3: 补充运行示例与远程开发文档

**Files:**
- Modify: `README.md`
- Create: `examples/compose.weixin.yaml`

- [ ] **Step 1: 写出文档需要覆盖的用户路径**

覆盖内容包括：`.cc-connect` 卷映射、首次扫码命令、双进程常驻说明、`/workspace/weixin` 默认绑定、远程开发建议。

- [ ] **Step 2: 新增 compose 示例**

创建 `examples/compose.weixin.yaml`，包含：
- `./workspace:/workspace`
- `./cc-connect:/home/devuser/.cc-connect`
- `./opencode-config:/home/devuser/.config/opencode`
- `./opencode-data:/home/devuser/.local/share/opencode`
- `./version-fox:/home/devuser/.version-fox`
- 可选 `docker.sock` 挂载

- [ ] **Step 3: 更新 README 使用说明**

在 README 中新增 `cc-connect` 小节，说明：
- 为什么必须使用 `cc-connect@beta`
- 为什么扫码只能在运行中的容器内手动执行
- 真实凭证写入 `/home/devuser/.cc-connect/config.toml`
- 推荐映射 `.cc-connect` 与 `/workspace` 以支持远程开发

- [ ] **Step 4: 更新 README 验证与排障**

补充版本验证、首次扫码命令、`cc-connect` 启动失败提示、如何查看日志。

- [ ] **Step 5: 验证 Compose 示例可展开**

Run: `docker compose -f examples/compose.weixin.yaml config`
Expected: Compose 配置展开成功，无语法错误。

- [ ] **Step 6: 运行文本与示例复核**

Run: `grep -n "cc-connect" README.md examples/compose.weixin.yaml examples/cc-connect.config.toml`
Expected: 三个文件都包含核心接入说明。

### Task 4: 进行端到端验证

**Files:**
- Test: `Dockerfile`
- Test: `entrypoint.sh`
- Test: `README.md`
- Test: `examples/compose.weixin.yaml`
- Test: `examples/cc-connect.config.toml`

- [ ] **Step 1: 重新构建最终镜像**

Run: `docker build -t opencode-docker:cc-connect-final .`
Expected: 构建成功。

- [ ] **Step 2: 验证镜像内核心命令**

Run: `docker run --rm opencode-docker:cc-connect-final bash -lc "cc-connect --version && opencode --version && docker --version"`
Expected: 三条命令都返回版本信息。

- [ ] **Step 3: 验证卷初始化与默认工作区**

Run: `docker run --rm -v "${PWD}/tmp/cc-connect-final:/home/devuser/.cc-connect" -v "${PWD}/tmp/workspace-final:/workspace" opencode-docker:cc-connect-final bash -lc "test -f /home/devuser/.cc-connect/config.toml && test -d /workspace/weixin"`
Expected: 配置文件和默认工作区都存在。

- [ ] **Step 4: 验证未扫码时 OpenCode 端口仍可用**

Run: `docker run --rm -d --name opencode-cc-final -p 4096:4096 -v "${PWD}/tmp/cc-connect-final:/home/devuser/.cc-connect" -v "${PWD}/tmp/workspace-final:/workspace" opencode-docker:cc-connect-final && sleep 5 && docker logs opencode-cc-final`
Expected: 容器正常运行，日志提示手动执行 `cc-connect weixin setup --project weixin`，OpenCode 未因 `cc-connect` 缺少 token 而退出。

- [ ] **Step 5: 记录人工扫码验收步骤**

记录最终人工步骤：进入容器执行 `cc-connect weixin setup --project weixin`，微信扫码后确认 `/home/devuser/.cc-connect/config.toml` 已写入真实 `token/account_id/allow_from`；并明确该步骤必须人工完成，不能由 Dockerfile、entrypoint、Compose 自动代办。

- [ ] **Step 6: 清理最终验证容器并整理结果**

Run: `docker rm -f opencode-cc-final`
Expected: 容器被移除。

- [ ] **Step 7: 整理结果并准备交付**

总结变更文件、已跑过的验证命令、仍需用户手工执行的扫码步骤。
