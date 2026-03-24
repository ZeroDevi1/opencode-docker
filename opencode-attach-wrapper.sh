#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
base_wrapper="${script_dir}/opencode"

if [ ! -x "${base_wrapper}" ]; then
    echo "opencode wrapper is not installed at ${base_wrapper}" >&2
    exit 127
fi

attach_url="${OPENCODE_ATTACH_URL:-http://127.0.0.1:4096}"

if [ "$#" -gt 0 ] && [ "$1" = "run" ]; then
    shift

    extra_args=()
    has_attach=0
    has_password=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --attach)
                has_attach=1
                extra_args+=("$1")
                shift
                if [ "$#" -gt 0 ]; then
                    extra_args+=("$1")
                    shift
                fi
                ;;
            --password)
                has_password=1
                extra_args+=("$1")
                shift
                if [ "$#" -gt 0 ]; then
                    extra_args+=("$1")
                    shift
                fi
                ;;
            *)
                extra_args+=("$1")
                shift
                ;;
        esac
    done

    if [ "${has_attach}" -eq 0 ]; then
        extra_args=(--attach "${attach_url}" "${extra_args[@]}")
    fi

    if [ "${has_password}" -eq 0 ] && [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
        extra_args=(--password "${OPENCODE_SERVER_PASSWORD}" "${extra_args[@]}")
    fi

    exec "${base_wrapper}" run "${extra_args[@]}"
fi

exec "${base_wrapper}" "$@"
