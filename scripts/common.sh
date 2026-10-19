#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

APP_SLUG="wechat-devtools-wine-flatpak"
SCALE_FACTOR_OVERRIDE="${WECHAT_DEVTOOLS_SCALE_FACTOR:-${DEVTOOLS_SCALE_FACTOR:-}}"
WINEDLLOVERRIDES_VALUE="${WECHAT_DEVTOOLS_WINEDLLOVERRIDES:-mscoree,mshtml=}"

DEEPIN_RUNNER_APP="io.github.loveyu.WeChatDevToolsWine"
DEEPIN_RUNNER_BRANCH="stable-25.08"
SHARED_WINE_ID="io.github.loveyu.Wine.Deepin"
SHARED_WINE_BRANCH="10.14deepin11-25.08"
BASELINE_RUNNER_APP="io.github.huzhiyu.WeComWine"
BASELINE_RUNNER_BRANCH="stable-25.08"
STAGING_RUNNER_APP="io.github.loveyu.WeChatDevToolsWine"
STAGING_RUNNER_BRANCH="staging-25.08"
RUNNER_VARIANT="${WECHAT_DEVTOOLS_RUNNER_VARIANT:-deepin}"
case "${RUNNER_VARIANT}" in
    deepin)
        APP_SLUG+="-deepin"
        RUNNER_APP="${DEEPIN_RUNNER_APP}"
        RUNNER_BRANCH="${DEEPIN_RUNNER_BRANCH}"
        WINEARCH_VALUE="win64"
        ;;
    baseline)
        RUNNER_APP="${BASELINE_RUNNER_APP}"
        RUNNER_BRANCH="${BASELINE_RUNNER_BRANCH}"
        WINEARCH_VALUE="win64"
        ;;
    staging)
        APP_SLUG+="-staging"
        RUNNER_APP="${STAGING_RUNNER_APP}"
        RUNNER_BRANCH="${STAGING_RUNNER_BRANCH}"
        WINEARCH_VALUE="wow64"
        ;;
    *)
        printf '不支持的 Wine runner：%s\n' "${RUNNER_VARIANT}" >&2
        exit 64
        ;;
esac
RUNNER_REF="${RUNNER_APP}//${RUNNER_BRANCH}"
DATA_DIR="${WECHAT_DEVTOOLS_DATA_DIR:-${XDG_DATA_HOME}/${APP_SLUG}}"
STATE_DIR="${WECHAT_DEVTOOLS_STATE_DIR:-${XDG_STATE_HOME}/${APP_SLUG}}"
CACHE_DIR="${WECHAT_DEVTOOLS_CACHE_DIR:-${XDG_CACHE_HOME}/${APP_SLUG}}"
LOG_DIR="${STATE_DIR}/logs"
WINEPREFIX_HOST="${DATA_DIR}/wine-prefix"
WORKSPACE_DIR="${DATA_DIR}/workspace"

DEVTOOLS_VERSION="2.02.2608070"
DEVTOOLS_INSTALLER="wechat_devtools_${DEVTOOLS_VERSION}_win32_x64.exe"
DEVTOOLS_URL="https://devtools.wxqcloud.qq.com.cn/WechatWebDev/release/be1ec64cf6184b0fa64091919793f068/${DEVTOOLS_INSTALLER}"
DEVTOOLS_SHA256="a502dead2e4fb6dcb0b5e157e1f2b9ac00c10a20f1940917112a1f8481ed5ed9"
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

rotate_log() {
    local log_file="$1"
    local max_bytes="${2:-52428800}"

    if [[ -f "${log_file}" ]] && (( $(stat -c '%s' "${log_file}") > max_bytes )); then
        mv -f "${log_file}.1" "${log_file}.2" 2>/dev/null || true
        mv -f "${log_file}" "${log_file}.1"
    fi
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

electron_compatibility_args() {
    local argument has_angle=0 has_no_sandbox=0

    [[ "${RUNNER_VARIANT}" == deepin ]] || return 0
    for argument in "$@"; do
        case "${argument}" in
            --use-angle=*|--use-gl=*) has_angle=1 ;;
            --no-sandbox) has_no_sandbox=1 ;;
        esac
    done
    # Deepin Wine 10 无法启动 Electron 36 的沙箱 GPU 进程；显式选择 D3D11
    # 避开其 SwiftShader/Vulkan 初始化失败，外层仍由 Flatpak 隔离。
    if (( ! has_no_sandbox )); then printf '%s\n' --no-sandbox; fi
    if (( ! has_angle )); then printf '%s\n' --use-angle=d3d11; fi
    return 0
}

flatpak_wine() {
    local command_name="$1"
    local -a extra_environment=()
    shift

    load_desktop_environment

    if [[ -n "${PORTAL_SMOKE_TIMEOUT_MS:-}" ]]; then
        extra_environment+=(--env="PORTAL_SMOKE_TIMEOUT_MS=${PORTAL_SMOKE_TIMEOUT_MS}")
    fi
    if [[ -n "${WINE_FORCE_PORTAL:-}" ]]; then
        extra_environment+=(--env="WINE_FORCE_PORTAL=${WINE_FORCE_PORTAL}")
    fi

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
        --env="WINEARCH=${WINEARCH_VALUE}" \
        --env="LANG=zh_CN.UTF-8" \
        --env="LC_ALL=zh_CN.UTF-8" \
        --env="XMODIFIERS=@im=fcitx" \
        --env="GTK_IM_MODULE=fcitx" \
        --env="QT_IM_MODULE=fcitx" \
        --env="WINEDLLOVERRIDES=${WINEDLLOVERRIDES_VALUE}" \
        --env="WINEDEBUG=${WINEDEBUG_VALUE:--all}" \
        "${extra_environment[@]}" \
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
