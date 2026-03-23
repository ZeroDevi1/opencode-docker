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

ensure_docker_socket_access() {
    local docker_socket="/var/run/docker.sock"
    local socket_gid=""
    local socket_group=""

    if [ ! -S "$docker_socket" ]; then
        return 0
    fi

    socket_gid="$(stat -c '%g' "$docker_socket")"
    socket_group="$(getent group "$socket_gid" | cut -d: -f1 || true)"

    if [ -z "$socket_group" ]; then
        socket_group="dockersock"
        if getent group "$socket_group" >/dev/null 2>&1; then
            groupmod -o -g "$socket_gid" "$socket_group" || true
        else
            groupadd -o -g "$socket_gid" "$socket_group" || true
        fi
    fi

    echo "Granting devuser access to ${docker_socket} via group ${socket_group} (${socket_gid})..."
    usermod -aG "$socket_group" devuser || true
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

init_cc_connect_config() {
    local template="/usr/local/share/cc-connect/config.toml"
    local target="/home/devuser/.cc-connect/config.toml"

    ensure_owned_dir /home/devuser/.cc-connect

    if [ ! -f "$target" ] && [ -f "$template" ]; then
        echo "Initializing cc-connect config from template..."
        cp "$template" "$target"
    fi

    if [ -f "$target" ]; then
        chown devuser:devgroup "$target" || true
        chmod 600 "$target" || true
    fi
}

ensure_default_workspace_project() {
    if [ -d "/workspace" ]; then
        mkdir -p /workspace/weixin
        chown devuser:devgroup /workspace/weixin || true
    fi
}

is_opencode_server_command() {
    [ "$#" -ge 2 ] && [ "$1" = "opencode" ] && [ "$2" = "serve" ]
}

cc_connect_config_has_token() {
    local config_path="/home/devuser/.cc-connect/config.toml"

    python3 - "$config_path" <<'PY'
import sys
import tomllib

path = sys.argv[1]

try:
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
except Exception:
    raise SystemExit(1)

for project in data.get("projects", []):
    for platform in project.get("platforms", []):
        if platform.get("type") != "weixin":
            continue
        options = platform.get("options") or {}
        token = (options.get("token") or "").strip()
        if token:
            raise SystemExit(0)

raise SystemExit(1)
PY
}

print_cc_connect_setup_hint() {
    echo "cc-connect is configured but no Weixin token was found in /home/devuser/.cc-connect/config.toml."
    echo "Start the container first, then run the following command inside the container to complete QR login:"
    echo "  cc-connect weixin setup --project weixin"
    echo "After QR login completes, restart the container to auto-start cc-connect."
}

run_with_optional_cc_connect() {
    local opencode_pid=""
    local cc_connect_pid=""
    local exit_status=0

    if ! is_opencode_server_command "$@"; then
        exec gosu devuser bash -lc 'exec "$@"' -- "$@"
    fi

    if ! cc_connect_config_has_token; then
        print_cc_connect_setup_hint
        exec gosu devuser bash -lc 'exec "$@"' -- "$@"
    fi

    terminate_children() {
        if [ -n "$opencode_pid" ] && kill -0 "$opencode_pid" 2>/dev/null; then
            kill "$opencode_pid" 2>/dev/null || true
        fi
        if [ -n "$cc_connect_pid" ] && kill -0 "$cc_connect_pid" 2>/dev/null; then
            kill "$cc_connect_pid" 2>/dev/null || true
        fi
    }

    handle_signal() {
        terminate_children
        wait "$opencode_pid" 2>/dev/null || true
        wait "$cc_connect_pid" 2>/dev/null || true
        exit 143
    }

    trap handle_signal INT TERM

    echo "Starting opencode server..."
    gosu devuser bash -lc 'exec "$@"' -- "$@" &
    opencode_pid=$!

    echo "Starting cc-connect..."
    gosu devuser bash -lc '
        cc-connect -config /home/devuser/.cc-connect/config.toml
        status=$?
        if [ "$status" -ne 0 ]; then
            echo "cc-connect exited with status ${status}. OpenCode will keep running; fix the Weixin side and restart the container when ready."
        fi
        exit "$status"
    ' &
    cc_connect_pid=$!

    set +e
    wait "$opencode_pid"
    exit_status=$?
    set -e

    echo "opencode server exited, stopping companion processes..."

    terminate_children
    wait "$opencode_pid" 2>/dev/null || true
    wait "$cc_connect_pid" 2>/dev/null || true
    trap - INT TERM

    return "$exit_status"
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
ensure_owned_dir /home/devuser/.cc-connect
ensure_owned_dir /home/devuser/.local
ensure_owned_dir /home/devuser/.local/share
ensure_owned_dir /home/devuser/.local/share/opencode
ensure_owned_dir /home/devuser/.version-fox
if [ ! -e /home/devuser/.vfox ]; then
    ln -s /home/devuser/.version-fox /home/devuser/.vfox
fi
chown -h devuser:devgroup /home/devuser/.vfox 2>/dev/null || true

ensure_docker_socket_access

bootstrap_vfox_node
init_cc_connect_config
ensure_default_workspace_project

echo "Starting application..."
run_with_optional_cc_connect "$@"
