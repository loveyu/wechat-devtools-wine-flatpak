#!/usr/bin/env bash

set -Eeuo pipefail

wineboot --update
winecfg -v win10
wine reg.exe add 'HKCU\Software\Wine\X11 Driver' /v UseXIM /t REG_SZ /d Y /f
wine reg.exe add 'HKCU\Software\Wine\X11 Driver' /v InputStyle /t REG_SZ /d overthespot /f
wine reg.exe add 'HKCU\Software\Wine\X11 Driver' /v Decorated /t REG_SZ /d Y /f
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
wineserver --wait
