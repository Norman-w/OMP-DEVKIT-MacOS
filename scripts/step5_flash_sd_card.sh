#!/bin/bash
# ============================================================================
# [macOS] step5 烧录 SD 卡脚本
# ============================================================================
#
# 运行环境: macOS（本脚本在 macOS 上执行）
#
# 功能:
#   1. 可选：从 VM 上的 PetaLinux 工程 sd_card 目录同步文件到本仓库 sd_card
#   2. 检测外置 SD 卡，选择设备
#   3. 用文件拷贝方式写入 BOOT 分区
#   4. 用 dd 将 rootfs.ext4 写入 SD 卡 root 区域（从固定扇区起）
#
# 说明:
#   - macOS 无法直接挂载 ext4，也无法在挂载后解压 rootfs.tar.gz 使用（路径/引用等问题）
#   - 因此 root 分区采用预制的 rootfs.ext4 用 dd 写入
#
# 使用方法:
#   ./scripts/step5_flash_sd_card.sh [VM上的sd_card路径]
#
# 示例:
#   ./scripts/step5_flash_sd_card.sh
#   ./scripts/step5_flash_sd_card.sh /path/on/vm/petalinux_project/sd_card
#
# 环境变量:
#   PETA_SD_SOURCE  若设置，则从该路径同步到仓库 sd_card（可替代第一个参数）
# ============================================================================

set -e

# 先保存调用时的当前目录（再 cd / 避免 getcwd 错误），用于解析脚本相对路径
ORIGINAL_PWD="$(pwd)"
cd / 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}错误: 此脚本仅在 macOS 上运行。当前系统: $OSTYPE${NC}"
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

