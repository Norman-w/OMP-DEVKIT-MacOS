#!/bin/bash
# ============================================================================
# Step4 解决方案A - 步骤4.2: rootfs分区镜像创建脚本（macOS烧录）
# ============================================================================
#
# 功能:
#   1. 计算rootfs.tar.gz解压后的实际大小
#   2. 创建精准大小的ext4镜像文件
#   3. 格式化镜像为ext4
#   4. 挂载镜像并解压rootfs.tar.gz到镜像
#   5. 卸载镜像并校验ext4魔数
#   6. 复制rootfs.ext4到sd_card文件夹，准备macOS烧录
#
# 使用方法:
#   在PetaLinux工程根目录下运行（打包完成后）:
#   bash step4_slnA_for_macos_4.2_rootfs_partition_create_image_and_copy_to_sd_card.sh
#
# 说明:
#   这是Step4的解决方案A（macOS烧录方案）的步骤4.2 - rootfs分区
#   - 步骤4.1: BOOT分区文件准备（step4_slnA_for_macos_4.1_BOOT_partition_copy_to_sd_card_folder.sh）
#   - 步骤4.2: rootfs分区镜像创建（本脚本）
#
#   如果要在VM上直接烧录SD卡，请使用 step4_slnB_for_vm_flash_to_sd_card.sh
#
# 注意事项:
#   - 需要root权限（使用sudo）
#   - 确保已运行 step3_package-after-build.sh
#   - 从sd_card文件夹复制到macOS时，不要使用RDP直接复制到编辑器
#     建议先复制到Finder，再复制到IDE，避免文件名编码问题
#
# ============================================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取脚本所在目录（应该是PetaLinux工程根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PETALINUX_PROJECT="$SCRIPT_DIR"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}创建rootfs镜像并复制到sd_card文件夹${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}工程路径: ${PETALINUX_PROJECT}${NC}"
echo ""

# 检查必要文件
IMAGES_DIR="${PETALINUX_PROJECT}/images/linux"
SD_CARD_DIR="${PETALINUX_PROJECT}/sd_card"

if [ ! -f "${IMAGES_DIR}/rootfs.tar.gz" ]; then
    echo -e "${RED}错误: 未找到 rootfs.tar.gz${NC}"
    echo "请先运行: bash step3_package-after-build.sh"
    exit 1
fi

if [ ! -f "${IMAGES_DIR}/BOOT.BIN" ]; then
    echo -e "${RED}错误: 未找到 BOOT.BIN${NC}"
    echo "请先运行: bash step3_package-after-build.sh"
    exit 1
fi

if [ ! -f "${IMAGES_DIR}/image.ub" ]; then
    echo -e "${RED}错误: 未找到 image.ub${NC}"
    echo "请先运行: bash step3_package-after-build.sh"
    exit 1
fi

echo -e "${GREEN}✓ 所有必需文件已找到${NC}"
echo ""

# 进入images/linux目录
cd "${IMAGES_DIR}"

# 步骤1: 计算rootfs.tar.gz解压后的实际大小（修复：用 gzip -l 避免 tar --to-stdout . 得到 0）
echo -e "${YELLOW}步骤 1: 计算rootfs.tar.gz解压后的实际大小...${NC}"
echo -e "${BLUE}这可能需要几秒钟...${NC}"

ROOTFS_ACTUAL_SIZE_MB=$(gzip -l rootfs.tar.gz 2>/dev/null | tail -1 | awk '{print int($2/1024/1024)}')
if [ -z "$ROOTFS_ACTUAL_SIZE_MB" ] || [ "$ROOTFS_ACTUAL_SIZE_MB" -eq 0 ]; then
    ROOTFS_ACTUAL_SIZE_MB=$(zcat rootfs.tar.gz 2>/dev/null | wc -c | awk '{print int($1/1024/1024)}')
fi
if [ -z "$ROOTFS_ACTUAL_SIZE_MB" ] || [ "$ROOTFS_ACTUAL_SIZE_MB" -eq 0 ]; then
    echo -e "${RED}错误: 无法计算rootfs大小（请检查 rootfs.tar.gz）${NC}"
    exit 1
fi

echo -e "${GREEN}✓ rootfs.tar.gz解压后实际大小: ${ROOTFS_ACTUAL_SIZE_MB}MB${NC}"
echo ""

