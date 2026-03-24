FROM ubuntu:24.04

ARG OPENCODE_VERSION=latest

ENV DEBIAN_FRONTEND=noninteractive
ENV OPENCODE_VERSION=${OPENCODE_VERSION}
ENV VFOX_NODE_VERSION=22.14.0
ENV VFOX_GLOBAL_NPM_PACKAGES="ace-tool @upstash/context7-mcp @fission-ai/openspec@latest"
ENV VFOX_HOME=/home/devuser/.version-fox
ENV DEVUSER_NPM_GLOBAL_PREFIX=/home/devuser/.local/npm-global
ENV DEVUSER_NPM_GLOBAL_BIN=/home/devuser/.local/npm-global/bin

# 使用国内镜像源以提升构建稳定性
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources \
    && sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    dos2unix \
    docker.io \
    ffmpeg \
    git \
    gosu \
    jq \
    musl \
    openssh-client \
    python3 \
    python3-pip \
    sudo \
    tzdata \
    unzip \
    wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 安装 Version Fox，容器内统一使用 vfox 管理 Java / Node.js
RUN set -eux; \
    echo "deb [trusted=yes lang=none] https://apt.fury.io/versionfox/ /" > /etc/apt/sources.list.d/versionfox.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends vfox; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p /etc/profile.d; \
    printf '%s\n' 'export VFOX_HOME=/home/devuser/.version-fox' 'export PATH="$PATH:/home/devuser/.local/npm-global/bin"' 'eval "$(vfox activate bash)"' > /etc/profile.d/vfox.sh; \
    chmod 0644 /etc/profile.d/vfox.sh

# 预创建标准开发用户，便于与宿主机 UID/GID 对齐
RUN (id -u ubuntu >/dev/null 2>&1 && userdel -r ubuntu) || true && \
    groupadd -g 1000 devgroup && \
    useradd -u 1000 -g 1000 -m -s /bin/bash devuser && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER devuser
WORKDIR /home/devuser

RUN mkdir -p "${VFOX_HOME}" \
    "${VFOX_HOME}/plugin" \
    "${VFOX_HOME}/cache" \
    "${VFOX_HOME}/sdks" \
    "${VFOX_HOME}/tmp"

# Rust / uv / qlty 保持与 codex-docker 一致，方便远程开发
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/devuser/.cargo/bin:${PATH}"

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/home/devuser/.local/bin:${PATH}"
ENV UV_SYSTEM_PYTHON=1

RUN curl -fsSL https://qlty.sh | sh
ENV PATH="/home/devuser/.qlty/bin:${PATH}"
RUN curl -fsSL https://bun.com/install | bash && test -x /home/devuser/.bun/bin/bun
ENV PATH="/home/devuser/.bun/bin:${PATH}"
ENV PATH="${PATH}:${DEVUSER_NPM_GLOBAL_BIN}"

RUN echo 'export PATH="$PATH:/home/devuser/.local/npm-global/bin"' >> /home/devuser/.bashrc \
    && echo 'export PATH="$PATH:/home/devuser/.local/npm-global/bin"' >> /home/devuser/.profile \
    && echo 'eval "$(vfox activate bash)"' >> /home/devuser/.bashrc \
    && echo 'eval "$(vfox activate bash)"' >> /home/devuser/.profile \
    && printf '%s\n' 'export VFOX_HOME=/home/devuser/.version-fox' | cat - /home/devuser/.bashrc > /home/devuser/.bashrc.tmp \
    && mv /home/devuser/.bashrc.tmp /home/devuser/.bashrc \
    && printf '%s\n' 'export VFOX_HOME=/home/devuser/.version-fox' | cat - /home/devuser/.profile > /home/devuser/.profile.tmp \
    && mv /home/devuser/.profile.tmp /home/devuser/.profile

RUN bash -lc " \
    vfox add java && \
    vfox add nodejs && \
    vfox install java@21.0.1 && \
    vfox install java@8.0.332 && \
    vfox use -g java@21.0.1+12 && \
    vfox install nodejs@22.14.0 && \
    vfox use -g nodejs@22.14.0 && \
    vfox use nodejs@22.14.0 \
"

RUN bash -lc " \
    corepack enable && \
    corepack prepare pnpm@latest --activate && \
    npm install -g ace-tool @upstash/context7-mcp @fission-ai/openspec@latest \
"

# 使用 npm 全局安装 opencode-ai 与 cc-connect，避免共享 vfox 卷覆盖 CLI
RUN bash -lc ' \
    set -euo pipefail; \
    npm install -g --prefix "${DEVUSER_NPM_GLOBAL_PREFIX}" "opencode-ai@${OPENCODE_VERSION}" "cc-connect@beta"; \
    test -x "${DEVUSER_NPM_GLOBAL_BIN}/opencode"; \
    test -x "${DEVUSER_NPM_GLOBAL_BIN}/cc-connect"; \
    export PATH="${DEVUSER_NPM_GLOBAL_BIN}:$PATH"; \
    command -v opencode >/dev/null; \
    command -v cc-connect >/dev/null; \
    opencode --version >/dev/null; \
    cc-connect --version >/dev/null \
'

USER root

RUN mkdir -p /usr/local/share/cc-connect
COPY examples/cc-connect.config.toml /usr/local/share/cc-connect/config.toml
RUN chmod 0644 /usr/local/share/cc-connect/config.toml

COPY devuser-cli-wrapper.sh /usr/local/bin/devuser-cli-wrapper.sh
RUN dos2unix /usr/local/bin/devuser-cli-wrapper.sh \
    && chmod +x /usr/local/bin/devuser-cli-wrapper.sh \
    && ln -sf /usr/local/bin/devuser-cli-wrapper.sh /usr/local/bin/opencode \
    && ln -sf /usr/local/bin/devuser-cli-wrapper.sh /usr/local/bin/cc-connect

COPY opencode-attach-wrapper.sh /usr/local/bin/opencode-attach
RUN dos2unix /usr/local/bin/opencode-attach \
    && chmod +x /usr/local/bin/opencode-attach

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN dos2unix /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 4096

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
