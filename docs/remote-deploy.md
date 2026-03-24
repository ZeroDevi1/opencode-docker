# OpenCode 远程部署配置文档

本文档说明仓库根目录这套正式远程部署配置的使用方式，目标是把 `opencode` 以 Docker Compose 方式部署到远程 Linux 服务器，并通过 Nginx + ACME 暴露为可远程访问的服务。根目录的 `docker-compose.yml`、`.env.example` 与 `nginx.conf` 对应本文默认推荐方案。

## 1. 部署拓扑

- `opencode`：实际提供服务，容器内监听 `4096`
- `nginx`：统一反向代理，对外监听 `4395` 和 `4396`
- `acme`：使用 `acme.sh` + 阿里云 DNS API 申请并续期证书
- `ssh_keys`：把宿主机 SSH 密钥与 Git 配置挂载进容器，便于容器内拉取私有仓库、推送代码、执行远程 Git 操作
- `docker.sock`：可选，挂载后容器内 OpenCode 可以直接调用宿主机 Docker

推荐访问方式：

- HTTP：`http://example.com:4395`
- HTTPS：`https://example.com:4396`

## 2. 前置条件

开始前请确认：

- 你有一台可公网访问的 Linux 服务器
- 域名已经解析到该服务器公网 IP
- 你有阿里云 DNS API 凭证：`Ali_Key`、`Ali_Secret`
- 服务器已经放行 `22`、`4395`、`4396` 端口
- 服务器已安装 Docker Engine 与 Docker Compose Plugin

如果你准备让容器内 OpenCode 直接管理宿主机容器，还需要保留：

- `/var/run/docker.sock:/var/run/docker.sock`
- `DOCKER_HOST=unix:///var/run/docker.sock`

## 3. 本地生成 SSH 密钥

如果本机还没有专门给这台服务器使用的密钥，建议单独生成一对 `ed25519` 密钥。以下命令在 Windows PowerShell 7 执行：

```powershell
ssh-keygen -t ed25519 -C "opencode-remote" -f "$env:USERPROFILE/.ssh/opencode_remote_ed25519"
```

生成完成后会得到：

- 私钥：`$env:USERPROFILE/.ssh/opencode_remote_ed25519`
- 公钥：`$env:USERPROFILE/.ssh/opencode_remote_ed25519.pub`

建议同时准备一个本地 SSH 别名，编辑 `$env:USERPROFILE/.ssh/config`：

```sshconfig
Host opencode-prod
    HostName <服务器公网 IP 或域名>
    User <登录用户名>
    Port 22
    IdentityFile ~/.ssh/opencode_remote_ed25519
    IdentitiesOnly yes
```

配置完成后，可通过下面命令测试：

```powershell
ssh opencode-prod
```

## 4. 把公钥安装到服务器

如果服务器当前还允许密码登录，可先用已有账号登录，再把本地公钥追加到远程 `authorized_keys`。

PowerShell 示例：

```powershell
Get-Content "$env:USERPROFILE/.ssh/opencode_remote_ed25519.pub" |
ssh <登录用户名>@<服务器地址> "install -d -m 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

验证成功后，建议在服务器的 `/etc/ssh/sshd_config` 中至少确认以下配置：

```text
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
```

修改后重启 SSH 服务：

```bash
sudo systemctl restart ssh
```

注意：务必在新终端确认密钥登录可用后，再关闭密码登录。

## 5. 服务器初始化

登录服务器后，先创建部署目录。这里以 `/srv/opencode-docker` 为例：

```bash
sudo mkdir -p /srv/opencode-docker
sudo chown -R $USER:$USER /srv/opencode-docker
cd /srv/opencode-docker
```

再准备部署需要的目录：

```bash
mkdir -p workspace cc-connect opencode-config opencode-data version-fox ssh_keys letsencrypt nginx-log
chmod 700 ssh_keys
```

建议使用当前部署用户的 UID/GID 填写 Compose，而不是硬编码示例值。查询方法：

```bash
id -u
id -g
```

## 6. 准备挂载用 SSH 与 Git 配置

容器会把 `./ssh_keys` 挂载到 `/home/devuser/.ssh`，并额外挂载 `./ssh_keys/.gitconfig` 到 `/home/devuser/.gitconfig`。建议目录结构如下：

```text
/srv/opencode-docker/
  docker-compose.yml
  nginx.conf
  ssh_keys/
    id_ed25519
    id_ed25519.pub
    known_hosts
    config
    .gitconfig
```

可直接把用于拉取 Git 仓库的密钥复制到服务器：

```bash
cp ~/.ssh/opencode_remote_ed25519 ./ssh_keys/id_ed25519
cp ~/.ssh/opencode_remote_ed25519.pub ./ssh_keys/id_ed25519.pub
chmod 600 ./ssh_keys/id_ed25519
chmod 644 ./ssh_keys/id_ed25519.pub
```

`./ssh_keys/config` 示例：

```sshconfig
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

