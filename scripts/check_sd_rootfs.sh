#!/bin/bash
# ============================================================================
# [macOS] 检查 SD 卡 rootfs 区域是否已写入 ext4 镜像
# ============================================================================
#
# 在 rootfs 偏移处读取 2 字节，检查是否为 ext4 魔数 0x53 0xEF。
# 需在终端运行（会请求 sudo 密码）。
#
# 用法:
#   ./scripts/check_sd_rootfs.sh /dev/disk5
#
# 若输出 "rootfs.ext4 已正确写入" 则无需再 dd；否则需执行 dd 写入 rootfs.ext4。
# ============================================================================

set -e

DEV="${1:-}"

if [ -z "$DEV" ]; then
    echo "用法: $0 /dev/diskN"
    echo "示例: $0 /dev/disk5"
    echo ""
    echo "先用 diskutil list 确认 SD 卡设备号（如 disk5）。"
    exit 1
fi

if [ ! -e "$DEV" ]; then
    echo "错误: 设备不存在: $DEV"
    exit 1
fi

# 禁止误操作系统盘
if [ "$DEV" = "/dev/disk0" ]; then
    echo "错误: 不能检查系统盘 disk0"
    exit 1
fi

# 两种分区布局下 ext4 魔数在磁盘上的字节偏移（魔数在镜像内 1080 字节）
OFFSET_A=$((1050624 * 512 + 1080))
OFFSET_B=$((1048576 * 512 + 1080))
RDEV="/dev/rdisk${DEV#/dev/disk}"

echo "设备: $DEV (raw: $RDEV)"
echo "检查 rootfs 区域 ext4 魔数 (0x53 0xEF)..."
echo ""

# 先卸载整张卡，否则可能读到的是分区“视图”而非原始扇区
echo "正在卸载设备以便读取原始扇区..."
sudo diskutil unmountDisk "$DEV" 2>/dev/null || true
sleep 1
echo ""

# macOS 上 dd bs=1 skip=大偏移 对 rdisk 会报 Invalid argument，改为按扇区读再截取
TMP_BIN="/tmp/sd_rootfs_check_$$.bin"
trap "rm -f $TMP_BIN" EXIT
read_hex_at() {
    local off="$1"
    local sector=$((off / 512))
    local byte_in_sector=$((off % 512))
    local sectors_needed=$(( (byte_in_sector + 2 + 511) / 512 ))
    sudo dd if="$RDEV" bs=512 skip="$sector" count="$sectors_needed" 2>/dev/null \
        | dd bs=1 skip="$byte_in_sector" count=2 of="$TMP_BIN" 2>/dev/null
    if command -v xxd &>/dev/null; then
        xxd -p "$TMP_BIN" 2>/dev/null | tr -d '\n'
    else
        od -A n -t x1 "$TMP_BIN" 2>/dev/null | tr -d ' \n'
    fi
}
echo "两处可能偏移:"
B_A=$(read_hex_at $OFFSET_A)
echo "  seek=1050624: ${B_A:-空}"
echo "$B_A" | grep -qE '53ef|ef53' && { echo ""; echo "结果: rootfs.ext4 已正确写入（seek=1050624）。"; exit 0; }
B_B=$(read_hex_at $OFFSET_B)
echo "  seek=1048576: ${B_B:-空}"
echo "$B_B" | grep -qE '53ef|ef53' && { echo ""; echo "结果: rootfs.ext4 已正确写入（seek=1048576）。"; exit 0; }
echo ""
echo "结果: 两处均无 ext4 魔数，需执行 dd。"
echo "  sudo dd if=\$REPO/sd_card/rootfs.ext4 of=$RDEV bs=512 seek=1048576 conv=sync status=progress"
exit 1
