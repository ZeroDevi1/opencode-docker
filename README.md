# opencode-docker

基于上游 [OpenCode](https://github.com/anomalyco/opencode) 的 Docker 镜像封装，目标是复用 `codex-docker` 的开发容器体验，同时提供可直接接入远程 Nginx 反代的 `opencode serve` 运行镜像。

> 免责声明：本项目不是 OpenCode 团队官方开发或维护的项目，与 OpenCode 团队不存在隶属、代理或其他官方关联关系。

## 功能概览

- 基于 `ubuntu:24.04`，内置 `git`、`ssh`、`ffmpeg`、`uv`、`qlty`、`Rust`、`Bun`、`Docker CLI`。
- 统一使用 `vfox` 管理 Java / Node.js，方便容器内构建多语言项目。
- 使用 `devuser` 运行服务，支持 `PUID` / `PGID` 动态映射宿主机权限。
- 默认启动行为：

```bash
opencode serve --hostname 0.0.0.0 --port 4096
```

- 若 `/home/devuser/.cc-connect/config.toml` 已写入真实微信 `token`，entrypoint 会额外自动启动 `cc-connect -config /home/devuser/.cc-connect/config.toml`。
- 适合与现有 Codex 远程栈并行部署，共享 `workspace`、`.version-fox`、`.ssh`、`.gitconfig`，但分离 OpenCode 自身配置与会话数据。
- 镜像内的 OpenCode 与 `cc-connect@beta` 会在构建阶段安装到独立目录 `/home/devuser/.local/npm-global/bin`，不会被共享的 `./version-fox` 挂载覆盖；同时镜像会提供 `/usr/local/bin/opencode`、`/usr/local/bin/cc-connect` 包装入口，并补齐 `devuser` 的 `.bashrc` / `.profile` PATH，因此 `root`、`su devuser`、`su - devuser`、`docker exec -u devuser ...` 都能直接执行这两个命令。
- Node.js、`ace-tool`、`@upstash/context7-mcp`、`@fission-ai/openspec` 以 `vfox` 方式准备；如果挂载了共享的 `./version-fox`，容器首次启动会自动把它们初始化到该卷里，后续 `codex` 与 `opencode` 可直接复用。
- 容器首次启动会自动初始化 `/home/devuser/.cc-connect/config.toml` 模板，并确保默认工作区 `/workspace/weixin` 存在。

## 本地构建

```bash
docker build -t opencode-docker:local .
```

如果你想固定 OpenCode 版本（npm 包版本，不带 `v` 前缀）：

```bash
docker build --build-arg OPENCODE_VERSION=1.2.27 -t opencode-docker:1.2.27 .
```

默认会准备：

- `nodejs@22.14.0`
- `bun`（官方安装脚本，默认位于 `/home/devuser/.bun/bin/bun`）
- 独立 CLI：`opencode-ai`、`cc-connect@beta`
- 全局 npm 包：`ace-tool`、`@upstash/context7-mcp`、`@fission-ai/openspec@latest`

如需覆盖，可在运行时传入：

```bash
-e VFOX_NODE_VERSION=22.14.0
-e VFOX_GLOBAL_NPM_PACKAGES="ace-tool @upstash/context7-mcp @fission-ai/openspec@latest"
```

构建完成后，可快速验证关键工具是否已就绪：

```bash
docker run --rm opencode-docker:local bash -lc "docker --version && bun --version && opencode --version && cc-connect --version && openspec --version"
```

如果你想额外确认 `root` 和非登录 `devuser` shell 的 PATH 都正常，可再执行：

```bash
docker run --rm --entrypoint bash opencode-docker:local -lc "cc-connect --version && su devuser -c 'cc-connect --version'"
```

## 本地运行

```bash
docker run --rm -p 4096:4096 \
  -e OPENCODE_SERVER_USERNAME=admin \
  -e OPENCODE_SERVER_PASSWORD=change-me \
  -e TZ=Asia/Shanghai \
  -v ${PWD}/workspace:/workspace \
  -v ${PWD}/cc-connect:/home/devuser/.cc-connect \
  -v ${PWD}/opencode-config:/home/devuser/.config/opencode \
  -v ${PWD}/opencode-data:/home/devuser/.local/share/opencode \
  -v ${PWD}/version-fox:/home/devuser/.version-fox \
  opencode-docker:local
```

服务启动后可访问：

- `http://127.0.0.1:4096/global/health`
- `http://127.0.0.1:4096/doc`

如果设置了 `OPENCODE_SERVER_PASSWORD`，需要使用 HTTP Basic Auth 访问。

首次运行后还会得到：

- `./cc-connect/config.toml`：从镜像模板初始化的 `cc-connect` 配置
- `./workspace/weixin`：默认信任并绑定给 OpenCode 的工作区

## 微信接入 cc-connect

`weixin` 平台目前只在 `cc-connect` 的 beta / pre-release 通道提供，因此镜像内默认安装的是 `cc-connect@beta`，不是 stable。

推荐流程：

1. 先按上面的方式启动容器，并映射 `./cc-connect:/home/devuser/.cc-connect`
2. 进入容器执行：

```bash
cc-connect weixin setup --project weixin
```

如果你是通过 Compose 启动的，也可以直接在宿主机执行：

```bash
docker exec -it opencode-weixin bash -lc 'cc-connect weixin setup --project weixin'
```

3. 用手机微信扫码并确认
4. 检查 `/home/devuser/.cc-connect/config.toml` 已被回写真实 `token`、`account_id`、`allow_from`
5. 重启容器，entrypoint 就会在启动 `opencode serve` 的同时自动拉起 `cc-connect`

说明：

- 扫码必须在运行中的容器内人工完成，不能放进 `Dockerfile`、entrypoint 或 Compose 自动代办。
- 真实微信凭证只会写入映射出来的 `/home/devuser/.cc-connect/config.toml`，不会写进仓库文件或镜像层。
- `/home/devuser/.cc-connect/config.toml` 会包含真实 token，请不要提交到 git。
- 建议把 `./cc-connect/` 或至少 `./cc-connect/config.toml` 加入你自己的 `.gitignore`。
- 如果尚未扫码，容器仍会正常启动 OpenCode，只是在日志中提示你执行 `cc-connect weixin setup --project weixin`。
- 若希望自动双进程启动，请尽量使用镜像默认 `CMD`，不要再覆盖成自定义 `command:`。
- 若你是在容器里临时切到 `root` 或执行 `su devuser`，现在也可以直接运行 `cc-connect`；镜像内包装脚本会自动补齐 `node` 与 npm CLI 所需的运行环境。

## 在容器内控制宿主机 Docker

镜像已包含 `docker` CLI。只要在运行时挂载 `/var/run/docker.sock`，entrypoint 会根据 socket 的实际 GID 自动为 `devuser` 补充对应组权限，因此 `devuser` 可直接访问宿主机 Docker daemon。

最小示例：

```bash
docker run --rm -p 4096:4096 \
  -e OPENCODE_SERVER_USERNAME=admin \
  -e OPENCODE_SERVER_PASSWORD=change-me \
  -e TZ=Asia/Shanghai \
  -v ${PWD}/workspace:/workspace \
  -v ${PWD}/cc-connect:/home/devuser/.cc-connect \
  -v ${PWD}/opencode-config:/home/devuser/.config/opencode \
  -v ${PWD}/opencode-data:/home/devuser/.local/share/opencode \
  -v ${PWD}/version-fox:/home/devuser/.version-fox \
  -v /var/run/docker.sock:/var/run/docker.sock \
  opencode-docker:local
```

如果使用 Compose，可直接参考 `examples/compose.docker-sock.yaml`。容器启动后可验证：

```bash
docker exec -it opencode-dev bash -lc "id && docker ps"
```

## MCP 与共享 vfox

如果你把 `./version-fox` 同时挂给 `codex` 和 `opencode`，推荐让 MCP 直接调用已经安装好的全局命令，而不是每次走 `npx` 冷启动：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "ace-tool": {
      "type": "local",
      "command": [
        "ace-tool",
        "--base-url",
        "https://acemcp.heroman.wtf/relay/",
        "--token",
        "YOUR_ACE_TOKEN"
      ],
      "enabled": true,
      "timeout": 30000
    },
    "context7": {
      "type": "local",
      "command": [
        "context7-mcp",
        "--api-key",
        "YOUR_CONTEXT7_API_KEY"
      ],
      "enabled": true,
      "timeout": 30000
    }
  }
}
```

说明：

- `vfox use -g` 用于持久化全局版本。
- `vfox use`（默认 Session 级）用于让当前 shell 立刻拿到 `node/npm/npx` 的 `PATH`。这是你刚才手工执行后仍然出现 `npm: command not found` 的直接原因。
- 如果卷是第一次挂载，entrypoint 会自动安装 Node 和全局 npm 包；后续两个容器都能复用。

## 远程部署建议

推荐把 OpenCode 作为现有 `codex + nginx + acme` 栈中的一个额外服务加入。

如果你的远程环境和当前现网一样，不能给 OpenCode 单独占用宿主机 `80/443`，推荐使用“同域名 + 独立端口”模式：

- Codex：
  - `http://example.com:5000`
  - `https://example.com:5001`