`./ssh_keys/.gitconfig` 示例：

```ini
[user]
    name = Your Name
    email = your@email.com
```

说明：

- `entrypoint.sh` 会在容器启动时自动修正 `/home/devuser/.ssh` 权限
- 它还会自动补充 `github.com` 与 `codeup.aliyun.com` 的 `known_hosts`
- 私钥文件建议使用 `id_*` 或 `*.key` 命名，便于入口脚本自动设置 `600` 权限

## 7. 编写 `docker-compose.yml`

仓库根目录已经提供可直接使用的 `docker-compose.yml` 与 `.env.example`。推荐做法是：

```bash
cp .env.example .env
```

然后只修改 `.env` 中的真实值，再直接执行 `docker compose up -d`。

当前仓库默认推荐的就是“`opencode + nginx + acme`”三服务独立部署方案。保存为 `/srv/opencode-docker/docker-compose.yml`：

```yaml
services:
  opencode:
    image: ghcr.io/zerodevi1/opencode-docker:latest
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
      - /var/run/docker.sock:/var/run/docker.sock
      - /etc/localtime:/etc/localtime
      - /etc/timezone:/etc/timezone
    environment:
      OPENCODE_SERVER_USERNAME: ${OPENCODE_SERVER_USERNAME}
      OPENCODE_SERVER_PASSWORD: ${OPENCODE_SERVER_PASSWORD}
      PUID: ${PUID}
      PGID: ${PGID}
      TZ: ${TZ}
      DOCKER_HOST: unix:///var/run/docker.sock

  nginx:
    image: nginx:alpine
    container_name: opencode-nginx
    restart: unless-stopped
    ports:
      - "4395:4395"
      - "4396:4396"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./letsencrypt:/etc/letsencrypt:ro
      - ./nginx-log:/var/log/nginx
    depends_on:
      - opencode
      - acme

  acme:
    image: neilpang/acme.sh:latest
    container_name: opencode-acme
    restart: unless-stopped
    volumes:
      - ./letsencrypt:/acme.sh
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      Ali_Key: ${ALI_KEY}
      Ali_Secret: ${ALI_SECRET}
      TARGET_DOMAIN: example.com
    entrypoint: /bin/sh
    command:
      - -c
      - |
        set -eu
        apk add --no-cache docker-cli

        issue_cert() {
          domain="$1"
          if [ -z "$domain" ]; then
            return 0
          fi

          if [ ! -f "/acme.sh/${domain}.pem" ]; then
            echo "[Init] 为 ${domain} 申请证书..."
            /usr/local/bin/acme.sh --issue --dns dns_ali -d "${domain}" --server letsencrypt

            echo "[Init] 安装 ${domain} 证书并配置 Nginx 重载钩子..."
            /usr/local/bin/acme.sh --install-cert -d "${domain}" \
              --key-file       /acme.sh/${domain}.key \
              --fullchain-file /acme.sh/${domain}.pem \
              --reloadcmd      "docker exec opencode-nginx nginx -s reload"
          else
            echo "[Init] ${domain} 证书已存在，跳过首次签发。"
          fi
        }

        issue_cert "$${TARGET_DOMAIN}"

        echo "[Init] 启动 cron 守护进程..."
        exec crond -f
```

说明：

- 提交到仓库的是占位符变量，真实敏感值写入本地 `.env`
- 域名固定为 `example.com`，因此不再通过 `.env` 覆盖 `TARGET_DOMAIN`
- `opencode` 容器内默认监听 `4096`，不需要再额外暴露宿主机端口
- 对外端口由 `nginx` 提供，因此只映射 `4395` 和 `4396`
- `cc-connect` 目录可以先保留为空；只有当 `/home/devuser/.cc-connect/config.toml` 写入真实 token 后，入口脚本才会额外自动启动 `cc-connect`
- 若不需要容器内操作宿主机 Docker，可删除 `docker.sock` 挂载和 `DOCKER_HOST`
- 不建议把真实密码、阿里云密钥、SSH 私钥提交到 Git 仓库
- 建议把 `workspace/`、`cc-connect/`、`opencode-config/`、`opencode-data/`、`version-fox/`、`ssh_keys/`、`letsencrypt/`、`nginx-log/` 视为运行时目录，不提交到仓库

## 8. 编写 `nginx.conf`

仓库根目录已经提供对应的 `nginx.conf`，当前内容固定为 `example.com` 的独立 OpenCode 部署版。部署时可直接使用。

保存为 `/srv/opencode-docker/nginx.conf`：

