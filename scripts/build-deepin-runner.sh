#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

SOURCE_REF="runtime/${SHARED_WINE_ID}//${SHARED_WINE_BRANCH}"
SOURCE_DIR="$(flatpak info --user --show-location "${SOURCE_REF}")/files"
SOURCE_COMMIT="$(flatpak info --user --show-commit "${SOURCE_REF}")"
BUILD_ROOT="${WECHAT_DEVTOOLS_DEEPIN_BUILD_ROOT:-${CACHE_DIR}/deepin-runner-build}"
LOCAL_REPO="${DATA_DIR}/deepin-flatpak-repo"
LOCAL_REMOTE="wechat-devtools-wine-deepin-local"
LOG_FILE="${LOG_DIR}/deepin-runner-build.log"

exec 9> "${STATE_DIR}/deepin-runner-build.lock"
flock -n 9 || exit 75
rotate_log "${LOG_FILE}"
exec >> "${LOG_FILE}" 2>&1

for required_path in \
    deepin-wine10-stable/bin/wine \
    deepin-wine10-stable/bin/wineserver \
    deepin-wine10-stable/lib/wine/x86_64-unix/comdlg32.so \
    adapter-dlls/x86_64-windows/user32.dll \
    lib/deepin-compat; do
    if [[ ! -e "${SOURCE_DIR}/${required_path}" ]]; then
        printf '共享 Wine 基础包缺少文件：%s\n' "${required_path}" >&2
        exit 65
    fi
done
# 每次使用新 appdir，失败的构建和旧版本均可保留；不复制企业微信程序或前缀。
mkdir -p "${BUILD_ROOT}" "${LOCAL_REPO}"
APP_DIR="$(mktemp -d "${BUILD_ROOT}/appdir.XXXXXX")"
flatpak build-init --arch=x86_64 \
    --sdk-extension=org.freedesktop.Sdk.Extension.mingw-w64 \
    "${APP_DIR}" "${DEEPIN_RUNNER_APP}" \
    org.freedesktop.Sdk org.freedesktop.Platform 25.08
files="${APP_DIR}/files"
mkdir -p "${files}/bin" "${files}/lib" \
    "${files}/shared-wine" \
    "${files}/share/wechat-devtools-deepin" \
    "${files}/share/doc/wechat-devtools-deepin" \
    "${files}/share/wechat-devtools-portal-tests"
# 共享扩展挂载到固定路径，应用层只保存链接和专属集成脚本。
ln -s /app/shared-wine/deepin-wine10-stable "${files}/deepin-wine10-stable"
ln -s /app/shared-wine/lib/deepin-compat "${files}/lib/deepin-compat"
ln -s /app/shared-wine/adapter-dlls "${files}/share/wechat-devtools-deepin/dlls"
while IFS= read -r -d '' library; do
    ln -s "/app/shared-wine/lib/$(basename -- "${library}")" "${files}/lib/"
done < <(find "${SOURCE_DIR}/lib" -maxdepth 1 -name '*.so*' -print0)
for library_dir in samba krb5; do
    ln -s "/app/shared-wine/lib/${library_dir}" "${files}/lib/"
done
ln -s /app/shared-wine/bin/ntlm_auth "${files}/bin/ntlm_auth"
install -m 0755 "${SCRIPT_DIR}/deepin-wine-wrapper.sh" "${files}/bin/wine"
for command_name in wineboot winecfg winepath wineserver; do
    ln -s wine "${files}/bin/${command_name}"
done
install -m 0755 "${SCRIPT_DIR}/wechat-devtools-host-open.sh" \
    "${files}/bin/wechat-devtools-host-open"
flatpak build --allow=devel \
    --bind-mount="/run/project=${PROJECT_DIR}" \
    "${APP_DIR}" /usr/lib/sdk/mingw-w64/bin/x86_64-w64-mingw32-gcc \
    -municode -O2 -s \
    -o /app/share/wechat-devtools-portal-tests/portal-smoke.exe \
    /run/project/tests/portal-smoke.c -lcomdlg32 -lshell32 -lole32 -luuid
{
    printf 'source_ref=%s\nsource_commit=%s\n' "${SOURCE_REF}" "${SOURCE_COMMIT}"
} > "${files}/share/doc/wechat-devtools-deepin/source.txt"

flatpak build-finish --command=wine \
    --share=ipc --share=network --allow=multiarch \
    --socket=x11 --socket=pulseaudio --device=dri \
    --filesystem=xdg-download/WeChatDevTools:create \
    --talk-name=org.freedesktop.FileManager1 \
    --extension="${SHARED_WINE_ID}=directory=shared-wine" \
    --extension="${SHARED_WINE_ID}=version=${SHARED_WINE_BRANCH}" \
    --extension="${SHARED_WINE_ID}=autodelete=false" \
    --env=WINEPREFIX=/var/data/wine-wechat-devtools \
    --env=LD_LIBRARY_PATH=/app/lib/deepin-compat:/app/lib \
    "${APP_DIR}"
flatpak build-export --disable-fsync \
    --subject="WeChat DevTools application layer with shared Deepin Wine ${SOURCE_COMMIT:0:12}" \
    "${LOCAL_REPO}" "${APP_DIR}" "${DEEPIN_RUNNER_BRANCH}"
flatpak remote-add --user --if-not-exists --no-gpg-verify \
    "${LOCAL_REMOTE}" "file://${LOCAL_REPO}"
flatpak remote-modify --user --url="file://${LOCAL_REPO}" "${LOCAL_REMOTE}"
flatpak install --user --noninteractive -y --reinstall --no-deps --no-related \
    "${LOCAL_REMOTE}" "${DEEPIN_RUNNER_APP}//${DEEPIN_RUNNER_BRANCH}"
printf '%s Deepin runner 构建完成，来源 %s\n' \
    "$(date --iso-8601=seconds)" "${SOURCE_COMMIT}"
