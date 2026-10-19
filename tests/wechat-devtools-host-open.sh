#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
HOST_OPEN="${PROJECT_DIR}/scripts/wechat-devtools-host-open.sh"

run_fallback() {
    HOME=/home/tester \
    FLATPAK_ID=io.github.loveyu.WeChatDevToolsWine \
    WINEPREFIX=/home/tester/.local/share/wechat-devtools-wine-flatpak-staging/wine-prefix \
    WECHAT_DEVTOOLS_GDBUS_COMMAND=/usr/bin/false \
    WECHAT_DEVTOOLS_XDG_OPEN_COMMAND=/usr/bin/echo \
        bash "${HOST_OPEN}" "$1"
}

run_portal_fallback() {
    WECHAT_DEVTOOLS_DOCUMENT_PORTAL_HOST_PATH='/data/客户 项目' run_fallback "$1"
}

c_result="$(run_fallback \
    'wechat-devtools-select:file:///C:/users/tester/Documents/%E6%BC%94%E7%A4%BA/report.png')"
[[ "${c_result}" == \
    'file:///home/tester/.local/share/wechat-devtools-wine-flatpak-staging/wine-prefix/drive_c/users/tester/Documents/%E6%BC%94%E7%A4%BA' ]]

z_result="$(run_portal_fallback \
    'wechat-devtools-select:file:///Z:/run/user/1000/doc/abc123/%E9%A1%B9%E7%9B%AE%20%E9%85%8D%E7%BD%AE.json')"
[[ "${z_result}" == 'file:///data/%E5%AE%A2%E6%88%B7%20%E9%A1%B9%E7%9B%AE' ]]

data_result="$(run_fallback \
    'wechat-devtools-select:file:///Z:/data/code/demo/mini.project.json')"
[[ "${data_result}" == 'file:///data/code/demo' ]]

if run_fallback 'wechat-devtools-select:file:///D:/unsupported.txt' >/dev/null 2>&1; then
    printf '不支持的驱动器不应交给宿主文件管理器\n' >&2
    exit 1
fi

plain_result="$(run_fallback 'file:///data/code/demo')"
[[ "${plain_result}" == 'file:///data/code/demo' ]]