# Root 分区在 SD 卡上的起始扇区（两分区时 diskutil 第二分区从 1048576 开始）
ROOT_SEEK_SECTORS=1048576

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  [macOS] step5 烧录 SD 卡${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ----- 可选：从 VM 同步 sd_card 到仓库 -----
PETA_SOURCE="${PETA_SD_SOURCE:-$1}"
if [ -n "$PETA_SOURCE" ]; then
    if [ ! -d "$PETA_SOURCE" ]; then
        echo -e "${RED}错误: 源目录不存在: $PETA_SOURCE${NC}"
        exit 1
    fi
    echo -e "${YELLOW}[macOS] 正在从 VM PetaLinux sd_card 同步到本仓库...${NC}"
    echo -e "${BLUE}  源: $PETA_SOURCE${NC}"
    echo -e "${BLUE}  目标: $SD_CARD_DIR${NC}"
    mkdir -p "$SD_CARD_DIR"
    rsync -a --delete "${PETA_SOURCE}/" "$SD_CARD_DIR/" || {
        echo -e "${YELLOW}rsync 未安装或失败，尝试 cp...${NC}"
        rm -rf "${SD_CARD_DIR:?}"/*
        cp -R "${PETA_SOURCE}"/* "$SD_CARD_DIR/"
    }
    echo -e "${GREEN}  同步完成${NC}"
    echo ""
else
    echo -e "${BLUE}[macOS] 未指定 PETA_SD_SOURCE 或参数，跳过从 VM 同步，使用本仓库 sd_card 现有内容${NC}"
    echo ""
fi

if [ ! -d "$BOOT_SOURCE" ]; then
    echo -e "${RED}错误: 未找到 BOOT 源目录: $BOOT_SOURCE${NC}"
    exit 1
fi
if [ ! -f "$ROOTFS_IMG" ]; then
    echo -e "${RED}错误: 未找到 rootfs 镜像: $ROOTFS_IMG${NC}"
    exit 1
fi

# ----- 复用 dd_img 中的 SD 卡检测逻辑 -----
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
    echo -e "${YELLOW}[macOS] 正在检测 SD 卡设备（外置、容量≤32GB）...${NC}"
    local devices device list_all
    list_all=$(diskutil list external 2>/dev/null | grep -E "^/dev/disk[0-9]+" | awk '{print $1}' || true)
    [ -z "$list_all" ] && list_all=$(diskutil list | grep -E "^/dev/disk[0-9]+" | awk '{print $1}' | grep -v "^/dev/disk0$" || true)
    devices=""
    for device in $list_all; do
        is_likely_sd_card "$device" && devices="$devices $device"
    done
    devices=$(echo "$devices" | xargs)
    [ -z "$devices" ] && return 1
    echo -e "${GREEN}检测到的 SD 卡设备:${NC}"
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
        echo -e "${YELLOW}[macOS] 未检测到 SD 卡，请插入 SD 卡（持续检测中...）${NC}"
        sleep 3
    done
}

if ! detect_sd_cards_macos; then
    wait_for_sd_card_macos
fi

echo ""
echo -e "${GREEN}可用的 SD 卡设备:${NC}"
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
    echo -e "${RED}错误: 未找到可用的 SD 卡设备${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}请选择要使用的 SD 卡（输入编号或设备名，如 1 或 disk2）:${NC}"
read -r USER_INPUT

if [[ "$USER_INPUT" =~ ^[0-9]+$ ]]; then
    if [ "$USER_INPUT" -ge 1 ] && [ "$USER_INPUT" -le ${#DEVICE_ARRAY[@]} ]; then
        SD_DEVICE="${DEVICE_ARRAY[$((USER_INPUT-1))]}"
    else
        echo -e "${RED}错误: 无效的编号${NC}"
        exit 1
    fi
else
    SD_DEVICE="${USER_INPUT}"
    [[ ! "$SD_DEVICE" =~ ^/dev/disk ]] && SD_DEVICE="/dev/disk${SD_DEVICE#disk}"
fi

if ! diskutil info "$SD_DEVICE" &>/dev/null; then
    echo -e "${RED}错误: 设备 $SD_DEVICE 不存在${NC}"
    exit 1
fi
if [ "$SD_DEVICE" = "/dev/disk0" ]; then
    echo -e "${RED}错误: 不能操作系统盘${NC}"
    exit 1
fi

RDEVICE="/dev/rdisk${SD_DEVICE#/dev/disk}"
BOOT_PART="${SD_DEVICE}s1"

echo ""
echo -e "${YELLOW}设备信息:${NC}"
diskutil list "$SD_DEVICE"
echo ""
echo -e "${RED}警告: 将向 $SD_DEVICE 写入 BOOT 分区文件并 dd 写入 rootfs.ext4，请确认设备、容量、名称确认为 SD 卡，避免误操作其他磁盘。${NC}"
echo -e "${YELLOW}确认使用 $SD_DEVICE 继续？(yes/y/no):${NC}"
read -r CONFIRM
CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
    echo "操作已取消"
    exit 0
fi

# 卸载整盘
echo ""
echo -e "${YELLOW}[macOS] 卸载设备...${NC}"
diskutil unmountDisk "$SD_DEVICE" 2>/dev/null || true
sleep 2

# 挂载 BOOT 分区并拷贝文件
echo ""
echo -e "${YELLOW}[macOS] 挂载 BOOT 分区并拷贝文件...${NC}"
diskutil mount "$BOOT_PART" || {
    echo -e "${RED}错误: 无法挂载 BOOT 分区 $BOOT_PART，请确认 SD 卡已按文档先做好分区（512M BOOT FAT32）${NC}"
    exit 1
}
sleep 1
BOOT_MOUNT=$(diskutil info "$BOOT_PART" | grep "Mount Point" | awk -F: '{print $2}' | xargs)
if [ -z "$BOOT_MOUNT" ] || [ ! -d "$BOOT_MOUNT" ]; then
    echo -e "${RED}错误: 无法获取 BOOT 挂载点${NC}"
    exit 1
fi
cp -R "${BOOT_SOURCE}"/* "$BOOT_MOUNT/"
sync
diskutil unmount "$BOOT_PART" || true
echo -e "${GREEN}BOOT 分区文件拷贝完成${NC}"
echo ""

# 使用 dd 写入 rootfs.ext4 到 root 区域
echo -e "${YELLOW}[macOS] 使用 dd 写入 rootfs.ext4 到 root 区域（seek=$ROOT_SEEK_SECTORS 扇区）...${NC}"
sudo dd if="$ROOTFS_IMG" of="$RDEVICE" bs=512 seek="$ROOT_SEEK_SECTORS" conv=sync status=progress || {
    echo -e "${RED}错误: dd 写入失败${NC}"
    exit 1
}
sync
echo -e "${GREEN}rootfs.ext4 写入完成${NC}"
echo ""

# 卸载并弹出
echo -e "${YELLOW}[macOS] 卸载并弹出 SD 卡...${NC}"
diskutil unmountDisk "$SD_DEVICE" 2>/dev/null || true
diskutil eject "$SD_DEVICE" 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  [macOS] step5 烧录完成${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}建议: 重新插拔 SD 卡，确认 BOOT 分区可识别即表示制作成功。${NC}"
echo ""
