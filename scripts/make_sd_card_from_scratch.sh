#!/bin/bash
# ============================================================================
# [macOS] 新卡从零制作：分区（BOOT + rootfs 区） + 写 BOOT + dd rootfs
# ============================================================================
#
# 运行环境: macOS
#
# 功能:
#   1. 检测外置 SD 卡并选择设备
#   2. 整盘重新分区：MBR，第一分区 512MB FAT32 名 BOOT，第二分区 Linux (83)
#   3. 拷贝 BOOT_partition 内容到 BOOT 分区
#   4. 用 dd 将 rootfs.ext4 写入第二分区区域
#
# 使用:
#   ./scripts/make_sd_card_from_scratch.sh
#
# 前提: 仓库 sd_card/BOOT_partition 与 sd_card/rootfs.ext4 已存在
# ============================================================================

set -e

ORIGINAL_PWD="$(pwd)"
cd / 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}错误: 此脚本仅在 macOS 上运行。${NC}"
    exit 1
fi

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
[[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="${ORIGINAL_PWD}/${SCRIPT_SOURCE}"
if [ -L "$SCRIPT_SOURCE" ]; then
    LINK_TARGET="$(readlink "$SCRIPT_SOURCE")"
    LINK_DIR="$(dirname "$SCRIPT_SOURCE")"
    [[ "$LINK_TARGET" == /* ]] && SCRIPT_SOURCE="$LINK_TARGET" || SCRIPT_SOURCE="${LINK_DIR}/${LINK_TARGET}"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SD_CARD_DIR="${REPO_ROOT}/sd_card"
BOOT_SOURCE="${SD_CARD_DIR}/BOOT_partition"
ROOTFS_IMG="${SD_CARD_DIR}/rootfs.ext4"
cd "$ORIGINAL_PWD" 2>/dev/null || true

ROOT_SEEK_MB=512

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  [macOS] 新卡从零制作（BOOT + rootfs）${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ ! -d "$BOOT_SOURCE" ]; then
    echo -e "${RED}错误: 未找到 BOOT 源: $BOOT_SOURCE${NC}"
    exit 1
fi
if [ ! -f "$ROOTFS_IMG" ]; then
    echo -e "${RED}错误: 未找到 rootfs 镜像: $ROOTFS_IMG${NC}"
    exit 1
fi

# ----- 与 step5 相同的 SD 卡检测 -----
is_likely_sd_card() {
    local dev="$1"
    local info model size_line size_gb
    info=$(diskutil info "$dev" 2>/dev/null) || return 1
    model=$(echo "$info" | grep "Device / Media Name" | awk -F: '{print $2}' | xargs)
    size_line=$(echo "$info" | grep "Disk Size" | head -1)
    if echo "$model" | grep -qiE "APPLE SSD|Internal|Macintosh"; then
        return 1
    fi
    if echo "$size_line" | grep -q " GB "; then
        size_gb=$(echo "$size_line" | sed -n 's/.* \([0-9.]*\) GB.*/\1/p' | head -1)
        if [ -n "$size_gb" ] && awk "BEGIN{exit !($size_gb > 32)}" 2>/dev/null; then
            return 1
        fi
    fi
    if echo "$size_line" | grep -q " TB "; then
        return 1
    fi
    return 0
}

detect_sd_cards_macos() {
    echo -e "${YELLOW}[macOS] 检测 SD 卡（外置、≤32GB）...${NC}"
    local list_all devices device
    list_all=$(diskutil list external 2>/dev/null | grep -E "^/dev/disk[0-9]+" | awk '{print $1}' || true)
    [ -z "$list_all" ] && list_all=$(diskutil list | grep -E "^/dev/disk[0-9]+" | awk '{print $1}' | grep -v "^/dev/disk0$" || true)
    devices=""
    for device in $list_all; do
        is_likely_sd_card "$device" && devices="$devices $device"
    done
    devices=$(echo "$devices" | xargs)
    [ -z "$devices" ] && return 1
    echo -e "${GREEN}检测到的 SD 卡:${NC}"
    for device in $devices; do
        size=$(diskutil info "$device" 2>/dev/null | grep "Disk Size" | awk -F: '{print $2}' | xargs || echo "未知")
        model=$(diskutil info "$device" 2>/dev/null | grep "Device / Media Name" | awk -F: '{print $2}' | xargs || echo "未知")
        echo "  $device - $size ($model)"
    done
    return 0
}

wait_for_sd_card_macos() {
    while true; do
        if detect_sd_cards_macos; then
            break
        fi
        echo -e "${YELLOW}未检测到 SD 卡，请插入 SD 卡...${NC}"
        sleep 3
    done
}

if ! detect_sd_cards_macos; then
    wait_for_sd_card_macos
fi

echo ""
DEVICE_ARRAY=()
dev_list=$(diskutil list external 2>/dev/null | grep -E "^/dev/disk[0-9]+" | awk '{print $1}' || true)
[ -z "$dev_list" ] && dev_list=$(diskutil list | grep -E "^/dev/disk[0-9]+" | awk '{print $1}' | grep -v "^/dev/disk0$" || true)
for device in $dev_list; do
    [ -z "$device" ] && continue
    is_likely_sd_card "$device" && DEVICE_ARRAY+=("$device")
done

index=1
for device in "${DEVICE_ARRAY[@]}"; do
    size=$(diskutil info "$device" 2>/dev/null | grep "Disk Size" | awk -F: '{print $2}' | xargs || echo "未知")
    model=$(diskutil info "$device" 2>/dev/null | grep "Device / Media Name" | awk -F: '{print $2}' | xargs || echo "未知")
    echo -e "  ${BLUE}[$index]${NC} $device - $size ($model)"
    ((index++))
done

if [ ${#DEVICE_ARRAY[@]} -eq 0 ]; then
    echo -e "${RED}错误: 未找到可用 SD 卡${NC}"
    exit 1
fi

if [ ${#DEVICE_ARRAY[@]} -eq 1 ]; then
    SD_DEVICE="${DEVICE_ARRAY[0]}"
    echo -e "${GREEN}自动选择唯一 SD 卡: $SD_DEVICE${NC}"
    AUTO_CONFIRM=1
else
    echo -e "${YELLOW}请选择 SD 卡（输入编号或设备名）:${NC}"
    read -r USER_INPUT
    if [[ "$USER_INPUT" =~ ^[0-9]+$ ]]; then
        if [ "$USER_INPUT" -ge 1 ] && [ "$USER_INPUT" -le ${#DEVICE_ARRAY[@]} ]; then
            SD_DEVICE="${DEVICE_ARRAY[$((USER_INPUT-1))]}"
        else
            echo -e "${RED}无效编号${NC}"
            exit 1
        fi
    else
        SD_DEVICE="${USER_INPUT}"
        [[ ! "$SD_DEVICE" =~ ^/dev/disk ]] && SD_DEVICE="/dev/disk${SD_DEVICE#disk}"
    fi
    AUTO_CONFIRM=0
fi

if ! diskutil info "$SD_DEVICE" &>/dev/null; then
    echo -e "${RED}错误: 设备不存在: $SD_DEVICE${NC}"
    exit 1
fi
if [ "$SD_DEVICE" = "/dev/disk0" ]; then
    echo -e "${RED}错误: 不能操作系统盘${NC}"
    exit 1
fi

RDEVICE="/dev/rdisk${SD_DEVICE#/dev/disk}"
BOOT_PART="${SD_DEVICE}s1"

echo ""
echo -e "${YELLOW}将操作的设备: $SD_DEVICE${NC}"
diskutil list "$SD_DEVICE"
echo ""
echo -e "${RED}⚠️  将对该盘重新分区并写入 BOOT + rootfs，请确认是 SD 卡且无重要数据。${NC}"
if [ "$AUTO_CONFIRM" != "1" ]; then
    echo -e "${YELLOW}确认使用 $SD_DEVICE 继续？(yes/y/no):${NC}"
    read -r CONFIRM
    CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
    if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
        echo "已取消"
        exit 0
    fi
fi

# ----- 1. 卸载 -----
echo ""
echo -e "${YELLOW}[1/5] 卸载设备...${NC}"
diskutil unmountDisk "$SD_DEVICE" 2>/dev/null || true
sleep 2

# ----- 2. 分区：MBR, BOOT 512M FAT32, 剩余 free -----
echo ""
echo -e "${YELLOW}[2/5] 创建分区表（MBR, BOOT 512M FAT32, 剩余空间保留）...${NC}"
sudo diskutil partitionDisk "$SD_DEVICE" MBR FAT32 BOOT 512M free none R
sleep 2
diskutil unmountDisk "$SD_DEVICE" 2>/dev/null || true
sleep 2

# ----- 3. fdisk：将第二项设为 Linux (83)，起始扇区 1048576 -----
echo ""
echo -e "${YELLOW}[3/5] 使用 fdisk 将剩余空间设为 Linux 分区 (83)...${NC}"
# macOS fdisk -e 接受 stdin
printf 'edit 2\n83\nn\n1048576\n\nwrite\ny\nquit\n' | sudo fdisk -e "$SD_DEVICE" || {
    echo -e "${YELLOW}fdisk 非交互失败，请手动执行以下命令后，再运行 step5 完成写 BOOT 和 rootfs:${NC}"
    echo "  sudo fdisk -e $SD_DEVICE"
    echo "  依次输入: edit 2, 83, n, 1048576, 回车, write, y, quit"
    exit 1
}
sleep 2

# ----- 4. 挂载 BOOT 并拷贝 -----
echo ""
echo -e "${YELLOW}[4/5] 挂载 BOOT 分区并拷贝文件...${NC}"
diskutil mount "$BOOT_PART" || {
    echo -e "${RED}无法挂载 $BOOT_PART${NC}"
    exit 1
}
sleep 1
BOOT_MOUNT=$(diskutil info "$BOOT_PART" | grep "Mount Point" | awk -F: '{print $2}' | xargs)
if [ -z "$BOOT_MOUNT" ] || [ ! -d "$BOOT_MOUNT" ]; then
    echo -e "${RED}无法获取 BOOT 挂载点${NC}"
    exit 1
fi
cp -R "${BOOT_SOURCE}"/* "$BOOT_MOUNT/" 2>/dev/null || true
[ -f "${BOOT_SOURCE}/.env" ] && cp "${BOOT_SOURCE}/.env" "$BOOT_MOUNT/" && echo -e "${GREEN}  已拷贝 .env${NC}"
[ -f "${BOOT_SOURCE}/.env.sample" ] && cp "${BOOT_SOURCE}/.env.sample" "$BOOT_MOUNT/"
OMP_AC820="${OMP_AC820:-$(dirname "$REPO_ROOT")/OMP-AC820-PetaLinux}"
if [ -f "${REPO_ROOT}/splash.rgb565" ]; then
    cp "${REPO_ROOT}/splash.rgb565" "$BOOT_MOUNT/" && echo -e "${GREEN}  已注入 splash.rgb565（来自仓库根）${NC}"
elif [ -f "${OMP_AC820}/splash.rgb565" ]; then
    cp "${OMP_AC820}/splash.rgb565" "$BOOT_MOUNT/" && echo -e "${GREEN}  已注入 splash.rgb565（来自 OMP-AC820-PetaLinux）${NC}"
fi
sync
diskutil unmount "$BOOT_PART" || true
echo -e "${GREEN}BOOT 拷贝完成${NC}"

# ----- 5. dd rootfs -----
echo ""
echo -e "${YELLOW}[5/5] dd 写入 rootfs.ext4（seek=${ROOT_SEEK_MB}MB）...${NC}"
sudo dd if="$ROOTFS_IMG" of="$RDEVICE" bs=1m seek="$ROOT_SEEK_MB" conv=sync status=progress || {
    echo -e "${RED}dd 失败${NC}"
    exit 1
}
sync
echo -e "${GREEN}rootfs 写入完成${NC}"

# ----- 卸载并弹出 -----
echo ""
echo -e "${YELLOW}卸载并弹出 SD 卡...${NC}"
diskutil unmountDisk "$SD_DEVICE" 2>/dev/null || true
diskutil eject "$SD_DEVICE" 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  新卡制作完成（BOOT + rootfs）${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}可重新插拔 SD 卡，确认 BOOT 分区可见即表示成功。${NC}"
echo ""
