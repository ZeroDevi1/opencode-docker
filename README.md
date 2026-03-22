# opencode-docker

基于上游 [OpenCode](https://github.com/anomalyco/opencode) 的 Docker 镜像封装，目标是复用 `codex-docker` 的开发容器体验，同时提供可直接接入远程 Nginx 反代的 `opencode serve` 运行镜像。

## 功能概览

- 基于 `ubuntu:24.04`，内置 `git`、`ssh`、`ffmpeg`、`uv`、`qlty`、`Rust`、`Bun`。
- 统一使用 `vfox` 管理 Java / Node.js，方便容器内构建多语言项目。
- 使用 `devuser` 运行服务，支持 `PUID` / `PGID` 动态映射宿主机权限。
- 默认启动命令：

```bash
opencode serve --hostname 0.0.0.0 --port 4096
```

- 适合与现有 Codex 远程栈并行部署，共享 `workspace`、`.version-fox`、`.ssh`、`.gitconfig`，但分离 OpenCode 自身配置与会话数据。
- 镜像内的 OpenCode 通过官方安装脚本安装到 `/home/devuser/.opencode/bin/opencode`，并已加入 `PATH`。
- Node.js、`ace-tool`、`@upstash/context7-mcp`、`@fission-ai/openspec` 以 `vfox` 方式准备；如果挂载了共享的 `./version-fox`，容器首次启动会自动把它们初始化到该卷里，后续 `codex` 与 `opencode` 可直接复用。

## 本地构建

```bash
docker build -t opencode-docker:local .
```

如果你想固定 OpenCode 版本：

```bash
docker build --build-arg OPENCODE_VERSION=1.2.27 -t opencode-docker:1.2.27 .
```

默认会准备：

- `nodejs@22.14.0`
- `bun`（官方安装脚本，默认位于 `/home/devuser/.bun/bin/bun`）
- 全局 npm 包：`ace-tool`、`@upstash/context7-mcp`、`@fission-ai/openspec@latest`

如需覆盖，可在运行时传入：

```bash
-e VFOX_NODE_VERSION=22.14.0
-e VFOX_GLOBAL_NPM_PACKAGES="ace-tool @upstash/context7-mcp @fission-ai/openspec@latest"
```

构建完成后，可快速验证关键工具是否已就绪：

```bash
docker run --rm opencode-docker:local bash -lc "bun --version && opencode --version && openspec --version"
```

## 本地运行

```bash
docker run --rm -p 4096:4096 \
  -e OPENCODE_SERVER_USERNAME=admin \
  -e OPENCODE_SERVER_PASSWORD=change-me \
  -e TZ=Asia/Shanghai \
  -v ${PWD}/workspace:/workspace \
  -v ${PWD}/opencode-config:/home/devuser/.config/opencode \
  -v ${PWD}/opencode-data:/home/devuser/.local/share/opencode \
  -v ${PWD}/version-fox:/home/devuser/.version-fox \
  opencode-docker:local
```

服务启动后可访问：

- `http://127.0.0.1:4096/global/health`
- `http://127.0.0.1:4096/doc`

如果设置了 `OPENCODE_SERVER_PASSWORD`，需要使用 HTTP Basic Auth 访问。

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
  - `http://ugos.zerodevi1.xyz:5000`
  - `https://ugos.zerodevi1.xyz:5001`
- OpenCode：
  - `http://ugos.zerodevi1.xyz:4395`
  - `https://ugos.zerodevi1.xyz:4396`

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
  - `./opencode-config:/home/devuser/.config/opencode`
  - `./opencode-data:/home/devuser/.local/share/opencode`

注意：你给出的旧示例里 `./version-fox:/home/devuser/..version-fox` 多了一个点，正确路径应为：

```yaml
- ./version-fox:/home/devuser/.version-fox
```

可直接参考：

- [examples/compose.remote.yaml](D:/Projects/ZedProjects/opencode-docker/examples/compose.remote.yaml)
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
    command: >
      sh -c '
        exec opencode serve \
          --hostname 0.0.0.0 \
          --port 4096
      '
```

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

HTTPS 证书可以直接复用 `ugos.zerodevi1.xyz` 的同一套证书文件。为保证服务端推送、事件流和未来扩展稳定，建议至少带上这些代理头：

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

如果 Codex 和 OpenCode 共用同一个域名，ACME 容器只需要维护一套 `TARGET_DOMAIN=ugos.zerodevi1.xyz` 证书即可，不需要再额外申请 `OPENCODE_DOMAIN`。

## GHCR 自动构建

仓库包含 GitHub Actions 工作流：

- 文件：[.github/workflows/build-and-push-ghcr.yml](D:/Projects/ZedProjects/opencode-docker/.github/workflows/build-and-push-ghcr.yml)
- 版本来源：`https://api.github.com/repos/anomalyco/opencode/releases/latest`
- 推送标签：
  - `ghcr.io/<owner>/opencode-docker:<release-tag>`
  - `ghcr.io/<owner>/opencode-docker:latest`

行为与 `codex-docker` 基本一致：

- `schedule`：每天检查一次最新 Release；若 GHCR 已存在同 tag 镜像则跳过。
- `push`：推送 `main` 且相关文件变更时，始终重建。
- `workflow_dispatch`：支持手动触发构建。

## 参考

- OpenCode Server 文档：[https://opencode.ai/docs/zh-cn/server/](https://opencode.ai/docs/zh-cn/server/)
- OpenCode Config 文档：[https://opencode.ai/docs/config/](https://opencode.ai/docs/config/)
- OpenCode CLI 文档：[https://opencode.ai/docs/zh-cn/cli/](https://opencode.ai/docs/zh-cn/cli/)