- OpenCode：
  - `http://example.com:4395`
  - `https://example.com:4396`

这里有一个关键点：不能只在 Docker 里把 `4395:80`、`4396:443` 映射出去，因为这样请求进入 Nginx 后仍然只会落到容器内的 `80/443`，Nginx 无法按“外部端口”区分 Codex 和 OpenCode。正确做法是：

- Codex 在 Nginx 容器内继续监听 `80/443`
- OpenCode 在 Nginx 容器内额外监听 `4395/4396`
- 宿主机端口一一映射到容器内同名端口

这不会和 OpenCode 服务本身冲突，因为：

- `opencode` 容器内服务端口仍然是 `4096`
- `4395/4396` 是 `nginx` 容器内监听并暴露到宿主机的端口
- 两者属于不同容器，不共享监听套接字

- 共享卷：
  - `./workspace:/workspace`
  - `./version-fox:/home/devuser/.version-fox`
  - `./ssh_keys:/home/devuser/.ssh`
  - `./ssh_keys/.gitconfig:/home/devuser/.gitconfig`
- 独立卷：
  - `./cc-connect:/home/devuser/.cc-connect`
  - `./opencode-config:/home/devuser/.config/opencode`
  - `./opencode-data:/home/devuser/.local/share/opencode`

注意：你给出的旧示例里 `./version-fox:/home/devuser/..version-fox` 多了一个点，正确路径应为：

