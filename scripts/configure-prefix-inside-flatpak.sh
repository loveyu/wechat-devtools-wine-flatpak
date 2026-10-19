#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

wineboot --update
winecfg -v win10
wine reg.exe add 'HKCU\Software\Wine\X11 Driver' \
    /v FileDialogPortal /t REG_SZ /d auto /f
wine reg.exe add 'HKCU\Software\Wine\X11 Driver' /v UseXIM /t REG_SZ /d Y /f
wine reg.exe add 'HKCU\Software\Wine\X11 Driver' /v InputStyle /t REG_SZ /d overthespot /f
# Electron creates auxiliary windows such as “真机调试” as if they were
# frameless, but Wine otherwise asks KWin for a second system title bar. The
# extra non-client area overlaps the app layout when the window is maximized.
wine reg.exe add 'HKCU\Software\Wine\X11 Driver' /v Decorated /t REG_SZ /d N /f
wine reg.exe add 'HKCU\Software\Wine\X11 Driver' /v Managed /t REG_SZ /d Y /f

font_family=''
if [[ -r /run/host/fonts/opentype/noto/NotoSansCJK-Regular.ttc ]]; then
    font_family='Noto Sans CJK SC'
    wine reg.exe add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
        /v 'Noto Sans CJK SC (TrueType)' /t REG_SZ \
        /d 'Z:\run\host\fonts\opentype\noto\NotoSansCJK-Regular.ttc' /f
elif [[ -r /run/host/fonts/truetype/droid/DroidSansFallbackFull.ttf ]]; then
    font_family='Droid Sans Fallback'
    wine reg.exe add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
        /v 'Droid Sans Fallback (TrueType)' /t REG_SZ \
        /d 'Z:\run\host\fonts\truetype\droid\DroidSansFallbackFull.ttf' /f
fi

if [[ -n "${font_family}" ]]; then
    for font_name in SimSun NSimSun SimHei 'Microsoft YaHei' \
        'Microsoft YaHei UI' 'MS Shell Dlg' 'MS Shell Dlg 2'; do
        wine reg.exe add 'HKCU\Software\Wine\Fonts\Replacements' \
            /v "${font_name}" /t REG_SZ /d "${font_family}" /f
    done
fi

if [[ -x /app/bin/wechat-devtools-host-open ]]; then
    "${SCRIPT_DIR}/configure-host-file-open.sh"
fi
wineserver --kill
wineserver --wait
