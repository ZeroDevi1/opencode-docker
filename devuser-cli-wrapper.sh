#!/bin/bash
set -euo pipefail

cli_name="$(basename "$0")"
devuser_home="${DEVUSER_CLI_HOME:-/home/devuser}"
runtime_user="${DEVUSER_CLI_RUNTIME_USER:-devuser}"
current_uid="${DEVUSER_CLI_CURRENT_UID:-$(id -u)}"
gosu_cmd="${DEVUSER_CLI_GOSU:-gosu}"
target="${devuser_home}/.local/npm-global/bin/${cli_name}"

if [ ! -x "$target" ]; then
    echo "${cli_name} is not installed at ${target}" >&2
    exit 127
fi

export VFOX_HOME="${VFOX_HOME:-${devuser_home}/.version-fox}"
export PATH="${devuser_home}/.local/npm-global/bin:${PATH}"

find_node_bin() {
    local candidate=""
    local nullglob_was_set=0

    if shopt -q nullglob; then
        nullglob_was_set=1
    fi
    shopt -s nullglob

    # vfox 在不同版本里会把 Node 安装到不同层级，这里直接找可执行 node，
    # 避免在非登录 shell 中再次 eval `vfox activate bash` 导致包装脚本自身失败。
    for candidate in \
        "${VFOX_HOME}/bin" \
        "${VFOX_HOME}/shims" \
        "${VFOX_HOME}/sdks/nodejs/current/bin" \
        "${VFOX_HOME}/sdks/nodejs"/*/bin \
        "${VFOX_HOME}/sdks/nodejs"/*/*/bin \
        "${VFOX_HOME}/cache/nodejs"/*/bin \
        "${VFOX_HOME}/cache/nodejs"/*/*/bin; do
        if [ -x "${candidate}/node" ]; then
            printf '%s\n' "${candidate}"
            if [ "${nullglob_was_set}" -eq 0 ]; then
                shopt -u nullglob
            fi
            return 0
        fi
    done

    if [ "${nullglob_was_set}" -eq 0 ]; then
        shopt -u nullglob
    fi
    return 1
}

if ! command -v node >/dev/null 2>&1; then
    node_bin_dir="$(find_node_bin || true)"
    if [ -n "${node_bin_dir}" ]; then
        export PATH="${node_bin_dir}:${PATH}"
    fi
fi

if [ "${current_uid}" -eq 0 ] && command -v "${gosu_cmd}" >/dev/null 2>&1; then
    exec "${gosu_cmd}" "${runtime_user}" env VFOX_HOME="${VFOX_HOME}" PATH="${PATH}" "$target" "$@"
fi

exec "$target" "$@"