# 步骤2: 计算镜像大小（加30MB余量）
echo -e "${YELLOW}步骤 2: 计算镜像大小...${NC}"
ROOTFS_IMG_SIZE_MB=$((ROOTFS_ACTUAL_SIZE_MB + 30))
echo -e "${BLUE}  实际大小: ${ROOTFS_ACTUAL_SIZE_MB}MB${NC}"
echo -e "${BLUE}  余量: 30MB${NC}"
echo -e "${GREEN}✓ 镜像大小: ${ROOTFS_IMG_SIZE_MB}MB${NC}"
echo ""

# 步骤3: 创建精准大小的空镜像
echo -e "${YELLOW}步骤 3: 创建ext4镜像文件...${NC}"
if [ -f "./rootfs.ext4" ]; then
    echo -e "${YELLOW}  警告: rootfs.ext4 已存在，将删除旧文件${NC}"
    rm -f ./rootfs.ext4
fi

echo -e "${BLUE}  创建 ${ROOTFS_IMG_SIZE_MB}MB 的镜像文件...${NC}"
dd if=/dev/zero of=./rootfs.ext4 bs=1M count=${ROOTFS_IMG_SIZE_MB} conv=sync status=progress

if [ ! -f "./rootfs.ext4" ]; then
    echo -e "${RED}错误: 镜像文件创建失败${NC}"
    exit 1
fi

ROOTFS_IMG_SIZE=$(ls -lh ./rootfs.ext4 | awk '{print $5}')
echo -e "${GREEN}✓ 镜像文件创建成功 (${ROOTFS_IMG_SIZE})${NC}"
echo ""

# 步骤4: 格式化镜像为ext4
echo -e "${YELLOW}步骤 4: 格式化镜像为ext4...${NC}"
sudo mkfs.ext4 -F -L "rootfs" ./rootfs.ext4
echo -e "${GREEN}✓ 格式化完成${NC}"
echo ""

# 步骤5: 挂载镜像并解压rootfs
echo -e "${YELLOW}步骤 5: 解压rootfs到镜像...${NC}"
MOUNT_POINT="/mnt/petalinux_rootfs"

# 创建临时挂载目录
sudo mkdir -p "${MOUNT_POINT}"

# 挂载镜像
sudo mount ./rootfs.ext4 "${MOUNT_POINT}"

# 解压rootfs.tar.gz到镜像（-p保留权限，开发板启动必需）
echo -e "${BLUE}  解压rootfs.tar.gz到镜像（这可能需要几分钟）...${NC}"
sudo tar -zxvpf ./rootfs.tar.gz -C "${MOUNT_POINT}" > /dev/null

# 同步缓存
sync

# 卸载镜像
sudo umount "${MOUNT_POINT}"

# 清理临时目录
sudo rmdir "${MOUNT_POINT}"

echo -e "${GREEN}✓ rootfs解压完成${NC}"
echo ""

# 步骤5.5: 校验 rootfs.ext4 为合法 ext4（魔数 0x53 0xEF 在偏移 1080）
echo -e "${YELLOW}步骤 5.5: 校验 rootfs.ext4 镜像...${NC}"
EXT4_MAGIC=$(dd if=./rootfs.ext4 bs=1 skip=1080 count=2 2>/dev/null | hexdump -e '2/1 "%02x"' | tr -d ' ')
if ! echo "$EXT4_MAGIC" | grep -qE '53ef|ef53'; then
    echo -e "${RED}错误: rootfs.ext4 无 ext4 魔数（当前: $EXT4_MAGIC），镜像可能未正确格式化或为空${NC}"
    exit 1
fi
echo -e "${GREEN}✓ rootfs.ext4 校验通过（ext4 魔数正确）${NC}"
echo ""

# 步骤6: 复制rootfs.ext4到sd_card文件夹
echo -e "${YELLOW}步骤 6: 复制rootfs.ext4到sd_card文件夹...${NC}"

# 确保sd_card目录存在（步骤4.1应该已经创建）
mkdir -p "${SD_CARD_DIR}"

# 复制rootfs.ext4镜像文件
echo -e "${BLUE}  复制rootfs.ext4镜像文件...${NC}"
cp ./rootfs.ext4 "${SD_CARD_DIR}/rootfs.ext4"
ROOTFS_EXT4_SIZE=$(ls -lh "${SD_CARD_DIR}/rootfs.ext4" | awk '{print $5}')
echo -e "${GREEN}  ✓ rootfs.ext4 已复制 (${ROOTFS_EXT4_SIZE})${NC}"

echo -e "${GREEN}✓ rootfs文件已复制到sd_card文件夹${NC}"
echo ""

