#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="${WECHAT_DEVTOOLS_PROJECT_DIR:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
XDG_BIN_HOME="${XDG_BIN_HOME:-${HOME}/.local/bin}"
APP_ID="io.github.loveyu.WeChatDevToolsWine"
DESKTOP_FILE="${APP_ID}.desktop"
APPLICATION_DIR="${XDG_DATA_HOME}/applications"
LAUNCHER_PATH="${XDG_BIN_HOME}/wechat-devtools-wine"
STATE_DIR="${WECHAT_DEVTOOLS_STATE_DIR:-${XDG_STATE_HOME}/wechat-devtools-wine-flatpak-deepin}"
PROGRAM_FILE="${STATE_DIR}/program.host-path"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wechat-devtools-menu.XXXXXX")"

cleanup() {
    rm -rf -- "${TEMP_DIR}"
}
trap cleanup EXIT

install -d "${APPLICATION_DIR}" "${XDG_BIN_HOME}"
ln -sfn "${PROJECT_DIR}/scripts/desktop-launch.sh" "${LAUNCHER_PATH}"
install -m 0644 "${PROJECT_DIR}/desktop/${DESKTOP_FILE}" \
    "${APPLICATION_DIR}/${DESKTOP_FILE}"

icon_source="${WECHAT_DEVTOOLS_ICON_SOURCE:-}"
if [[ -z "${icon_source}" ]] && [[ -s "${PROGRAM_FILE}" ]] && \
   command -v wrestool >/dev/null 2>&1 && command -v convert >/dev/null 2>&1; then
    program_path="$(<"${PROGRAM_FILE}")"
    icon_dib="${TEMP_DIR}/wechat-devtools.dib"
    icon_png="${TEMP_DIR}/wechat-devtools.png"
    if [[ -f "${program_path}" ]] && \
       wrestool -x --raw --type=3 --name=1 --output="${icon_dib}" \
           "${program_path}" 2>/dev/null; then
        header_size="$(od -An -tu4 -j 0 -N 4 "${icon_dib}" | tr -d '[:space:]')"
        width="$(od -An -tu4 -j 4 -N 4 "${icon_dib}" | tr -d '[:space:]')"
        doubled_height="$(od -An -tu4 -j 8 -N 4 "${icon_dib}" | tr -d '[:space:]')"
        bit_count="$(od -An -tu2 -j 14 -N 2 "${icon_dib}" | tr -d '[:space:]')"
        if [[ "${header_size}" == 40 ]] && [[ "${bit_count}" == 32 ]] && \
           (( width > 0 && width <= 1024 && doubled_height > 0 && doubled_height % 2 == 0 )); then
            height=$((doubled_height / 2))
            pixel_bytes=$((width * height * 4))
            if tail -c +41 "${icon_dib}" | head -c "${pixel_bytes}" | \
               convert -size "${width}x${height}" -depth 8 bgra:- -flip "${icon_png}"; then
                icon_source="${icon_png}"
            fi
        fi
    fi
fi

if [[ -n "${icon_source}" ]] && [[ -f "${icon_source}" ]] && \
   command -v convert >/dev/null 2>&1; then
    for size in 16 32 48 64 128 256; do
        icon_dir="${XDG_DATA_HOME}/icons/hicolor/${size}x${size}/apps"
        generated_icon="${TEMP_DIR}/${APP_ID}-${size}.png"
        install -d "${icon_dir}"
        convert "${icon_source}" -resize "${size}x${size}" "${generated_icon}"
        install -m 0644 "${generated_icon}" "${icon_dir}/${APP_ID}.png"
    done
else
    printf '警告：未能从已安装程序提取菜单图标；桌面入口仍已安装。\n' >&2
fi

desktop-file-validate "${APPLICATION_DIR}/${DESKTOP_FILE}"
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APPLICATION_DIR}" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache --force --ignore-theme-index \
        "${XDG_DATA_HOME}/icons/hicolor" >/dev/null 2>&1 || true
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
fi

printf '已安装启动菜单：%s\n' "${APPLICATION_DIR}/${DESKTOP_FILE}"
