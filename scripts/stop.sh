#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

INSTANCE_FILE="${STATE_DIR}/flatpak.instance"
if [[ -s "${INSTANCE_FILE}" ]]; then
    instance_id="$(<"${INSTANCE_FILE}")"
    if flatpak ps --columns=instance,application 2>/dev/null | \
        awk -v id="${instance_id}" -v app="${RUNNER_APP}" \
            '$1 == id && $2 == app {found=1} END {exit !found}'; then
        flatpak kill "${instance_id}" 2>/dev/null || true
    fi
fi

# Deepin 与 Staging 共用本项目独占的 App ID。切换前收拢两种 runner 的残留
# 实例，避免多个 Electron 进程树耗尽内存；baseline 与其他应用共享，不能兜底。
if [[ "${RUNNER_VARIANT}" != baseline ]]; then
    while IFS=$'\t' read -r instance_id application; do
        [[ "${application}" == "${RUNNER_APP}" ]] || continue
        flatpak kill "${instance_id}" 2>/dev/null || true
    done < <(flatpak ps --columns=instance,application 2>/dev/null || true)
fi

rm -f -- "${INSTANCE_FILE}"

# 等启动脚本释放锁后再返回，连续执行 stop/run 时不会因清理尚未结束而丢失启动。
if [[ "${WECHAT_DEVTOOLS_STOP_WAIT:-1}" == 1 ]]; then
    flock -w 10 "${STATE_DIR}/app.lock" true
fi
