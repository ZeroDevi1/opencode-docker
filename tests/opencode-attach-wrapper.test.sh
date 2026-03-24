#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper_src="${repo_root}/opencode-attach-wrapper.sh"

tmp_dir="$(mktemp -d)"
fake_bin="${tmp_dir}/bin"
fake_home="${tmp_dir}/home/devuser"
target_dir="${fake_home}/.local/npm-global/bin"
target_path="${target_dir}/opencode"
args_log="${tmp_dir}/args.log"
wrapper_path="${tmp_dir}/opencode-attach"
base_wrapper_path="${tmp_dir}/opencode"

cleanup() {
    rm -rf "${tmp_dir}"
}

trap cleanup EXIT

mkdir -p "${fake_bin}" "${target_dir}"

cat > "${target_path}" <<EOF
#!/bin/bash
printf '%s\n' "\$*" > "${args_log}"
EOF
chmod +x "${target_path}"

cp "${wrapper_src}" "${wrapper_path}"
chmod +x "${wrapper_path}"

cat > "${base_wrapper_path}" <<EOF
#!/bin/bash
exec "${target_path}" "\$@"
EOF
chmod +x "${base_wrapper_path}"

OPENCODE_SERVER_PASSWORD='secret-pass' \
DEVUSER_CLI_HOME="${fake_home}" \
DEVUSER_CLI_CURRENT_UID=1000 \
PATH="${fake_bin}:/usr/bin:/bin" \
"${wrapper_path}" run --dir /workspace/weixin hello

logged_args="$(<"${args_log}")"

for expected_fragment in \
    'run ' \
    '--attach http://127.0.0.1:4096' \
    '--password secret-pass' \
    '--dir /workspace/weixin' \
    'hello'; do
    case "${logged_args}" in
        *"${expected_fragment}"*) ;;
        *)
            printf 'missing run fragment %s in args: %s\n' "${expected_fragment}" "${logged_args}" >&2
            exit 1
            ;;
    esac
done

OPENCODE_SERVER_PASSWORD='secret-pass' \
DEVUSER_CLI_HOME="${fake_home}" \
DEVUSER_CLI_CURRENT_UID=1000 \
PATH="${fake_bin}:/usr/bin:/bin" \
"${wrapper_path}" session list --format json

logged_args="$(<"${args_log}")"

if [ "${logged_args}" != 'session list --format json' ]; then
    printf 'non-run command should pass through unchanged: %s\n' "${logged_args}" >&2
    exit 1
fi

OPENCODE_SERVER_PASSWORD='secret-pass' \
DEVUSER_CLI_HOME="${fake_home}" \
DEVUSER_CLI_CURRENT_UID=1000 \
PATH="${fake_bin}:/usr/bin:/bin" \
"${wrapper_path}" run --attach http://example.test:9999 --password explicit-pass hello

logged_args="$(<"${args_log}")"

if [ "${logged_args}" != 'run --attach http://example.test:9999 --password explicit-pass hello' ]; then
    printf 'explicit attach/password should pass through unchanged: %s\n' "${logged_args}" >&2
    exit 1
fi
