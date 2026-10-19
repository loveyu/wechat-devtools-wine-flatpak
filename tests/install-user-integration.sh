#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

printf '%s\n' \
    'P3' \
    '2 2' \
    '255' \
    '7 193 96  255 255 255' \
    '255 255 255  7 193 96' \
    > "${TEST_ROOT}/icon.ppm"

HOME="${TEST_ROOT}/home" \
XDG_DATA_HOME="${TEST_ROOT}/data" \
XDG_STATE_HOME="${TEST_ROOT}/state" \
XDG_BIN_HOME="${TEST_ROOT}/bin" \
WECHAT_DEVTOOLS_PROJECT_DIR="${PROJECT_DIR}" \
WECHAT_DEVTOOLS_ICON_SOURCE="${TEST_ROOT}/icon.ppm" \
    bash "${PROJECT_DIR}/scripts/install-user-integration.sh" \
        > "${TEST_ROOT}/install.log"

desktop_file="${TEST_ROOT}/data/applications/io.github.loveyu.WeChatDevToolsWine.desktop"
launcher="${TEST_ROOT}/bin/wechat-devtools-wine"
icon="${TEST_ROOT}/data/icons/hicolor/256x256/apps/io.github.loveyu.WeChatDevToolsWine.png"
[[ -f "${desktop_file}" ]]
[[ -L "${launcher}" ]]
[[ "$(readlink -f -- "${launcher}")" == "${PROJECT_DIR}/scripts/desktop-launch.sh" ]]
[[ -f "${icon}" ]]
desktop-file-validate "${desktop_file}"
grep -Fq 'Exec=wechat-devtools-wine' "${desktop_file}"
grep -Fq "已安装启动菜单：${desktop_file}" "${TEST_ROOT}/install.log"
