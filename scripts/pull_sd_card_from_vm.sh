#!/bin/bash
# ============================================================================
# [macOS] 从远程 VM 拉取 PetaLinux sd_card 到本仓库 sd_card
# ============================================================================
#
# 运行环境: macOS
#
# 功能:
#   先清空本仓库 sd_card 目录，再从 VM 全量拉取，保证与 VM 一致；便于后续烧录。
#
# 用法:
#   ./scripts/pull_sd_card_from_vm.sh
#
# 环境变量（可选）:
#   VM_IP     VM 的 IP，默认 10.10.10.1
#   VM_USER   VM 上的用户名，默认 norman
#   VM_SD_PATH  VM 上 sd_card 路径，默认 /home/norman/petalinux-projects/OMP/sd_card
#
# 前置: 需已配置好到 VM 的免密登录（见 setup_ssh_key_to_vm.sh）
# ============================================================================

set -e

VM_IP="${VM_IP:-10.10.10.1}"
VM_USER="${VM_USER:-norman}"
VM_SD_PATH="${VM_SD_PATH:-/home/norman/petalinux-projects/OMP/sd_card}"
REMOTE="${VM_USER}@${VM_IP}"
REMOTE_SRC="${REMOTE}:${VM_SD_PATH}/"

# 解析脚本所在目录和仓库根目录
ORIGINAL_PWD="$(pwd)"
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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}错误: 此脚本设计为在 macOS 上运行。当前: $OSTYPE${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  从 VM 拉取 sd_card${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}远程: ${REMOTE_SRC}${NC}"
echo -e "${BLUE}本地: ${SD_CARD_DIR}/${NC}"
echo ""

# 可选：先测试 SSH 免密是否可用
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE" "exit" 2>/dev/null; then
    echo -e "${YELLOW}提示: 无法免密连接 $REMOTE。请先运行:${NC}"
    echo -e "  ${BLUE}./scripts/setup_ssh_key_to_vm.sh${NC}"
    echo -e "${YELLOW}继续将尝试拉取（可能会提示输入密码）...${NC}"
    echo ""
fi

# 清空本地 sd_card 后全量同步，避免漏同步；-P 输出进度
echo -e "${YELLOW}清空本地 sd_card...${NC}"
rm -rf "${SD_CARD_DIR}"
mkdir -p "$SD_CARD_DIR"

echo -e "${YELLOW}正在从 VM 拉取...${NC}"
if rsync -avz -P -e ssh "${REMOTE_SRC}" "${SD_CARD_DIR}/"; then
    echo ""
    echo -e "${GREEN}拉取完成。${NC}"
    echo -e "${BLUE}可执行烧录: ./scripts/step5_flash_sd_card.sh${NC}"
    echo ""
else
    echo -e "${RED}rsync 失败。请检查网络、VM 路径及 SSH 配置。${NC}"
    exit 1
fi
