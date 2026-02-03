#!/bin/bash
# ============================================================================
# 串口自动重连（macOS / Linux）
# ============================================================================
#
# 拔掉开发板电源或 USB 后串口会消失，本脚本会持续等待串口重新出现并自动
# 再次打开 minicom/screen，无需手动重连。
#
# 用法:
#   ./scripts/serial_auto_reconnect.sh [波特率] [设备]
#
# 示例:
#   ./scripts/serial_auto_reconnect.sh              # 自动找 /dev/cu.usb*，115200
#   ./scripts/serial_auto_reconnect.sh 115200      # 指定波特率
#   ./scripts/serial_auto_reconnect.sh 115200 /dev/cu.usbserial-1234
#
# 退出: 在 minicom 里 Ctrl+A X，或在 screen 里 Ctrl+A K，退出后脚本会等待串口再现再重连。
#       若想完全退出脚本：在终端按 Ctrl+C。
# ============================================================================

BAUD="${1:-115200}"
DEVICE="$2"

# 自动找串口（优先 cu.，排除蓝牙）
find_serial() {
    if [ -n "$DEVICE" ] && [ -e "$DEVICE" ]; then
        echo "$DEVICE"
        return
    fi
    for d in /dev/cu.usb* /dev/cu.usbserial* /dev/tty.usb* /dev/ttyUSB* /dev/ttyACM*; do
        [ -e "$d" ] && echo "$d" && return
    done 2>/dev/null
    ls -1 /dev/cu.* 2>/dev/null | grep -vi bluetooth | head -1
}

wait_for_port() {
    while true; do
        PORT=$(find_serial)
        if [ -n "$PORT" ] && [ -e "$PORT" ]; then
            echo "$PORT"
            return
        fi
        echo "等待串口出现... (插上开发板或上电后会自动连接，Ctrl+C 退出脚本)"
        sleep 2
    done
}

# 优先 minicom，其次 screen
if command -v minicom &>/dev/null; then
    RUN_SERIAL() {
        minicom -D "$1" -b "$BAUD"
    }
elif command -v screen &>/dev/null; then
    RUN_SERIAL() {
        screen "$1" "$BAUD"
    }
else
    echo "请安装 minicom 或 screen: brew install minicom"
    exit 1
fi

echo "波特率: $BAUD （退出当前会话后会自动等待串口并重连，Ctrl+C 退出脚本）"
echo ""

while true; do
    PORT=$(wait_for_port)
    echo "连接: $PORT"
    RUN_SERIAL "$PORT" || true
    echo "连接已断开，2 秒后等待串口重新出现..."
    sleep 2
done
