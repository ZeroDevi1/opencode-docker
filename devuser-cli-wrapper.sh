#!/bin/bash
set -euo pipefail

cli_name="$(basename "$0")"
target="/home/devuser/.local/npm-global/bin/${cli_name}"

if [ ! -x "$target" ]; then
    echo "${cli_name} is not installed at ${target}" >&2
    exit 127
fi

export VFOX_HOME="${VFOX_HOME:-/home/devuser/.version-fox}"
export PATH="/home/devuser/.local/npm-global/bin:${PATH}"

if command -v vfox >/dev/null 2>&1; then
    eval "$(vfox activate bash)"
fi

exec "$target" "$@"
