#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper_src="${repo_root}/devuser-cli-wrapper.sh"

tmp_dir="$(mktemp -d)"
fake_bin="${tmp_dir}/bin"
wrapper_bin="${tmp_dir}/wrapper-bin"
sandbox_home="${tmp_dir}/home/devuser"
target_dir="${sandbox_home}/.local/npm-global/bin"
vfox_node_dir="${sandbox_home}/.version-fox/sdks/nodejs/test/bin"
target_path="${target_dir}/opencode"
node_path="${vfox_node_dir}/node"
gosu_log="${tmp_dir}/gosu.log"

cleanup() {
    rm -rf "${tmp_dir}"
}

trap cleanup EXIT

mkdir -p "${fake_bin}" "${wrapper_bin}" "${target_dir}" "${vfox_node_dir}"

cat > "${fake_bin}/vfox" <<'EOF'
#!/bin/bash
printf 'create broken output\n'
EOF
chmod +x "${fake_bin}/vfox"

cat > "${fake_bin}/gosu" <<EOF
#!/bin/bash
printf '%s\n' "\$*" > "${gosu_log}"
user="\$1"
shift
exec "\$@"
EOF
chmod +x "${fake_bin}/gosu"

cat > "${node_path}" <<'EOF'
#!/bin/bash
script="$1"
shift
exec bash "$script" "$@"
EOF
chmod +x "${node_path}"

cat > "${target_path}" <<'EOF'
#!/usr/bin/env node
printf 'wrapper target ok\n'
EOF
chmod +x "${target_path}"

cp "${wrapper_src}" "${wrapper_bin}/opencode"
chmod +x "${wrapper_bin}/opencode"

set +e
output="$(DEVUSER_CLI_HOME="${sandbox_home}" DEVUSER_CLI_CURRENT_UID=0 DEVUSER_CLI_GOSU="${fake_bin}/gosu" PATH="${fake_bin}:/usr/bin:/bin" "${wrapper_bin}/opencode" 2>&1)"
status=$?
set -e

if [ "${status}" -ne 0 ]; then
    printf 'wrapper exited with status %s: %s\n' "${status}" "${output}" >&2
    exit 1
fi

if [ "${output}" != "wrapper target ok" ]; then
    printf 'unexpected output: %s\n' "${output}" >&2
    exit 1
fi

if ! grep -q '^devuser env VFOX_HOME=' "${gosu_log}"; then
    printf 'gosu was not invoked with expected user/env wrapper: %s\n' "$(cat "${gosu_log}" 2>/dev/null || true)" >&2
    exit 1
fi
