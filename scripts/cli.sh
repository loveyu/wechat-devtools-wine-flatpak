#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

CLI_WINDOWS='C:\Program Files (x86)\Tencent\微信web开发者工具\cli.bat'
INSTANCE_FILE="${STATE_DIR}/flatpak.instance"

# 微信开发者工具自带的 Node CLI 会直接打开控制台设备；为无人值守调用补一个伪终端。
if [[ ! -t 0 && ! -t 1 && "${WECHAT_DEVTOOLS_CLI_PTY:-0}" != 1 ]] && \
    command -v script >/dev/null 2>&1; then
    command=(env WECHAT_DEVTOOLS_CLI_PTY=1 "$0" "$@")
    printf -v command_line '%q ' "${command[@]}"
    exec script --quiet --return --command "${command_line}" /dev/null
fi

instance_id="$(cat "${INSTANCE_FILE}" 2>/dev/null || true)"
if [[ -n "${instance_id}" ]] && \
    flatpak ps --columns=instance,application 2>/dev/null | \
        awk -v id="${instance_id}" -v app="${RUNNER_APP}" \
            '$1 == id && $2 == app {found=1} END {exit !found}'; then
    load_desktop_environment
    exec flatpak enter "${instance_id}" env \
        "HOME=${HOME}" \
        "XDG_CACHE_HOME=${CACHE_DIR}" \
        "PATH=/app/bin:/usr/bin" \
        "WINEPREFIX=${WINEPREFIX_HOST}" \
        "WINEARCH=win64" \
        "WINEDEBUG=${WINEDEBUG_VALUE:--all}" \
        "LANG=zh_CN.UTF-8" \
        "LC_ALL=zh_CN.UTF-8" \
        /app/bin/wine cmd.exe /d /c call "${CLI_WINDOWS}" "$@"
fi

WINEDEBUG_VALUE="${WINEDEBUG_VALUE:--all}" \
    flatpak_wine wine cmd.exe /d /c call "${CLI_WINDOWS}" "$@"
