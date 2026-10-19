#!/usr/bin/env bash

set -Eeuo pipefail

: "${WINEPREFIX:?WINEPREFIX 未设置}"

readonly association_version="1"
readonly marker="${WINEPREFIX}/.host-file-open-associations"
readonly progid="WeChatDevTools.HostOpen"
readonly open_command='"C:\windows\system32\winebrowser.exe" "%1"'
readonly browser_commands='/app/bin/wechat-devtools-host-open,xdg-open'

if [[ -f "${marker}" ]] && [[ "$(<"${marker}")" == "${association_version}" ]]; then
    exit 0
fi

for classes_key in \
    'HKCU\Software\Classes' \
    'HKLM\Software\Classes'; do
    wine reg.exe add "${classes_key}\\${progid}" \
        /ve /t REG_SZ /d '宿主系统默认应用' /f >/dev/null
    wine reg.exe add "${classes_key}\\${progid}\\shell\\open\\command" \
        /ve /t REG_SZ /d "${open_command}" /f >/dev/null
    for folder_class in Directory Folder; do
        wine reg.exe add "${classes_key}\\${folder_class}\\shell\\open\\command" \
            /ve /t REG_SZ /d "${open_command}" /f >/dev/null
    done
done

wine reg.exe add 'HKCU\Software\Wine\WineBrowser' \
    /v Browsers /t REG_SZ /d "${browser_commands}" /f >/dev/null

# 仅接管非可执行文档和媒体类型；脚本与可执行文件保留 Wine 默认处理。
for extension in \
    .doc .docx .docm .dot .dotx \
    .xls .xlsx .xlsm .xlsb .csv \
    .ppt .pptx .pptm .pps .ppsx \
    .pdf .txt .rtf .md .odt .ods .odp .wps .et .dps \
    .zip .rar .7z .tar .gz .bz2 .xz \
    .jpg .jpeg .png .gif .bmp .webp .svg .tif .tiff \
    .mp3 .wav .ogg .flac .m4a \
    .mp4 .mkv .avi .mov .webm .wmv \
    .json .xml .html .htm; do
    for classes_key in \
        'HKCU\Software\Classes' \
        'HKLM\Software\Classes'; do
        wine reg.exe add "${classes_key}\\${extension}" \
            /ve /t REG_SZ /d "${progid}" /f >/dev/null
    done
done

printf '%s\n' "${association_version}" > "${marker}"