```yaml
- ./version-fox:/home/devuser/.version-fox
```

可直接参考：

- [examples/compose.remote.yaml](D:/Projects/ZedProjects/opencode-docker/examples/compose.remote.yaml)
- [examples/compose.docker-sock.yaml](D:/Projects/ZedProjects/opencode-docker/examples/compose.docker-sock.yaml)
- [examples/compose.weixin.yaml](D:/Projects/ZedProjects/opencode-docker/examples/compose.weixin.yaml)
- [examples/nginx.opencode.conf](D:/Projects/ZedProjects/opencode-docker/examples/nginx.opencode.conf)
- [nginx.conf](D:/Projects/ZedProjects/opencode-docker/nginx.conf)

## Compose 合并要点

`opencode` 服务建议如下：

```yaml
  opencode:
    image: ghcr.io/<owner>/opencode-docker:latest
    container_name: opencode-dev
    restart: unless-stopped
    volumes:
      - ./workspace:/workspace
      - ./cc-connect:/home/devuser/.cc-connect
      - ./opencode-config:/home/devuser/.config/opencode
      - ./opencode-data:/home/devuser/.local/share/opencode
      - ./version-fox:/home/devuser/.version-fox
      - ./ssh_keys:/home/devuser/.ssh
      - ./ssh_keys/.gitconfig:/home/devuser/.gitconfig
    environment:
      - OPENCODE_SERVER_USERNAME=admin
      - OPENCODE_SERVER_PASSWORD=change-me
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
```

这里建议直接使用镜像默认 `CMD`，这样 entrypoint 才能在检测到微信 token 后自动同时拉起 `opencode serve` 与 `cc-connect`。

如果走“同域名 + 独立端口”模式，Nginx 需要同时监听这四个端口：

```yaml
ports:
  - "5000:80"
  - "5001:443"
  - "4395:4395"
  - "4396:4396"
```

对应的 Nginx 路由关系是：

- `80/443 -> codex:5000`
- `4395/4396 -> opencode:4096`

HTTPS 证书可以直接复用 `example.com` 的同一套证书文件。为保证服务端推送、事件流和未来扩展稳定，建议至少带上这些代理头：

```nginx
proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
```

如果 Codex 和 OpenCode 共用同一个域名，ACME 容器只需要维护一套 `TARGET_DOMAIN=example.com` 证书即可，不需要再额外申请 `OPENCODE_DOMAIN`。

## GHCR 自动构建

仓库包含 GitHub Actions 工作流：

- 文件：[.github/workflows/build-and-push-ghcr.yml](D:/Projects/ZedProjects/opencode-docker/.github/workflows/build-and-push-ghcr.yml)
- 版本来源：`https://api.github.com/repos/anomalyco/opencode/releases/latest`
- 推送标签：
  - `ghcr.io/<owner>/opencode-docker:<release-tag>`
  - `ghcr.io/<owner>/opencode-docker:latest`

行为与 `codex-docker` 基本一致：

- `schedule`：每天检查一次最新 Release；若 GHCR 已存在同 `release-tag` 镜像则跳过。
- `push`：推送 `main` 且相关文件变更时，始终重建。
- `workflow_dispatch`：支持手动触发构建；即使同版本镜像已存在，也会按当前最新 Release 重新构建。

说明：GitHub Release tag 可能带 `v` 前缀（如 `v1.3.0`），工作流会保留该 tag 作为镜像标签，同时自动去掉前缀后再传给 `npm i -g opencode-ai@<version>`。在真正构建前，workflow 还会先校验 npm 上已发布对应的 `opencode-ai` 版本；若 npm 尚未同步该版本，则本次运行会直接失败，不会继续推镜像。对于真正要重建的场景，workflow 会先删除 GHCR 中当前 `release-tag` 和 `latest` 对应的 package version，再重新构建并推送，尽量减少手动重建后残留无 tag 版本的情况。

## 参考

- OpenCode Server 文档：[https://opencode.ai/docs/zh-cn/server/](https://opencode.ai/docs/zh-cn/server/)
- OpenCode Config 文档：[https://opencode.ai/docs/config/](https://opencode.ai/docs/config/)
- OpenCode CLI 文档：[https://opencode.ai/docs/zh-cn/cli/](https://opencode.ai/docs/zh-cn/cli/)
