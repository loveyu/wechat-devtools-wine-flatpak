#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

install -d "${TEST_ROOT}/bin" \
    "${TEST_ROOT}/state/wechat-devtools-wine-flatpak-deepin"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\t%s\\n" "test-instance" "io.github.loveyu.WeChatDevToolsWine"' \
    > "${TEST_ROOT}/bin/flatpak"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\n" "$*" > "$WMCTRL_LOG"' \
    > "${TEST_ROOT}/bin/wmctrl"
chmod +x "${TEST_ROOT}/bin/flatpak" "${TEST_ROOT}/bin/wmctrl"
printf '%s\n' 'test-instance' \
    > "${TEST_ROOT}/state/wechat-devtools-wine-flatpak-deepin/flatpak.instance"

PATH="${TEST_ROOT}/bin:${PATH}" \
XDG_DATA_HOME="${TEST_ROOT}/data" \
XDG_STATE_HOME="${TEST_ROOT}/state" \
XDG_CACHE_HOME="${TEST_ROOT}/cache" \
WMCTRL_LOG="${TEST_ROOT}/wmctrl.log" \
    bash "${PROJECT_DIR}/scripts/desktop-launch.sh"

grep -Fxq -- '-xa wechat-devtools-wine' "${TEST_ROOT}/wmctrl.log"
