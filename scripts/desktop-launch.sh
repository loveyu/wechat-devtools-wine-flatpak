#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd -P)"

source "${SCRIPT_DIR}/common.sh"

INSTANCE_FILE="${STATE_DIR}/flatpak.instance"
instance_id="$(cat "${INSTANCE_FILE}" 2>/dev/null || true)"

if [[ -n "${instance_id}" ]] && flatpak ps --columns=instance,application 2>/dev/null | \
    awk -v instance="${instance_id}" -v app="${RUNNER_APP}" \
        '$1 == instance && $2 == app { found = 1 } END { exit !found }'; then
    load_desktop_environment
    if command -v wmctrl >/dev/null 2>&1; then
        wmctrl -xa 'wechat-devtools-wine' 2>/dev/null || \
            wmctrl -xa '微信开发者工具.exe' 2>/dev/null || \
            wmctrl -a '项目列表' 2>/dev/null || true
    fi
    exit 0
fi

exec "${SCRIPT_DIR}/run.sh" "$@"
