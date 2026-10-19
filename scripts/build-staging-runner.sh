#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

WINE_VERSION="11.17"
WINE_SHA256="8e752e29bba2901ad9f915139345c6ee67184b099d425704d915971ca5c055fc"
WINE_URL="https://dl.winehq.org/wine/source/11.x/wine-11.17.tar.xz"
STAGING_TAG="v11.17"
STAGING_COMMIT="83acf91a00c7db33ac85a704293159fb47aaed24"
STAGING_SHA256="8bbee364a66a97da5ac12e7c64b959537da8e424f46acb08f5384e130ea6ca2d"
STAGING_URL="https://gitlab.winehq.org/wine/wine-staging/-/archive/${STAGING_TAG}/wine-staging-${STAGING_TAG}.tar.gz"

FLATPAK_REMOTE="${WECHAT_DEVTOOLS_FLATPAK_REMOTE:-}"
LOCAL_REMOTE="wechat-devtools-wine-staging-local"
LOCAL_REPO="${DATA_DIR}/staging-flatpak-repo"
BUILD_ROOT="${WECHAT_DEVTOOLS_STAGING_BUILD_ROOT:-${CACHE_DIR}/staging-runner-build/${WINE_VERSION}-${STAGING_COMMIT}}"
SOURCE_CACHE_DIR="${WINE_SOURCE_CACHE_DIR:-${PROJECT_DIR}/../source-cache}"
PORTAL_PATCH_DIR="${PROJECT_DIR}/patches/wine-portal"
PORTAL_PATCH_SIGNATURE="$(sha256sum "${PORTAL_PATCH_DIR}"/*.patch | \
    sha256sum | awk '{print $1}')"
SOURCE_SIGNATURE="${STAGING_COMMIT}:${PORTAL_PATCH_SIGNATURE}"
SOURCE_DIR="${BUILD_ROOT}/source"
STAGING_DIR="${BUILD_ROOT}/wine-staging"
BUILD_DIR="${BUILD_ROOT}/build-wow64"
APP_DIR="${BUILD_ROOT}/appdir-${STAGING_RUNNER_APP}-portal-${PORTAL_PATCH_SIGNATURE:0:12}"
WINE_ARCHIVE="${SOURCE_CACHE_DIR}/wine-${WINE_VERSION}.tar.xz"
STAGING_ARCHIVE="${SOURCE_CACHE_DIR}/wine-staging-${STAGING_TAG}.tar.gz"
STATUS_FILE="${STATE_DIR}/staging-runner-build.status"
LOCK_FILE="${STATE_DIR}/staging-runner-build.lock"
LOG_FILE="${LOG_DIR}/staging-runner-build.log"
BUILD_JOBS="${BUILD_JOBS:-14}"
CONFIGURE_SIGNATURE="${WINE_VERSION}:${SOURCE_SIGNATURE}:new-wow64-without-opencl-v2"

rotate_log "${LOG_FILE}" 104857600
exec >> "${LOG_FILE}" 2>&1
exec 9> "${LOCK_FILE}"
if ! flock -n 9; then
    printf '%s Wine Staging runner 已在构建\n' "$(date --iso-8601=seconds)"
    exit 0
fi

build_status() {
    local stage="$1"
    local detail="${2:-}"
    {
        printf 'updated_at=%s\n' "$(date --iso-8601=seconds)"
        printf 'stage=%s\n' "${stage}"
        printf 'detail=%s\n' "${detail}"
    } > "${STATUS_FILE}"
}

on_error() {
    local exit_code="$?"
    build_status failed "exit=${exit_code},line=${BASH_LINENO[0]:-unknown}"
    exit "${exit_code}"
}
trap on_error ERR

mkdir -p "${BUILD_ROOT}" "${LOCAL_REPO}" "${SOURCE_CACHE_DIR}"
build_status install-sdk "org.freedesktop.Sdk//25.08"
if [[ -z "${FLATPAK_REMOTE}" ]]; then
    for remote_candidate in flathub flathub-wecom; do
        if flatpak remotes --user --columns=name | grep -Fxq "${remote_candidate}"; then
            FLATPAK_REMOTE="${remote_candidate}"
            break
        fi
    done
fi
if [[ -z "${FLATPAK_REMOTE}" ]] || \
   ! flatpak remotes --user --columns=name | grep -Fxq "${FLATPAK_REMOTE}"; then
    printf 'Flatpak remote 不存在：%s\n' "${FLATPAK_REMOTE}" >&2
    exit 69
