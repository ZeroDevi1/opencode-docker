# cc-connect 微信接入 OpenCode Docker 设计

## 目标

- 在当前 `opencode-docker` 镜像中集成 `cc-connect@beta`，让微信个人号（ilink）可以控制容器内的 OpenCode。
- 保持现有远程开发体验，继续以 `/workspace` 作为统一工作区，并默认绑定 `/workspace/weixin`。
- 首次登录采用“容器启动后手动扫码”，登录态与真实配置持久化到映射出的 `/home/devuser/.cc-connect`。

## 约束与前提

- `weixin` 平台仅在 `cc-connect` 的 beta / pre-release 通道可用，因此镜像必须安装 `cc-connect@beta`，不能使用 stable。
- 微信扫码属于交互式登录，不能放进 `docker build`，也不应在容器启动阶段强制阻塞等待扫码。
- 真实 `token`、`account_id`、`allow_from` 等敏感值不能写入仓库文件或镜像层，只能落在宿主机映射出来的 `.cc-connect` 目录。
- 用户要求容器默认信任并服务 `/workspace/weixin`，因此镜像启动时应确保该目录存在，并将其作为 `cc-connect` 中 OpenCode agent 的固定 `work_dir`。

## 运行架构

- 容器内常驻两个进程：
  - `opencode serve --hostname 0.0.0.0 --port 4096`
  - `cc-connect -config /home/devuser/.cc-connect/config.toml`
- `entrypoint.sh` 负责完成目录初始化、模板配置复制、权限修正和双进程生命周期管理。
- 当 `/home/devuser/.cc-connect/config.toml` 不存在时，entrypoint 从镜像内模板生成初始配置；若已存在，则完全保留用户版本。
- 首次接入必须在容器已经启动后，由用户手动进入容器执行 `cc-connect weixin setup --project weixin` 完成扫码。该步骤不由 `docker build`、entrypoint 或其他自动化流程代办。
- 上述命令写回的 `token`、`account_id`、`allow_from` 等真实值会直接落到 `/home/devuser/.cc-connect/config.toml`，后续容器重启自动恢复。

## 配置边界

- 持久化目录：
  - `/home/devuser/.cc-connect`：`cc-connect` 目录；其中真实配置文件固定为 `/home/devuser/.cc-connect/config.toml`，会话状态与微信登录态也保存在该目录下
  - `/home/devuser/.config/opencode`：OpenCode 配置
  - `/home/devuser/.local/share/opencode`：OpenCode 数据目录
- 仓库仅提供模板与示例：
  - `examples/cc-connect.config.toml`：微信 + OpenCode 示例配置
  - `examples/compose.weixin.yaml`：包含 `.cc-connect` 挂载的运行示例
- 模板配置固定：
  - `project.name = "weixin"`
  - `agent.type = "opencode"`
  - `agent.options.work_dir = "/workspace/weixin"`
  - `agent.options.mode = "yolo"`
  - `agent.options.model = "openai/gpt-5.4"`
  - `platform.type = "weixin"`
- 敏感字段仅保留占位说明，不提供真实值。

## 远程开发增强

- Dockerfile 补齐 `cc-connect@beta`，并保持现有 `vfox`、`docker` CLI、`uv`、`bun` 工具链不变。
- README 补充微信接入流程、`.cc-connect` 卷映射、扫码初始化步骤、双进程常驻说明。
- Compose 示例新增 `.cc-connect:/home/devuser/.cc-connect`，同时保留 `docker.sock`、`workspace`、`version-fox` 的远程开发挂载模式。
- 可选地在 `/workspace/weixin` 首次放置 `OPENCODE.md`，让 OpenCode 知道该项目由 `cc-connect` 驱动并支持 `cc-connect cron/send` 命令。

## 失败处理与可恢复性

- 若 `cc-connect` 未完成扫码，容器仍应允许 OpenCode 服务正常启动，日志明确提示用户执行 `cc-connect weixin setup`。
- 若模板配置缺失敏感值，`cc-connect` 可以失败退出，但 entrypoint 需要输出清晰说明，不应静默失败。
- 双进程管理需保证任一关键进程退出后容器整体退出，避免出现“容器存活但核心服务失效”的假活状态。

## 验证方式

- 构建镜像后验证：`cc-connect --version`、`opencode --version`、`docker --version`。
- 运行容器后验证：
  - `/home/devuser/.cc-connect` 是否被自动初始化
  - `/workspace/weixin` 是否存在
  - `opencode serve` 是否对外监听 `4096`
  - 首次扫码后 `cc-connect` 是否能读取更新后的配置并启动微信平台
