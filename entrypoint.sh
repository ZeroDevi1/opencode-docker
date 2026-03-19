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

echo "Starting application..."
exec gosu devuser bash -lc 'exec "$@"' -- "$@"