fi
for sdk_ref in \
    org.freedesktop.Sdk//25.08 \
    org.freedesktop.Sdk.Extension.mingw-w64//25.08; do
    if ! flatpak info --user "${sdk_ref}" >/dev/null 2>&1; then
        flatpak install --user --noninteractive -y --no-deps --no-related \
            "${FLATPAK_REMOTE}" "${sdk_ref}"
    fi
done

download_checked() {
    local url="$1"
    local output="$2"
    local expected="$3"

    if [[ -f "${output}" ]] && \
       [[ "$(sha256sum "${output}" | awk '{print $1}')" != "${expected}" ]]; then
        mv "${output}" "${output}.invalid.$(date +%s)"
    fi
    if [[ ! -f "${output}" ]]; then
        curl --fail --location --continue-at - --retry 20 --retry-all-errors \
            --retry-delay 10 --connect-timeout 30 --output "${output}" "${url}"
    fi
    printf '%s  %s\n' "${expected}" "${output}" | sha256sum --check -
}

build_status download-sources "wine=${WINE_VERSION},staging=${STAGING_TAG}"
download_checked "${WINE_URL}" "${WINE_ARCHIVE}" "${WINE_SHA256}"
download_checked "${STAGING_URL}" "${STAGING_ARCHIVE}" "${STAGING_SHA256}"

build_status apply-staging "${SOURCE_SIGNATURE}"
current_source_signature=''
if [[ -f "${SOURCE_DIR}/.wechat-devtools-source-signature" ]]; then
    current_source_signature="$(<"${SOURCE_DIR}/.wechat-devtools-source-signature")"
