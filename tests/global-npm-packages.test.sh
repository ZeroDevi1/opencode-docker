#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dockerfile="${repo_root}/Dockerfile"
entrypoint="${repo_root}/entrypoint.sh"
readme="${repo_root}/README.md"

docker_pkg='@gsd-build/sdk'
runtime_pkg='@gsd-build/sdk'
readme_pkg='`@gsd-build/sdk`'
readme_cmd='gsd-sdk --version'

if ! grep -Fq "${docker_pkg}" "${dockerfile}"; then
    printf 'Dockerfile is missing %s in global npm install\n' "${docker_pkg}" >&2
    exit 1
fi

if ! grep -Fq "${runtime_pkg}" "${entrypoint}"; then
    printf 'entrypoint.sh is missing %s in VFOX_GLOBAL_NPM_PACKAGES\n' "${runtime_pkg}" >&2
    exit 1
fi

if ! grep -Fq "${readme_pkg}" "${readme}"; then
    printf 'README.md is missing %s in default global npm packages\n' "${docker_pkg}" >&2
    exit 1
fi

if ! grep -Fq "${readme_cmd}" "${readme}"; then
    printf 'README.md is missing %s in verification command\n' "${readme_cmd}" >&2
    exit 1
fi
