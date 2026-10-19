#!/usr/bin/env bash

set -Eeuo pipefail

target="${1:-}"
if [[ -z "${target}" ]]; then
    exit 64
fi

gdbus_command="${WECHAT_DEVTOOLS_GDBUS_COMMAND:-gdbus}"
xdg_open_command="${WECHAT_DEVTOOLS_XDG_OPEN_COMMAND:-xdg-open}"
getfattr_command="${WECHAT_DEVTOOLS_GETFATTR_COMMAND:-getfattr}"
python_command="${WECHAT_DEVTOOLS_PYTHON_COMMAND:-python3}"

resolve_document_portal_uri() {
    local portal_uri="$1"
    local portal_path=''
    local portal_root=''
    local portal_relative_path=''
    local host_root="${WECHAT_DEVTOOLS_DOCUMENT_PORTAL_HOST_PATH:-}"

    portal_path="$("${python_command}" -c \
        'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlsplit(sys.argv[1]).path))' \
        "${portal_uri}")" || return 1
    if [[ "${portal_path}" =~ ^(/run/user/[[:digit:]]+/doc/[^/]+)/(.*)$ ]] || \
       [[ "${portal_path}" =~ ^(/run/flatpak/doc/[^/]+)/(.*)$ ]]; then
        portal_root="${BASH_REMATCH[1]}"
        portal_relative_path="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    if [[ -z "${host_root}" ]]; then
        host_root="$("${getfattr_command}" --only-values \
            -n user.document-portal.host-path "${portal_root}" 2>/dev/null)" || return 1
    fi
    [[ "${host_root}" == /* && -n "${portal_relative_path}" ]] || return 1

    "${python_command}" -c \
        'import pathlib, sys; print(pathlib.Path(sys.argv[1]).as_uri())' \
        "${host_root%/}/${portal_relative_path}"
}

case "${target}" in
    wechat-devtools-select:file:///[Cc]:/*)
        # 本项目把宿主前缀以同一路径挂入 Flatpak，可直接还原 C: 文件的宿主路径。
        if [[ "${WINEPREFIX:-}" != /* ]]; then
            printf '无法映射 Flatpak Wine C: 路径：%s\n' "${target}" >&2
            exit 65
        fi
        wine_relative_path="${target#wechat-devtools-select:file:///?:}"
        uri="file://${WINEPREFIX}/drive_c${wine_relative_path}"
        ;;
    wechat-devtools-select:file:///[Zz]:/*)
        # Z: 对应宿主根目录；Document Portal 路径优先反查原始目录。
        uri="file://${target#wechat-devtools-select:file:///?:}"
        if host_uri="$(resolve_document_portal_uri "${uri}")"; then
            uri="${host_uri}"
        fi
        ;;
    wechat-devtools-select:*)
        printf '不支持的 Wine Explorer 选择 URI：%s\n' "${target}" >&2
        exit 65
        ;;
    *)
        exec "${xdg_open_command}" "${target}"
        ;;
esac

escaped_uri="${uri//\\/\\\\}"
escaped_uri="${escaped_uri//\'/\\\'}"
if "${gdbus_command}" call --session \
    --dest org.freedesktop.FileManager1 \
    --object-path /org/freedesktop/FileManager1 \
    --method org.freedesktop.FileManager1.ShowItems \
    "['${escaped_uri}']" '' >/dev/null; then
    exit 0
fi

# FileManager1 是可选接口；失败时至少通过 OpenURI 打开所在目录。
exec "${xdg_open_command}" "${uri%/*}"
