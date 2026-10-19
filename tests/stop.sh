#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

install -d "${TEST_ROOT}/bin"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "$1" in' \
    '  ps)' \
    '    printf "%s\\t%s\\n" "wechat-instance" "io.github.loveyu.WeChatDevToolsWine"' \
    '    printf "%s\\t%s\\n" "other-instance" "io.github.loveyu.WeComWine.Deepin"' \
    '    ;;' \
    '  kill)' \
    '    printf "%s\\n" "$2" >> "$FLATPAK_KILL_LOG"' \
    '    ;;' \
    'esac' \
    > "${TEST_ROOT}/bin/flatpak"
chmod +x "${TEST_ROOT}/bin/flatpak"

PATH="${TEST_ROOT}/bin:${PATH}" \
FLATPAK_KILL_LOG="${TEST_ROOT}/kills.log" \
WECHAT_DEVTOOLS_RUNNER_VARIANT=staging \
WECHAT_DEVTOOLS_DATA_DIR="${TEST_ROOT}/data" \
WECHAT_DEVTOOLS_STATE_DIR="${TEST_ROOT}/state" \
WECHAT_DEVTOOLS_CACHE_DIR="${TEST_ROOT}/cache" \
    bash "${PROJECT_DIR}/scripts/stop.sh"

[[ "$(wc -l < "${TEST_ROOT}/kills.log")" == 1 ]]
grep -Fxq 'wechat-instance' "${TEST_ROOT}/kills.log"
