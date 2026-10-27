#!/bin/bash
# 安裝 Home Guard 為 launchd 系統服務 (需要 sudo)
#   sudo ./install.sh                 # 每 15 分鐘分析一次
#   sudo INTERVAL=600 ./install.sh    # 自訂間隔 (秒)
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG:-$APP_DIR/config.toml}"
INTERVAL="${INTERVAL:-900}"
LOG_DIR=/var/log/home-guard

if [[ $EUID -ne 0 ]]; then
    echo "請用 sudo 執行: sudo $0" >&2
    exit 1
fi

if [[ -z "${PYTHON:-}" ]]; then
    for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
        if [[ -x $candidate ]]; then PYTHON=$candidate; break; fi
    done
fi
if [[ -z "${PYTHON:-}" ]]; then
    echo "找不到 python3,請先 brew install python" >&2
    exit 1
fi

if ! "$PYTHON" -c 'import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli' 2>/dev/null; then
    echo "$PYTHON 版本太舊 (需要 3.11+),請 brew install python 或 $PYTHON -m pip install tomli" >&2
    exit 1
fi

if [[ ! -f $CONFIG ]]; then
    echo "找不到 $CONFIG,請先: cp config.example.toml config.toml 並編輯" >&2
    exit 1
fi
chmod 600 "$CONFIG"

case "$APP_DIR" in
    */Desktop/*|*/Documents/*|*/Downloads/*)
        echo "警告: $APP_DIR 在受 macOS 隱私保護的資料夾內,背景服務可能無法讀取。" >&2
        echo "      建議移到例如 ~/claudecode/home-guard" >&2
        ;;
esac

# Validate the config before installing anything.
(cd "$APP_DIR" && "$PYTHON" -c "from homeguard.config import load_config; load_config('$CONFIG')")

mkdir -p "$LOG_DIR"

for name in receiver analyze; do
    label="com.homeguard.$name"
    dest="/Library/LaunchDaemons/$label.plist"
    sed -e "s|__PYTHON__|$PYTHON|g" \
        -e "s|__APP_DIR__|$APP_DIR|g" \
        -e "s|__CONFIG__|$CONFIG|g" \
        -e "s|__INTERVAL__|$INTERVAL|g" \
        "$APP_DIR/launchd/$label.plist" > "$dest"
    chown root:wheel "$dest"
    chmod 644 "$dest"
    launchctl bootout "system/$label" 2>/dev/null || true
    launchctl bootstrap system "$dest"
    echo "已啟動 $label"
done

echo
echo "完成。Python: $PYTHON"
echo "  服務 log:   $LOG_DIR/"
echo "  立即分析:   sudo launchctl kickstart system/com.homeguard.analyze"
echo "  測試通知:   cd $APP_DIR && sudo $PYTHON -m homeguard -c $CONFIG test-notify"
echo "提醒: 若開著 macOS 防火牆,請允許 $PYTHON 接受連入連線 (UDP/TCP 514)。"
