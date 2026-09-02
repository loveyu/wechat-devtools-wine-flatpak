#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

LOCK_FILE="${STATE_DIR}/install.lock"
LOG_FILE="${LOG_DIR}/install.log"
exec 9> "${LOCK_FILE}"
flock -n 9 || exit 75
exec >> "${LOG_FILE}" 2>&1

on_error() {
    local exit_code="$?"
    write_status "install-failed" "exit=${exit_code},line=${BASH_LINENO[0]:-unknown}"
    exit "${exit_code}"
}
trap on_error ERR

write_status "checking-runner" "${RUNNER_REF}"
flatpak info --user "${RUNNER_REF}"
"${SCRIPT_DIR}/download.sh"

write_status "configuring-prefix" "${WINEPREFIX_HOST}"
flatpak_wine sh "${PROJECT_DIR}/scripts/configure-prefix-inside-flatpak.sh"

program_host="$(find "${WINEPREFIX_HOST}/drive_c" -type f \
    \( -iname 'wechatdevtools.exe' -o -iname '微信开发者工具.exe' \) \
    ! -iname '*uninstall*' -print -quit 2>/dev/null || true)"

if [[ -z "${program_host}" ]]; then
    write_status "installing" "${DEVTOOLS_VERSION}"
    flatpak_wine wine "${DEVTOOLS_INSTALLER_HOST}" /S /allusers
    program_host="$(find "${WINEPREFIX_HOST}/drive_c" -type f \
        \( -iname 'wechatdevtools.exe' -o -iname '微信开发者工具.exe' \) \
        ! -iname '*uninstall*' -print -quit 2>/dev/null || true)"
fi

if [[ -z "${program_host}" ]]; then
    write_status "install-failed" "executable-not-found"
    exit 4
fi

program_relative="${program_host#"${WINEPREFIX_HOST}/drive_c/"}"
program_windows="C:\\$(printf '%s' "${program_relative}" | tr '/' '\\')"
printf '%s\n' "${program_host}" > "${STATE_DIR}/program.host-path"
printf '%s\n' "${program_windows}" > "${STATE_DIR}/program.windows-path"
write_status "installed" "${program_windows}"
