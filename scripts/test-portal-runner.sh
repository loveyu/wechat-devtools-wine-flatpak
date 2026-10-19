#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

STATUS_FILE="${STATE_DIR}/portal-test.status"
LOCK_FILE="${STATE_DIR}/portal-test.lock"
LOG_FILE="${LOG_DIR}/portal-test.log"
DBUS_LOG="${LOG_DIR}/portal-dbus.log"
TEST_PREFIX="${STATE_DIR}/portal-test-prefix"
TEST_EXE='Z:\app\share\wechat-devtools-portal-tests\portal-smoke.exe'
monitor_pid=''
baseline_instances=''

portal_status() {
    {
        printf 'updated_at=%s\n' "$(date --iso-8601=seconds)"
        printf 'stage=%s\n' "$1"
        printf 'detail=%s\n' "${2:-}"
    } > "${STATUS_FILE}"
}

rotate_log "${LOG_FILE}"
exec >> "${LOG_FILE}" 2>&1
exec 9> "${LOCK_FILE}"
if ! flock -n 9; then
    printf '%s Portal 测试已在运行\n' "$(date --iso-8601=seconds)"
    exit 0
fi

cleanup() {
    if [[ -n "${monitor_pid}" ]]; then
        kill "${monitor_pid}" 2>/dev/null || true
        wait "${monitor_pid}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# 测试使用独立前缀，不与正在运行的开发者工具共享注册表或 wineserver。
WINEPREFIX_HOST="${TEST_PREFIX}"
mkdir -p "${TEST_PREFIX}"
portal_status initialize-prefix "${TEST_PREFIX}"
flatpak_wine sh "${PROJECT_DIR}/scripts/configure-prefix-inside-flatpak.sh"

portal_status running 'Win32+IFileDialog+SHBrowseForFolder'
: > "${DBUS_LOG}"
baseline_instances="$(flatpak ps --columns=instance,application 2>/dev/null | \
    awk -v app="${RUNNER_APP}" '$2 == app {print $1}')"
dbus-monitor --session \
    "type='method_call',interface='org.freedesktop.portal.FileChooser'" \
    >> "${DBUS_LOG}" 2>&1 &
monitor_pid="$!"
sleep 1

export PORTAL_SMOKE_TIMEOUT_MS=3000
for mode in open opena save savea folder ifileopen ifilesave hook; do
    printf '%s test mode=%s\n' "$(date --iso-8601=seconds)" "${mode}"
    set +e
    flatpak_wine wine "${TEST_EXE}" "${mode}"
    test_exit="$?"
    set -e
    printf '%s test mode=%s exit=%s\n' \
        "$(date --iso-8601=seconds)" "${mode}" "${test_exit}"
    while read -r instance_id; do
        [[ -n "${instance_id}" ]] || continue
        if ! grep -Fxq "${instance_id}" <<< "${baseline_instances}"; then
            flatpak kill "${instance_id}" 2>/dev/null || true
        fi
    done < <(flatpak ps --columns=instance,application 2>/dev/null | \
        awk -v app="${RUNNER_APP}" '$2 == app {print $1}')
    sleep 1
done

printf '%s test mode=forced-hook\n' "$(date --iso-8601=seconds)"
set +e
WINE_FORCE_PORTAL=1 flatpak_wine wine "${TEST_EXE}" hook
test_exit="$?"
set -e
printf '%s test mode=forced-hook exit=%s\n' \
    "$(date --iso-8601=seconds)" "${test_exit}"
while read -r instance_id; do
    [[ -n "${instance_id}" ]] || continue
    if ! grep -Fxq "${instance_id}" <<< "${baseline_instances}"; then
        flatpak kill "${instance_id}" 2>/dev/null || true
    fi
done < <(flatpak ps --columns=instance,application 2>/dev/null | \
    awk -v app="${RUNNER_APP}" '$2 == app {print $1}')
sleep 1

cleanup
monitor_pid=''
open_calls="$(grep -c 'member=OpenFile' "${DBUS_LOG}" || true)"
save_calls="$(grep -c 'member=SaveFile' "${DBUS_LOG}" || true)"
if (( open_calls != 5 || save_calls != 3 )); then
    portal_status failed "open=${open_calls},save=${save_calls}"
    exit 31
fi

portal_status complete "open=${open_calls},save=${save_calls}"
printf '%s Portal 测试完成：open=%s, save=%s\n' \
    "$(date --iso-8601=seconds)" "${open_calls}" "${save_calls}"
