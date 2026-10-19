#!/usr/bin/env bash

set -Eeuo pipefail

readonly engine_root="/app/deepin-wine10-stable"
command_name="$(basename -- "$0")"

export PATH="/app/bin:${engine_root}/bin:${PATH}"
export LD_LIBRARY_PATH="${engine_root}/lib:/app/lib/deepin-compat:/app/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export WINEDLLPATH="${engine_root}/lib/wine"
# 与企业微信保持引擎、Unix 驱动、PE 模块和 wineserver 的 ABI 配对。
export WINEPREDLL="/app/share/wechat-devtools-deepin/dlls"
export ATTACH_FILE_DIALOG=1
export WINE_FORCE_PORTAL="${WINE_FORCE_PORTAL:-1}"
export WINE_WMCLASS="wechat-devtools-wine"

exec "${engine_root}/bin/${command_name}" "$@"
