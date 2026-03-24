#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/examples/cc-connect.config.toml"
dockerfile="${repo_root}/Dockerfile"

if ! grep -Fq 'cmd = "/usr/local/bin/opencode-attach"' "${config_file}"; then
    printf 'cc-connect template is missing opencode attach cmd\n' >&2
    exit 1
fi

if ! grep -Fq 'COPY opencode-attach-wrapper.sh /usr/local/bin/opencode-attach' "${dockerfile}"; then
    printf 'Dockerfile is missing opencode-attach installation path\n' >&2
    exit 1
fi