```nginx
events {
    worker_connections 1024;
}

http {
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen 4395;
        server_name example.com;

        location / {
            proxy_pass http://opencode:4096;
            proxy_buffering off;
            proxy_cache off;
            proxy_http_version 1.1;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Authorization $http_authorization;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 86400;
            proxy_send_timeout 86400;
        }
    }

    server {
        listen 4396 ssl;
        http2 on;
        server_name example.com;

        ssl_certificate     /etc/letsencrypt/example.com.pem;
        ssl_certificate_key /etc/letsencrypt/example.com.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        add_header Content-Security-Policy "upgrade-insecure-requests";

        location / {
            proxy_pass http://opencode:4096;
            proxy_buffering off;
            proxy_cache off;
            proxy_http_version 1.1;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Authorization $http_authorization;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 86400;
            proxy_send_timeout 86400;
        }
    }
}
```

说明：

- `4395` 对应 HTTP
- `4396` 对应 HTTPS
- Nginx 直接复用 `acme` 容器生成的 `/etc/letsencrypt/example.com.pem` 与 `/etc/letsencrypt/example.com.key`
- `Authorization`、`Upgrade`、`Connection` 等头建议保留，避免登录态、流式响应或后续 WebSocket 能力异常

## 9. 首次启动部署

先检查 Compose 配置是否能正确展开：

```bash
docker compose config
```

确认无误后启动：

```bash
docker compose up -d
```

查看启动状态：

```bash
docker compose ps
```

重点检查日志：

```bash
docker compose logs -f acme
docker compose logs -f nginx
docker compose logs -f opencode
```

首次成功后，预期结果如下：

- `acme` 日志出现证书签发或“证书已存在”的提示
- `nginx` 成功加载 `nginx.conf`
- `opencode` 正常监听 `0.0.0.0:4096`
- 访问 `https://example.com:4396` 可以看到 OpenCode 登录页或服务响应

## 10. 验证与联通性检查

可按下面顺序验证：

```bash
curl -I http://127.0.0.1:4395
curl -k -I https://127.0.0.1:4396
curl -I http://example.com:4395
curl -I https://example.com:4396
```

如果你启用了服务器防火墙，还需要确认：

```bash
sudo ufw allow 22/tcp
sudo ufw allow 4395/tcp
sudo ufw allow 4396/tcp
```

## 11. 后续更新与远程发布

如果远程服务器是直接 `git clone` 本仓库部署，后续更新流程可以固定为：

```bash
cd /srv/opencode-docker
git pull
docker compose pull
docker compose up -d
docker image prune -f
```

如果只想更新 OpenCode 镜像：

```bash
docker compose pull opencode
docker compose up -d opencode nginx
```

如果改动了 `nginx.conf`：

```bash
docker compose up -d nginx
docker exec opencode-nginx nginx -t
docker exec opencode-nginx nginx -s reload
```

如果改动了 Compose 中的环境变量或卷挂载，建议直接重新拉起整栈：

```bash
docker compose up -d --force-recreate
```

## 12. 常见问题

### 12.1 证书一直没有签发成功

优先检查：

- `Ali_Key`、`Ali_Secret` 是否正确
- `example.com` 是否已经解析到目标服务器
- 域名 DNS 是否已经生效
- `acme` 容器是否能正常访问外网

排查命令：

```bash
docker compose logs --tail=200 acme
```

### 12.2 HTTPS 无法访问但 HTTP 正常

通常是以下原因之一：

- `letsencrypt/<域名>.pem` 或 `.key` 尚未生成
- `nginx.conf` 中证书路径与 `TARGET_DOMAIN` 不一致
- 服务器未放行 `4396`

### 12.3 容器内 Git / SSH 无法使用

优先检查：

- `./ssh_keys` 是否正确挂载到 `/home/devuser/.ssh`
- 私钥权限是否为 `600`
- `./ssh_keys/.gitconfig` 是否存在
- 目标 Git 平台是否已登记对应公钥

可进入容器验证：

```bash
docker exec -it opencode-dev bash
ssh -T git@github.com
git config --global --list
```

### 12.4 OpenCode 无法操作宿主机 Docker

检查以下几点：

- 是否挂载了 `/var/run/docker.sock`
- 是否设置了 `DOCKER_HOST=unix:///var/run/docker.sock`
- 当前部署用户是否对 Docker Socket 有访问权限

## 13. 对应仓库文件

本部署文档与以下根目录正式远程部署方案对应文件相互对应：

- `README.md`
- `docker-compose.yml`
- `.env.example`
- `nginx.conf`
- `entrypoint.sh`

## 14. 历史参考与相关示例

以下内容仅用于历史对照或特定功能示例，不属于本文正文所述的根目录正式三服务部署流程：

- `examples/compose.remote.yaml`：Codex/OpenCode 共栈历史参考
- `examples/nginx.opencode.conf`：旧的子域名反代模板
- `examples/cc-connect.config.toml`：模板示例 / 功能示例，用于初始化或参考 `/home/devuser/.cc-connect/config.toml`，不是仓库根目录正式远程部署入口；正式远程部署仍优先参考根目录 `docker-compose.yml`、`.env.example`、`nginx.conf` 与本文
- `examples/compose.docker-sock.yaml`：最小 Docker Socket 示例
- `examples/compose.weixin.yaml`：微信接入示例
