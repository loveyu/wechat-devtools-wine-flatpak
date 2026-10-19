#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

if [[ "${RUNNER_VARIANT}" != deepin ]]; then
    printf '迁移必须使用默认 Deepin runner。\n' >&2
    exit 64
fi
SOURCE_DATA="${WECHAT_DEVTOOLS_STAGING_DATA_DIR:-${XDG_DATA_HOME}/wechat-devtools-wine-flatpak-staging}"
SOURCE_STATE="${WECHAT_DEVTOOLS_STAGING_STATE_DIR:-${XDG_STATE_HOME}/wechat-devtools-wine-flatpak-staging}"
SOURCE_PREFIX="${SOURCE_DATA}/wine-prefix"
MARKER="${STATE_DIR}/migrated-from-staging"

exec 9> "${STATE_DIR}/app.lock"
flock -n 9 || exit 75
exec 8> "${STATE_DIR}/install.lock"
flock -n 8 || exit 75
flatpak info --user "${RUNNER_REF}" >/dev/null
if [[ -f "${MARKER}" ]]; then
    printf '已迁移到 Deepin：%s\n' "${WINEPREFIX_HOST}"
    exit 0
fi
if [[ "$(realpath -m -- "${SOURCE_PREFIX}")" == "$(realpath -m -- "${WINEPREFIX_HOST}")" ]]; then
    printf '源前缀与目标前缀不能相同。\n' >&2
    exit 64
fi
if [[ ! -f "${SOURCE_PREFIX}/system.reg" ]] || \
   [[ ! -s "${SOURCE_STATE}/program.host-path" ]] || \
   [[ ! -s "${SOURCE_STATE}/program.windows-path" ]]; then
    printf '找不到已安装的 Staging 前缀；全新安装请使用 make install。\n' >&2
    exit 66
fi
program_source="$(<"${SOURCE_STATE}/program.host-path")"
if [[ "${program_source}" != "${SOURCE_PREFIX}/"* ]] || [[ ! -f "${program_source}" ]]; then
    printf '程序路径不在源前缀内或文件缺失：%s\n' "${program_source}" >&2
    exit 65
fi
if [[ -n "$(find "${WINEPREFIX_HOST}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    printf '目标前缀已存在，拒绝覆盖：%s\n' "${WINEPREFIX_HOST}" >&2
    exit 73
fi

# 只停止本项目的 App ID，随后持有旧前缀的启动和安装锁直到复制结束。
WECHAT_DEVTOOLS_STOP_WAIT=0 "${SCRIPT_DIR}/stop.sh"
mkdir -p "${SOURCE_STATE}"
exec 7> "${SOURCE_STATE}/app.lock"
flock -w 10 7 || exit 75
exec 6> "${SOURCE_STATE}/install.lock"
flock -n 6 || exit 75
if flatpak ps --columns=application 2>/dev/null | grep -Fxq "${RUNNER_APP}"; then
    printf '开发者工具尚未完全退出，请稍后重试迁移。\n' >&2
    exit 75
fi

LOG_FILE="${LOG_DIR}/deepin-migration.log"
exec >> "${LOG_FILE}" 2>&1
write_status migrating "${SOURCE_PREFIX}"
copy_dir="$(mktemp -d "${DATA_DIR}/wine-prefix.migrating.XXXXXX")"
cp -a --reflink=auto "${SOURCE_PREFIX}/." "${copy_dir}/"
rmdir -- "${WINEPREFIX_HOST}"
mv -- "${copy_dir}" "${WINEPREFIX_HOST}"
if [[ -d "${SOURCE_STATE}/repairs" ]]; then
    cp -a --reflink=auto "${SOURCE_STATE}/repairs" "${STATE_DIR}/"
fi

# wineboot 重新生成当前引擎的 builtin DLL，原 Wine 11 前缀保留在旧目录。
flatpak_wine sh "${PROJECT_DIR}/scripts/configure-prefix-inside-flatpak.sh"
program_host="${WINEPREFIX_HOST}/${program_source#"${SOURCE_PREFIX}/"}"
[[ -f "${program_host}" ]]
printf '%s\n' "${program_host}" > "${STATE_DIR}/program.host-path"
cp -a "${SOURCE_STATE}/program.windows-path" "${STATE_DIR}/"
if [[ -f "${SOURCE_STATE}/installed.version" ]]; then
    cp -a "${SOURCE_STATE}/installed.version" "${STATE_DIR}/"
fi
printf '%s\n' "${SOURCE_PREFIX}" > "${MARKER}"
write_status migrated "${RUNNER_REF}"
printf '%s 已迁移到 %s，原前缀保留在 %s\n' \
    "$(date --iso-8601=seconds)" "${WINEPREFIX_HOST}" "${SOURCE_PREFIX}"
