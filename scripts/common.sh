#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

APP_SLUG="wechat-devtools-wine-flatpak"
DATA_DIR="${WECHAT_DEVTOOLS_DATA_DIR:-${XDG_DATA_HOME}/${APP_SLUG}}"
STATE_DIR="${WECHAT_DEVTOOLS_STATE_DIR:-${XDG_STATE_HOME}/${APP_SLUG}}"
CACHE_DIR="${WECHAT_DEVTOOLS_CACHE_DIR:-${XDG_CACHE_HOME}/${APP_SLUG}}"
LOG_DIR="${STATE_DIR}/logs"
WINEPREFIX_HOST="${DATA_DIR}/wine-prefix"
WORKSPACE_DIR="${DATA_DIR}/workspace"
SCALE_FACTOR_OVERRIDE="${WECHAT_DEVTOOLS_SCALE_FACTOR:-${DEVTOOLS_SCALE_FACTOR:-}}"

RUNNER_APP="io.github.huzhiyu.WeComWine"
RUNNER_BRANCH="stable-25.08"
RUNNER_REF="${RUNNER_APP}//${RUNNER_BRANCH}"

DEVTOOLS_VERSION="2.02.2608050"
DEVTOOLS_INSTALLER="wechat_devtools_${DEVTOOLS_VERSION}_win32_x64.exe"
DEVTOOLS_URL="https://dldir1.qq.com/WechatWebDev/release/be1ec64cf6184b0fa64091919793f068/${DEVTOOLS_INSTALLER}"
DEVTOOLS_SHA256="34082f779984e1f5654f7e99f7fbaa7402af0e4c3c9574d8441778429069daab"
DEVTOOLS_INSTALLER_HOST="${CACHE_DIR}/${DEVTOOLS_INSTALLER}"

mkdir -p "${DATA_DIR}" "${STATE_DIR}" "${CACHE_DIR}" "${LOG_DIR}" \
    "${WINEPREFIX_HOST}" "${WORKSPACE_DIR}"

write_status() {
    local stage="$1"
    local detail="${2:-}"
    {
        printf 'updated_at=%s\n' "$(date --iso-8601=seconds)"
        printf 'stage=%s\n' "${stage}"
        printf 'detail=%s\n' "${detail}"
    } > "${STATE_DIR}/app.status"
}

load_desktop_environment() {
    local variable value

    for variable in DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS; do
        [[ -n "${!variable:-}" ]] && continue
        value="$(systemctl --user show-environment 2>/dev/null | \
            sed -n "s/^${variable}=//p" | head -n 1)"
        [[ -n "${value}" ]] && export "${variable}=${value}"
    done
}

normalize_scale_factor() {
    local value="$1"

    [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    LC_ALL=C awk -v value="${value}" '
        BEGIN {
            if (value < 0.5 || value > 4) exit 1
            printf "%.4f", value
        }
    ' | sed -e 's/0*$//' -e 's/\.$//'
}

detect_system_scale_factor() {
    local dpi scale

    if [[ -n "${SCALE_FACTOR_OVERRIDE}" ]]; then
        if ! scale="$(normalize_scale_factor "${SCALE_FACTOR_OVERRIDE}")"; then
            printf '无效的缩放倍率：%s（允许范围 0.5-4）\n' \
                "${SCALE_FACTOR_OVERRIDE}" >&2
            return 64
        fi
        printf '%s\n' "${scale}"
        return
    fi

    load_desktop_environment
    dpi="$(xrdb -query 2>/dev/null | awk -F: '
        tolower($1) ~ /^[[:space:]]*xft[.]dpi[[:space:]]*$/ {
            gsub(/[[:space:]]/, "", $2); print $2; exit
        }
    ')"
    if [[ "${dpi}" =~ ^[0-9]+([.][0-9]+)?$ ]] && \
       scale="$(normalize_scale_factor "$(LC_ALL=C awk -v dpi="${dpi}" \
           'BEGIN { printf "%.6f", dpi / 96 }')")"; then
        printf '%s\n' "${scale}"
        return
    fi

    scale="$(kscreen-doctor -o 2>/dev/null | \
        sed $'s/\033\\[[0-9;]*[[:alpha:]]//g' | \
        sed -n 's/^[[:space:]]*Scale:[[:space:]]*//p' | head -n 1)"
    if [[ -n "${scale}" ]] && scale="$(normalize_scale_factor "${scale}")"; then
        printf '%s\n' "${scale}"
        return
    fi

    printf '1\n'
}

scale_factor_to_wine_dpi() {
    LC_ALL=C awk -v scale="$1" 'BEGIN { printf "%d\n", int(scale * 96 + 0.5) }'
}

flatpak_wine() {
    local command_name="$1"
    shift

    load_desktop_environment

    flatpak run \
        --user \
        --branch="${RUNNER_BRANCH}" \
        --arch=x86_64 \
        --nosocket=wayland \
        --filesystem="${WINEPREFIX_HOST}" \
        --filesystem="${CACHE_DIR}:ro" \
        --filesystem="${WORKSPACE_DIR}" \
        --filesystem="${PROJECT_DIR}:ro" \
        --env="WINEPREFIX=${WINEPREFIX_HOST}" \
        --env="WINEARCH=win64" \
        --env="LANG=zh_CN.UTF-8" \
        --env="LC_ALL=zh_CN.UTF-8" \
        --env="XMODIFIERS=@im=fcitx" \
        --env="GTK_IM_MODULE=fcitx" \
        --env="QT_IM_MODULE=fcitx" \
        --env="WINEDEBUG=${WINEDEBUG_VALUE:--all}" \
        --command="${command_name}" \
        "${RUNNER_APP}" "$@"
}

flatpak_wine_scaled() {
    local wine_dpi="$1"
    shift

    flatpak_wine sh -c '
        wine reg.exe add "HKCU\Control Panel\Desktop" \
            /v LogPixels /t REG_DWORD /d "$1" /f >/dev/null
        wine reg.exe add \
            "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts" \
            /v "codicon (TrueType)" /t REG_SZ /d codicon.ttf /f >/dev/null
        wine reg.exe add \
            "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts" \
            /v "Develope-Tool-Icon (TrueType)" /t REG_SZ \
            /d vscode-iconfont-patch.ttf /f >/dev/null
        wine reg.exe delete \
            "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts" \
            /v "Developer-Tool-Icon (TrueType)" /f >/dev/null 2>&1 || true
        shift
        exec "$@"
    ' sh "${wine_dpi}" "$@"
}
