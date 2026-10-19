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
for command_name in wine wineboot winecfg wineserver; do
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\\t%s\\n" "$(basename -- "$0")" "$*" >> "$PREFIX_COMMAND_LOG"' \
        > "${TEST_ROOT}/bin/${command_name}"
    chmod +x "${TEST_ROOT}/bin/${command_name}"
done

PATH="${TEST_ROOT}/bin:${PATH}" \
PREFIX_COMMAND_LOG="${TEST_ROOT}/commands.log" \
    bash "${PROJECT_DIR}/scripts/configure-prefix-inside-flatpak.sh"

grep -Fq $'wine\treg.exe add HKCU\\Software\\Wine\\X11 Driver /v Decorated /t REG_SZ /d N /f' \
    "${TEST_ROOT}/commands.log"
grep -Fq $'wine\treg.exe add HKCU\\Software\\Wine\\X11 Driver /v Managed /t REG_SZ /d Y /f' \
    "${TEST_ROOT}/commands.log"