# 步骤7: 更新说明文件
echo -e "${YELLOW}步骤 7: 更新说明文件...${NC}"
cat > "${SD_CARD_DIR}/README.txt" << 'EOF'
SD卡烧录文件说明
================

目录结构:
  sd_card/
  ├── BOOT_partition/       - BOOT分区文件（包含BOOT.BIN, image.ub, boot.scr）
  └── rootfs.ext4           - rootfs ext4镜像文件（用于直接dd写入rootfs分区）

使用方法:
--------

方法1: 使用macOS脚本烧录（推荐）
  1. 将整个 sd_card 文件夹复制到macOS
     ⚠️ 重要: 不要使用RDP直接复制到编辑器（Cursor等）
     建议先复制到Finder，再复制到IDE，避免文件名编码问题
  2. 运行: bash macos-flash-img-to-sd-card.sh
     （脚本会自动处理BOOT分区和rootfs分区）

方法2: 手动复制到SD卡
  BOOT分区 (FAT32):
    - 复制 BOOT_partition/ 文件夹下的所有文件到BOOT分区
    - 注意: BOOT.BIN 文件名必须全大写

  rootfs分区 (EXT4):
    - 使用dd命令将 rootfs.ext4 写入rootfs分区:
      sudo dd if=rootfs.ext4 of=/dev/sdX2 bs=1M status=progress

重要提示:
--------
  • BOOT.BIN 文件名必须全大写（不是 boot.bin）
  • image.ub 文件名是小写（不是 boot.ub）
  • 不要复制 u-boot.elf 和 system.bit（已包含在BOOT.BIN中）
  • ⚠️ 从macOS复制文件时，不要使用RDP直接复制到编辑器
    建议通过Finder或scp复制，避免文件名编码问题
  • 确保文件名大小写正确：BOOT.BIN（全大写），image.ub（小写）
EOF

echo -e "${GREEN}✓ 说明文件已创建${NC}"
echo ""

# 显示最终统计
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}sd_card 文件夹结构:${NC}"
tree -L 2 "${SD_CARD_DIR}" 2>/dev/null || {
    echo "  sd_card/"
    echo "  ├── BOOT_partition/"
    echo "  │   ├── BOOT.BIN"
    echo "  │   ├── image.ub"
    if [ -f "${SD_CARD_DIR}/BOOT_partition/boot.scr" ]; then
        echo "  │   └── boot.scr"
    fi
    echo "  └── rootfs.ext4"
}
echo ""
echo -e "${BLUE}文件大小统计:${NC}"
echo ""
echo -e "${YELLOW}BOOT分区文件 (BOOT_partition/):${NC}"
ls -lh "${SD_CARD_DIR}/BOOT_partition"/BOOT.BIN "${SD_CARD_DIR}/BOOT_partition"/image.ub "${SD_CARD_DIR}/BOOT_partition"/boot.scr 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""
echo -e "${YELLOW}rootfs文件:${NC}"
ls -lh "${SD_CARD_DIR}/rootfs.ext4" 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""

TOTAL_SIZE=$(du -sh "${SD_CARD_DIR}" 2>/dev/null | awk '{print $1}')
echo -e "${BLUE}总大小: ${TOTAL_SIZE}${NC}"
echo ""

# 下一步说明
echo -e "${GREEN}下一步:${NC}"
echo "  1. 将整个 sd_card 文件夹复制到macOS"
echo ""
echo -e "${YELLOW}    ⚠️ 重要提示:${NC}"
echo "     • 不要使用RDP直接复制到编辑器（Cursor等）"
echo "     • 建议先复制到Finder，再复制到IDE"
echo "     • 或使用scp命令:"
echo -e "       ${BLUE}scp -r norman@192.168.46.128:${SD_CARD_DIR} ~/Downloads/${NC}"
echo ""
echo "  2. 在macOS上使用脚本烧录:"
echo -e "     ${YELLOW}bash macos-flash-img-to-sd-card.sh${NC}"
echo ""
echo "  3. 或手动复制文件到SD卡:"
echo "     - BOOT分区: 复制 BOOT_partition/ 文件夹下的所有文件"
echo "     - rootfs分区: 使用dd命令将 rootfs.ext4 写入分区"
echo "       sudo dd if=rootfs.ext4 of=/dev/sdX2 bs=1M status=progress"
echo ""
echo -e "${BLUE}关于rootfs镜像:${NC}"
echo "  • rootfs.ext4: 已格式化的ext4镜像，包含完整的rootfs内容"
echo "  • 可以直接使用dd命令写入rootfs分区，无需解压"
echo ""