fi
if [[ "${current_source_signature}" != "${SOURCE_SIGNATURE}" ]]; then
    prepare_dir="${BUILD_ROOT}/source.prepare.$$"
    staging_prepare="${BUILD_ROOT}/staging.prepare.$$"
    mkdir -p "${prepare_dir}" "${staging_prepare}"
    tar --extract --xz --file="${WINE_ARCHIVE}" --strip-components=1 --directory="${prepare_dir}"
    tar --extract --gzip --file="${STAGING_ARCHIVE}" --strip-components=1 --directory="${staging_prepare}"
    # Wine Staging needs autoreconf while applying patches.  Keep that build
    # dependency inside the Freedesktop SDK instead of installing it on the host.
    flatpak run --user \
        --command=sh \
        --filesystem="${BUILD_ROOT}" \
        org.freedesktop.Sdk//25.08 \
        -c 'python3 "$1/staging/patchinstall.py" DESTDIR="$2" --all' \
        sh "${staging_prepare}" "${prepare_dir}"

    build_status apply-portal "${PORTAL_PATCH_SIGNATURE}"
    for patch_file in "${PORTAL_PATCH_DIR}"/*.patch; do
        patch --directory="${prepare_dir}" --strip=1 --forward --batch \
            --no-backup-if-mismatch --dry-run < "${patch_file}" >/dev/null
        patch --directory="${prepare_dir}" --strip=1 --forward --batch \
            --no-backup-if-mismatch < "${patch_file}"
    done
    printf '%s\n' "${STAGING_COMMIT}" > "${prepare_dir}/.wechat-devtools-staging-patched"
    printf '%s\n' "${SOURCE_SIGNATURE}" > "${prepare_dir}/.wechat-devtools-source-signature"

    previous_source=''
    previous_staging=''
    if [[ -e "${SOURCE_DIR}" ]]; then
        previous_source="${BUILD_ROOT}/source.previous.$$"
        mv "${SOURCE_DIR}" "${previous_source}"
    fi
    if [[ -e "${STAGING_DIR}" ]]; then
        previous_staging="${BUILD_ROOT}/wine-staging.previous.$$"
        mv "${STAGING_DIR}" "${previous_staging}"
    fi
    mv "${prepare_dir}" "${SOURCE_DIR}"
    mv "${staging_prepare}" "${STAGING_DIR}"
    if [[ -n "${previous_source}" ]]; then
        rm -rf -- "${previous_source}"
    fi
    if [[ -n "${previous_staging}" ]]; then
        rm -rf -- "${previous_staging}"
    fi
fi

build_status initialize-appdir "${STAGING_RUNNER_APP}"
mkdir -p "${BUILD_DIR}"
if [[ ! -f "${APP_DIR}/metadata" ]]; then
    flatpak build-init \
        --arch=x86_64 \
        --sdk-extension=org.freedesktop.Sdk.Extension.mingw-w64 \
        "${APP_DIR}" "${STAGING_RUNNER_APP}" \
        org.freedesktop.Sdk org.freedesktop.Platform 25.08
fi

build_status build-new-wow64 "jobs=${BUILD_JOBS}"
flatpak build \
    --allow=devel \
    --bind-mount="/run/build=${BUILD_ROOT}" \
    --env="BUILD_JOBS=${BUILD_JOBS}" \
    --env="CONFIGURE_SIGNATURE=${CONFIGURE_SIGNATURE}" \
    "${APP_DIR}" bash -lc '
        set -Eeuo pipefail
        export PATH="/usr/lib/sdk/mingw-w64/bin:${PATH}"
        cd /run/build/build-wow64
        if [[ ! -f Makefile ]] || \
           [[ ! -f .wechat-devtools-configure-signature ]] || \
           [[ "$(< .wechat-devtools-configure-signature)" != "${CONFIGURE_SIGNATURE}" ]]; then
            /run/build/source/configure \
                --prefix=/app \
                --libdir=/app/lib \
                --enable-archs=i386,x86_64 \
                --disable-winemenubuilder \
                --disable-tests \
                --without-opencl
            printf "%s\n" "${CONFIGURE_SIGNATURE}" > .wechat-devtools-configure-signature
        fi
        make -j"${BUILD_JOBS}"
        make install \
            LDCONFIG=/bin/true \
            UPDATE_DESKTOP_DATABASE=/bin/true \
            INSTALL_PROGRAM_FLAGS=-s
    '

build_status install-host-integration "portal=${PORTAL_PATCH_SIGNATURE}"
flatpak build \
    --allow=devel \
    --bind-mount="/run/project=${PROJECT_DIR}" \
    "${APP_DIR}" bash -lc '
        set -Eeuo pipefail
        export PATH="/usr/lib/sdk/mingw-w64/bin:${PATH}"
        install -m 0755 /run/project/scripts/wechat-devtools-host-open.sh \
            /app/bin/wechat-devtools-host-open
        install -d -m 0755 /app/share/wechat-devtools-portal-tests
        x86_64-w64-mingw32-gcc -municode -O2 -s \
            -o /app/share/wechat-devtools-portal-tests/portal-smoke.exe \
            /run/project/tests/portal-smoke.c \
            -lcomdlg32 -lshell32 -lole32 -luuid
    '

build_status finish-flatpak "${STAGING_RUNNER_APP}"
if [[ ! -f "${APP_DIR}/.wechat-devtools-finished" ]]; then
    mkdir -p \
        "${APP_DIR}/files/share/wine/gecko" \
        "${APP_DIR}/files/share/wine/mono"
    flatpak build-finish \
        --command=wine \
        --share=ipc \
        --share=network \
        --allow=multiarch \
        --socket=x11 \
        --socket=pulseaudio \
        --device=dri \
        --filesystem=xdg-download/WeChatDevTools:create \
        --talk-name=org.freedesktop.FileManager1 \
        --env=WINEPREFIX=/var/data/wine-wechat-devtools \
        --extension=org.winehq.Wine.gecko=directory=share/wine/gecko \
        --extension=org.winehq.Wine.gecko=version=stable-25.08 \
        --extension=org.winehq.Wine.mono=directory=share/wine/mono \
        --extension=org.winehq.Wine.mono=version=stable-25.08 \
        "${APP_DIR}"
    printf '%s\n' "${STAGING_COMMIT}" > "${APP_DIR}/.wechat-devtools-finished"
fi

build_status export-flatpak "${LOCAL_REPO}"
flatpak build-export --disable-fsync \
    --subject="Wine ${WINE_VERSION} Staging ${STAGING_TAG} new WoW64 with Portal for WeChat DevTools" \
    "${LOCAL_REPO}" "${APP_DIR}" "${STAGING_RUNNER_BRANCH}"

local_url="file://${LOCAL_REPO}"
if flatpak remotes --user --columns=name | grep -Fxq "${LOCAL_REMOTE}"; then
    flatpak remote-modify --user --url="${local_url}" "${LOCAL_REMOTE}"
else
    flatpak remote-add --user --if-not-exists --no-gpg-verify \
        "${LOCAL_REMOTE}" "${local_url}"
fi

build_status install-flatpak "${STAGING_RUNNER_APP}//${STAGING_RUNNER_BRANCH}"
flatpak install --user --noninteractive -y --reinstall --no-deps --no-related \
    "${LOCAL_REMOTE}" "${STAGING_RUNNER_APP}//${STAGING_RUNNER_BRANCH}"

build_status complete "${STAGING_RUNNER_APP}//${STAGING_RUNNER_BRANCH}"
printf '%s Wine Staging runner 构建完成\n' "$(date --iso-8601=seconds)"
