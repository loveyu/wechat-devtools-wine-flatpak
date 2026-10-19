#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

PROGRAM_FILE="${STATE_DIR}/program.windows-path"
PROGRAM_HOST_FILE="${STATE_DIR}/program.host-path"
INSTANCE_FILE="${STATE_DIR}/flatpak.instance"
LOG_FILE="${LOG_DIR}/app.log"
LOCK_FILE="${STATE_DIR}/app.lock"
exec 9> "${LOCK_FILE}"
flock -n 9 || exit 75
rotate_log "${LOG_FILE}"
exec >> "${LOG_FILE}" 2>&1

[[ -s "${PROGRAM_FILE}" ]] || "${SCRIPT_DIR}/install.sh"
program_windows="$(<"${PROGRAM_FILE}")"
program_host="$(<"${PROGRAM_HOST_FILE}")"
app_asar="$(dirname -- "${program_host}")/resources/app.asar"
write_status "repairing-codicon" "${app_asar}"
python3 "${SCRIPT_DIR}/repair-codicon-font.py" \
    --archive "${app_asar}" \
    --wine-prefix "${WINEPREFIX_HOST}" \
    --state-dir "${STATE_DIR}"
scale_factor="$(detect_system_scale_factor)"
wine_dpi="$(scale_factor_to_wine_dpi "${scale_factor}")"
launch_args=("$@")
mapfile -t compatibility_args < <(electron_compatibility_args "${launch_args[@]}")
launch_args=("${compatibility_args[@]}" "${launch_args[@]}")
has_scale_argument=0
has_gpu_compositing_argument=0
for argument in "${launch_args[@]}"; do
    if [[ "${argument}" == --force-device-scale-factor=* ]]; then
        has_scale_argument=1
    fi
    case "${argument}" in
        --disable-gpu|--disable-gpu=*|--disable-gpu-compositing|--enable-gpu-compositing)
            has_gpu_compositing_argument=1
            ;;
    esac
done
if [[ "${WECHAT_DEVTOOLS_GPU_COMPOSITING:-software}" == software ]] && \
   (( ! has_gpu_compositing_argument )); then
    launch_args=("--disable-gpu-compositing" "${launch_args[@]}")
elif [[ "${WECHAT_DEVTOOLS_GPU_COMPOSITING:-software}" != hardware ]] && \
     [[ "${WECHAT_DEVTOOLS_GPU_COMPOSITING:-software}" != software ]]; then
    printf '无效的 GPU 合成模式：%s（允许 software 或 hardware）\n' \
        "${WECHAT_DEVTOOLS_GPU_COMPOSITING}" >&2
    exit 64
fi
if (( ! has_scale_argument )); then
    launch_args=("--force-device-scale-factor=${scale_factor}" "${launch_args[@]}")
fi
baseline_instances="$(flatpak ps --columns=instance,application 2>/dev/null | \
    awk -v app="${RUNNER_APP}" '$2 == app {print $1}')"

runner_pid=''
instance_id=''
termination_requested=0
stop_runner() {
    if [[ -n "${instance_id}" ]]; then
        flatpak kill "${instance_id}" 2>/dev/null || true
    fi
    if [[ -n "${runner_pid}" ]]; then
        kill "${runner_pid}" 2>/dev/null || true
    fi
}
request_stop() {
    termination_requested=1
    stop_runner
}
cleanup() {
    stop_runner
    if [[ -n "${instance_id}" ]] && [[ "$(cat "${INSTANCE_FILE}" 2>/dev/null || true)" == "${instance_id}" ]]; then
        rm -f -- "${INSTANCE_FILE}"
    fi
}
trap request_stop TERM INT
trap cleanup EXIT

write_status "starting" "${program_windows},scale=${scale_factor},dpi=${wine_dpi}"
flatpak_wine_scaled "${wine_dpi}" wine "${program_windows}" "${launch_args[@]}" &
runner_pid="$!"

for _ in $(seq 1 30); do
    instance_id="$(flatpak ps --columns=instance,application 2>/dev/null | \
        awk -v app="${RUNNER_APP}" -v old="${baseline_instances}" \
        '$2 == app && index("\n" old "\n", "\n" $1 "\n") == 0 {print $1; exit}')"
    [[ -n "${instance_id}" ]] && break
    sleep 1
done

if [[ -n "${instance_id}" ]]; then
    printf '%s\n' "${instance_id}" > "${INSTANCE_FILE}"
fi
write_status "running" \
    "instance=${instance_id:-unknown},scale=${scale_factor},dpi=${wine_dpi}"

set +e
wait "${runner_pid}"
exit_code="$?"
set -e
if (( termination_requested )); then
    write_status "stopped" "instance=${instance_id:-unknown}"
    exit 0
fi
write_status "exited" "wine=${exit_code}"
exit "${exit_code}"
