#!/bin/bash
# 移除 Home Guard launchd 服務 (保留 data_dir 內的 log 與報告)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "請用 sudo 執行: sudo $0" >&2
    exit 1
fi

for name in receiver analyze; do
    label="com.homeguard.$name"
    launchctl bootout "system/$label" 2>/dev/null || true
    rm -f "/Library/LaunchDaemons/$label.plist"
    echo "已移除 $label"
done
