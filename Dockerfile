FROM ubuntu:24.04

ARG OPENCODE_VERSION=latest

ENV DEBIAN_FRONTEND=noninteractive
ENV OPENCODE_VERSION=${OPENCODE_VERSION}

# 使用国内镜像源以提升构建稳定性
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources \
    && sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    dos2unix \
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
    printf '%s\n' 'eval "$(vfox activate bash)"' > /etc/profile.d/vfox.sh; \
    chmod 0644 /etc/profile.d/vfox.sh

# 预创建标准开发用户，便于与宿主机 UID/GID 对齐
RUN (id -u ubuntu >/dev/null 2>&1 && userdel -r ubuntu) || true && \
    groupadd -g 1000 devgroup && \
    useradd -u 1000 -g 1000 -m -s /bin/bash devuser && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER devuser
WORKDIR /home/devuser

# Rust / uv / qlty 保持与 codex-docker 一致，方便远程开发
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/devuser/.cargo/bin:${PATH}"

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/home/devuser/.local/bin:${PATH}"
ENV UV_SYSTEM_PYTHON=1

RUN curl -fsSL https://qlty.sh | sh
ENV PATH="/home/devuser/.qlty/bin:${PATH}"

RUN echo 'eval "$(vfox activate bash)"' >> /home/devuser/.bashrc \
    && echo 'eval "$(vfox activate bash)"' >> /home/devuser/.profile

RUN bash -lc " \
    vfox add java && \
    vfox add nodejs && \
    vfox install java@21.0.1 && \
    vfox install java@8.0.332 && \
    vfox use -g java@21.0.1+12 && \
    vfox install nodejs@22.14.0 && \
    vfox use -g nodejs@22.14.0 \
"

RUN bash -lc " \
    corepack enable && \
    corepack prepare pnpm@latest --activate && \
    npm install -g ace-tool && \
    npm install -g opencode-ai@${OPENCODE_VERSION} \
"

USER root

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN dos2unix /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 4096

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
