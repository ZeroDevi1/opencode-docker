#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dockerfile="${repo_root}/Dockerfile"
tmp_dir="$(mktemp -d)"
fake_usr_local_bin="${tmp_dir}/usr-local-bin"
fake_bin="${tmp_dir}/bin"
fake_home="${tmp_dir}/home/devuser"
fake_npm_bin="${fake_home}/.local/npm-global/bin"
fake_profile_d="${tmp_dir}/vfox.sh"
fake_profile="${tmp_dir}/.profile"
fake_bashrc="${tmp_dir}/.bashrc"

content="$(<"${dockerfile}")"

cleanup() {
    rm -rf "${tmp_dir}"
}

trap cleanup EXIT

if [[ "${content}" == *'export PATH="/home/devuser/.local/npm-global/bin:$PATH"'* ]]; then
    printf 'Dockerfile still prepends npm-global bin before existing PATH\n' >&2
    exit 1
fi

for expected in \
    'export PATH="$PATH:/home/devuser/.local/npm-global/bin"' \
    'echo '\''export PATH="$PATH:/home/devuser/.local/npm-global/bin"'\''' ; do
    if [[ "${content}" != *"${expected}"* ]]; then
        printf 'Dockerfile is missing expected PATH append fragment: %s\n' "${expected}" >&2
        exit 1
    fi
done

mkdir -p "${fake_usr_local_bin}" "${fake_npm_bin}" "${fake_bin}"

for cli in opencode cc-connect; do
    printf '#!/bin/bash\nprintf wrapper-%s\\n\n' "${cli}" > "${fake_usr_local_bin}/${cli}"
    printf '#!/bin/bash\nprintf raw-%s\\n\n' "${cli}" > "${fake_npm_bin}/${cli}"
    chmod +x "${fake_usr_local_bin}/${cli}" "${fake_npm_bin}/${cli}"
done

cat > "${fake_bin}/vfox" <<'EOF'
#!/bin/bash
if [ "$1" = "activate" ] && [ "$2" = "bash" ]; then
    exit 0
fi
exit 0
EOF
chmod +x "${fake_bin}/vfox"

cat > "${fake_profile_d}" <<EOF
export VFOX_HOME="${fake_home}/.version-fox"
export PATH="\$PATH:${fake_npm_bin}"
eval "\$(vfox activate bash)"
EOF

cat > "${fake_profile}" <<EOF
export PATH="\$PATH:${fake_npm_bin}"
EOF

cp "${fake_profile}" "${fake_bashrc}"

login_shell_output="$(env -i HOME="${fake_home}" PATH="${fake_usr_local_bin}:${fake_bin}:/usr/bin:/bin" bash --noprofile --norc -c '
    source "$1"
    source "$2"
    source "$3"
    command -v opencode
    command -v cc-connect
' bash "${fake_profile_d}" "${fake_profile}" "${fake_bashrc}")"

opencode_path="$(printf '%s\n' "${login_shell_output}" | sed -n '1p')"
cc_connect_path="$(printf '%s\n' "${login_shell_output}" | sed -n '2p')"

if [ "${opencode_path}" != "${fake_usr_local_bin}/opencode" ]; then
    printf 'login shell PATH no longer prefers wrapper opencode\n' >&2
    exit 1
fi

if [ "${cc_connect_path}" != "${fake_usr_local_bin}/cc-connect" ]; then
    printf 'login shell PATH no longer prefers wrapper cc-connect\n' >&2
    exit 1
fi
