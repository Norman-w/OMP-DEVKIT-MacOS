#!/bin/bash
# ============================================================================
# [macOS] 一键：VM 构建 + 拉取 sd_card + 烧录 SD 卡
# ============================================================================
#
# 运行环境: macOS
#
# 功能:
#   1. 调用 build_sd_card_on_vm.sh：在 VM 上 OMP 工程目录 git pull 与 ./do build card
#   2. 调用 pull_sd_card_from_vm.sh：从 VM 拉取 sd_card 到本仓库
#   3. 调用 step5_flash_sd_card.sh：检测 SD 卡并烧录
#
# 用法:
#   ./scripts/onekey_sd_card.sh
#
# 环境变量: VM_IP, VM_USER, VM_SD_PATH（与子脚本一致）
#
# 前置: 已配置 VM 免密登录（见 setup_ssh_key_to_vm.sh）
# ============================================================================

set -e

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
[[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$(pwd)/${SCRIPT_SOURCE}"
if [ -L "$SCRIPT_SOURCE" ]; then
    LINK_TARGET="$(readlink "$SCRIPT_SOURCE")"
    LINK_DIR="$(dirname "$SCRIPT_SOURCE")"
    [[ "$LINK_TARGET" == /* ]] && SCRIPT_SOURCE="$LINK_TARGET" || SCRIPT_SOURCE="${LINK_DIR}/${LINK_TARGET}"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# 与子脚本一致的默认值，便于单独跑一键时生效
export VM_IP="${VM_IP:-10.10.10.1}"
export VM_USER="${VM_USER:-norman}"
export VM_SD_PATH="${VM_SD_PATH:-/home/norman/petalinux-projects/OMP/sd_card}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  一键：VM 构建 + 拉取 + 烧录 SD 卡${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}[1/3] VM 上拉取代码并构建 sd_card...${NC}"
"${SCRIPT_DIR}/build_sd_card_on_vm.sh"
echo ""

echo -e "${YELLOW}[2/3] 从 VM 拉取 sd_card 到本机...${NC}"
"${SCRIPT_DIR}/pull_sd_card_from_vm.sh"
echo ""

echo -e "${YELLOW}[3/3] 烧录 SD 卡...${NC}"
"${SCRIPT_DIR}/step5_flash_sd_card.sh"
