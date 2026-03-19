#!/bin/bash
set -e

if [ -n "$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

USER_ID=${PUID:-1000}
GROUP_ID=${PGID:-1000}

if [ "$USER_ID" != "1000" ] || [ "$GROUP_ID" != "1000" ]; then
    echo "Updating devuser UID/GID to $USER_ID:$GROUP_ID..."
    groupmod -o -g "$GROUP_ID" devgroup || true
    usermod -o -u "$USER_ID" devuser || true
    chown -R "$USER_ID:$GROUP_ID" /home/devuser &
fi

ensure_owned_dir() {
    local target="$1"
    mkdir -p "$target"
    chown -R devuser:devgroup "$target"
}

with_vfox_bootstrap_lock() {
    local lock_dir="/tmp/vfox-bootstrap.lock"
    local wait_seconds=0

    while ! mkdir "$lock_dir" 2>/dev/null; do
        wait_seconds=$((wait_seconds + 1))
        if [ "$wait_seconds" -eq 1 ]; then
            echo "Waiting for shared vfox bootstrap lock..."
        fi
        if [ "$wait_seconds" -ge 120 ]; then
            echo "Timed out waiting for shared vfox bootstrap lock" >&2
            return 1
        fi
        sleep 1
    done

    trap 'rmdir "$lock_dir" 2>/dev/null || true' RETURN
    "$@"
}

bootstrap_vfox_node() {
    local node_version="${VFOX_NODE_VERSION:-22.14.0}"
    local npm_packages="${VFOX_GLOBAL_NPM_PACKAGES:-ace-tool @upstash/context7-mcp}"

    echo "Bootstrapping shared vfox toolchain..."
    with_vfox_bootstrap_lock gosu devuser bash -lc "
        set -e
        eval \"\$(vfox activate bash)\"

        vfox add nodejs >/dev/null 2>&1 || true

        if ! vfox list nodejs 2>/dev/null | grep -q \"${node_version}\"; then
            vfox install nodejs@${node_version}
        fi

        vfox use -g nodejs@${node_version}
        vfox use nodejs@${node_version}
        hash -r

        corepack enable >/dev/null 2>&1 || true

        for pkg in ${npm_packages}; do
            if ! npm list -g --depth=0 \"\$pkg\" >/dev/null 2>&1; then
                npm install -g \"\$pkg\"
            fi
        done

        command -v node >/dev/null
        command -v npm >/dev/null
    "
}

if [ -d "/home/devuser/.ssh" ]; then
    echo "Securing mounted SSH keys..."

    chown -R devuser:devgroup /home/devuser/.ssh
    chmod 700 /home/devuser/.ssh

    find /home/devuser/.ssh -type f \( -name "id_*" -o -name "*.key" \) -not -name "*.pub" -exec chmod 600 {} \;
    find /home/devuser/.ssh -type f \( -name "*.pub" -o -name "known_hosts" -o -name "config" \) -exec chmod 644 {} \;

    for host in github.com codeup.aliyun.com; do
        if ! grep -q "^${host}" /home/devuser/.ssh/known_hosts 2>/dev/null; then
            echo "Auto-adding SSH host key for ${host}..."
            ssh-keyscan -t rsa,ed25519 "${host}" >> /home/devuser/.ssh/known_hosts 2>/dev/null || true
        fi
    done

    chown devuser:devgroup /home/devuser/.ssh/known_hosts 2>/dev/null || true
    chmod 644 /home/devuser/.ssh/known_hosts 2>/dev/null || true
fi

if [ -f "/home/devuser/.gitconfig" ]; then
    chown devuser:devgroup /home/devuser/.gitconfig || true
    chmod 644 /home/devuser/.gitconfig || true
fi

if [ -d "/workspace" ]; then
    chown devuser:devgroup /workspace || true
fi

# OpenCode 默认使用 XDG 目录，这里确保配置和数据目录可持久化
ensure_owned_dir /home/devuser/.config
ensure_owned_dir /home/devuser/.config/opencode
ensure_owned_dir /home/devuser/.local
ensure_owned_dir /home/devuser/.local/share
ensure_owned_dir /home/devuser/.local/share/opencode
ensure_owned_dir /home/devuser/.version-fox
if [ ! -e /home/devuser/.vfox ]; then
    ln -s /home/devuser/.version-fox /home/devuser/.vfox
fi
chown -h devuser:devgroup /home/devuser/.vfox 2>/dev/null || true

bootstrap_vfox_node

echo "Starting application..."
exec gosu devuser bash -lc 'exec "$@"' -- "$@"
