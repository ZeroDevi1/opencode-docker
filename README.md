# opencode-docker

基于上游 [OpenCode](https://github.com/anomalyco/opencode) 的 Docker 镜像封装，目标是复用 `codex-docker` 的开发容器体验，同时提供可直接接入远程 Nginx 反代的 `opencode serve` 运行镜像。

## 功能概览

- 基于 `ubuntu:24.04`，内置 `git`、`ssh`、`ffmpeg`、`uv`、`qlty`、`Rust`。
- 统一使用 `vfox` 管理 Java / Node.js，方便容器内构建多语言项目。
- 使用 `devuser` 运行服务，支持 `PUID` / `PGID` 动态映射宿主机权限。
- 默认启动命令：

```bash
opencode serve --hostname 0.0.0.0 --port 4096
```

- 适合与现有 Codex 远程栈并行部署，共享 `workspace`、`.version-fox`、`.ssh`、`.gitconfig`，但分离 OpenCode 自身配置与会话数据。

## 本地构建

```bash
docker build -t opencode-docker:local .
```

如果你想固定 OpenCode 版本：

```bash
docker build --build-arg OPENCODE_VERSION=1.2.27 -t opencode-docker:1.2.27 .
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

## 远程部署建议

推荐把 OpenCode 作为现有 `codex + nginx + acme` 栈中的一个额外服务加入：

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

Nginx 建议新增一个独立子域名，例如 `opencode.example.com`，反代到容器内的 `http://opencode:4096`。为保证服务端推送、事件流和未来扩展稳定，建议至少带上这些代理头：

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

ACME 容器可以沿用现有模式，只需要把 `TARGET_DOMAIN` 扩展成同时处理 Codex 和 OpenCode 的域名列表，或额外增加一个 `OPENCODE_DOMAIN` 环境变量，并在初始化脚本中逐个检查是否已有证书。

## GHCR 自动构建

仓库包含 GitHub Actions 工作流：

- 文件：[.github/workflows/build-and-push-ghcr.yml](D:/Projects/ZedProjects/opencode-docker/.github/workflows/build-and-push-ghcr.yml)
- 版本来源：`https://registry.npmjs.org/opencode-ai/latest`
- 推送标签：
  - `ghcr.io/<owner>/opencode-docker:<npm-version>`
  - `ghcr.io/<owner>/opencode-docker:latest`

行为与 `codex-docker` 基本一致：

- `schedule`：每天检查一次最新 npm 版本；若 GHCR 已存在同 tag 镜像则跳过。
- `push`：推送 `main` 且相关文件变更时，始终重建。
- `workflow_dispatch`：支持手动触发构建。

## 参考

- OpenCode Server 文档：[https://opencode.ai/docs/zh-cn/server/](https://opencode.ai/docs/zh-cn/server/)
- OpenCode Config 文档：[https://opencode.ai/docs/config/](https://opencode.ai/docs/config/)
- OpenCode CLI 文档：[https://opencode.ai/docs/zh-cn/cli/](https://opencode.ai/docs/zh-cn/cli/)
