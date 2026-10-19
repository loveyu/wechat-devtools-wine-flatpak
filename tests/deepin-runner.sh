#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export XDG_DATA_HOME="${TEST_ROOT}/data"
export XDG_STATE_HOME="${TEST_ROOT}/state"
export XDG_CACHE_HOME="${TEST_ROOT}/cache"
unset WECHAT_DEVTOOLS_RUNNER_VARIANT WECHAT_DEVTOOLS_DATA_DIR \
    WECHAT_DEVTOOLS_STATE_DIR WECHAT_DEVTOOLS_CACHE_DIR

source "${PROJECT_DIR}/scripts/common.sh"
[[ "${RUNNER_REF}" == io.github.loveyu.WeChatDevToolsWine//stable-25.08 ]]
[[ "${WINEARCH_VALUE}" == win64 ]]
[[ "${WINEPREFIX_HOST}" == "${TEST_ROOT}/data/wechat-devtools-wine-flatpak-deepin/wine-prefix" ]]
mapfile -t args < <(electron_compatibility_args)
[[ "${args[*]}" == '--no-sandbox --use-angle=d3d11' ]]
[[ "$(electron_compatibility_args --no-sandbox --use-angle=gl)" == '' ]]

# 默认、Staging 和历史基线不能落到同一个前缀，切换引擎也不能混用前缀。
"${PROJECT_DIR}/scripts/with-staging-runner.sh" bash -c '
    source "$1/scripts/common.sh"
    [[ "${RUNNER_REF}" == io.github.loveyu.WeChatDevToolsWine//staging-25.08 ]]
    [[ "${WINEARCH_VALUE}" == wow64 ]]
    [[ "${DATA_DIR}" == "${XDG_DATA_HOME}/wechat-devtools-wine-flatpak-staging" ]]
    [[ "$(electron_compatibility_args)" == "" ]]
' sh "${PROJECT_DIR}"
WECHAT_DEVTOOLS_RUNNER_VARIANT=baseline bash -c '
    source "$1/scripts/common.sh"
    [[ "${RUNNER_REF}" == io.github.huzhiyu.WeComWine//stable-25.08 ]]
    [[ "${DATA_DIR}" == "${XDG_DATA_HOME}/wechat-devtools-wine-flatpak" ]]
' sh "${PROJECT_DIR}"

mkdir -p "${TEST_ROOT}/bin"
cat > "${TEST_ROOT}/bin/flatpak" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == ps ]]; then
    printf '%s\t%s\n' enterprise-instance io.github.loveyu.WeComWine.Deepin
    if [[ "${MOCK_QUIET:-0}" != 1 ]]; then
        printf '%s\t%s\n' devtools-instance io.github.loveyu.WeChatDevToolsWine
    fi
elif [[ "$1" == kill ]]; then
    printf '%s\n' "$2" >> "${KILL_LOG}"
elif [[ "$1" == run ]]; then
    printf '%s\n' "$*" >> "${RUN_LOG}"
fi
EOF
chmod +x "${TEST_ROOT}/bin/flatpak"
# 即使 instance 文件误留了企业微信 ID，也只能停止开发者工具。
printf '%s\n' enterprise-instance > "${STATE_DIR}/flatpak.instance"
PATH="${TEST_ROOT}/bin:${PATH}" KILL_LOG="${TEST_ROOT}/kills" \
    "${PROJECT_DIR}/scripts/stop.sh"
[[ "$(cat "${TEST_ROOT}/kills")" == devtools-instance ]]

# 源和目标指向同一前缀时，在停止实例或写入数据之前拒绝迁移。
set +e
PATH="${TEST_ROOT}/bin:${PATH}" \
WECHAT_DEVTOOLS_STAGING_DATA_DIR="${DATA_DIR}" \
    "${PROJECT_DIR}/scripts/migrate-to-deepin.sh" > "${TEST_ROOT}/migration.log" 2>&1
migration_exit="$?"
set -e
[[ "${migration_exit}" == 64 ]]
grep -Fq '源前缀与目标前缀不能相同' "${TEST_ROOT}/migration.log"

source_data="${TEST_ROOT}/old-data"
source_state="${TEST_ROOT}/old-state"
mkdir -p "${source_data}/wine-prefix/drive_c/DevTools" "${source_state}/repairs/codicon"
printf '%s\n' old-registry > "${source_data}/wine-prefix/system.reg"
printf '%s\n' user-profile > "${source_data}/wine-prefix/account.fixture"
printf '%s\n' app > "${source_data}/wine-prefix/drive_c/DevTools/devtools.fixture"
printf '%s\n' "${source_data}/wine-prefix/drive_c/DevTools/devtools.fixture" \
    > "${source_state}/program.host-path"
printf '%s\n' 'C:\DevTools\devtools.fixture' > "${source_state}/program.windows-path"
printf '%s\n' fixture-version > "${source_state}/installed.version"
printf '%s\n' original-font > "${source_state}/repairs/codicon/backup.fixture"

PATH="${TEST_ROOT}/bin:${PATH}" MOCK_QUIET=1 RUN_LOG="${TEST_ROOT}/runs" \
WECHAT_DEVTOOLS_STAGING_DATA_DIR="${source_data}" \
WECHAT_DEVTOOLS_STAGING_STATE_DIR="${source_state}" \
    "${PROJECT_DIR}/scripts/migrate-to-deepin.sh"
[[ "$(cat "${WINEPREFIX_HOST}/account.fixture")" == user-profile ]]
[[ "$(cat "${source_data}/wine-prefix/system.reg")" == old-registry ]]
[[ "$(cat "${STATE_DIR}/program.host-path")" == "${WINEPREFIX_HOST}/drive_c/DevTools/devtools.fixture" ]]
cmp "${source_state}/repairs/codicon/backup.fixture" "${STATE_DIR}/repairs/codicon/backup.fixture"
grep -Fq -- '--branch=stable-25.08' "${TEST_ROOT}/runs"
grep -Fq -- "--env=WINEPREFIX=${WINEPREFIX_HOST}" "${TEST_ROOT}/runs"

# 已完成的迁移可重跑，但没有成功标记的非空目标必须拒绝覆盖。
PATH="${TEST_ROOT}/bin:${PATH}" \
    "${PROJECT_DIR}/scripts/migrate-to-deepin.sh" > /dev/null
rm -- "${STATE_DIR}/migrated-from-staging"
set +e
PATH="${TEST_ROOT}/bin:${PATH}" \
WECHAT_DEVTOOLS_STAGING_DATA_DIR="${source_data}" \
WECHAT_DEVTOOLS_STAGING_STATE_DIR="${source_state}" \
    "${PROJECT_DIR}/scripts/migrate-to-deepin.sh" > "${TEST_ROOT}/retry.log" 2>&1
retry_exit="$?"
set -e
[[ "${retry_exit}" == 73 ]]
[[ "$(cat "${WINEPREFIX_HOST}/account.fixture")" == user-profile ]]
