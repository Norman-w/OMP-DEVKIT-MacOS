#!/bin/bash
# ============================================================================
# [macOS] 在 VM 上 OMP 工程目录执行 git pull 与 ./do build card
# ============================================================================
#
# 运行环境: macOS，通过 SSH 在 VM 上执行命令
#
# 功能:
#   SSH 到 VM，进入 OMP 工程根目录，执行 git pull 与 ./do build card。
#
# 用法:
#   ./scripts/build_sd_card_on_vm.sh
#
# 环境变量（可选）:
#   VM_IP       VM 的 IP，默认 10.10.10.1
#   VM_USER     VM 上的用户名，默认 norman
#   VM_SD_PATH  VM 上 sd_card 路径，默认 /home/norman/petalinux-projects/OMP/sd_card
#               OMP 工程根目录取其上级目录。
#
# 前置: 已配置 VM 免密登录（见 setup_ssh_key_to_vm.sh）
# ============================================================================

set -e

VM_IP="${VM_IP:-10.10.10.1}"
VM_USER="${VM_USER:-norman}"
VM_SD_PATH="${VM_SD_PATH:-/home/norman/petalinux-projects/OMP/sd_card}"
VM_OMP_ROOT="$(dirname "$VM_SD_PATH")"
REMOTE="${VM_USER}@${VM_IP}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 使用 bash -lic 启动 login+交互 shell，避免 .bashrc 因非交互而提前 return 导致 PLNX_PATH 未加载
echo -e "${YELLOW}在 VM ($REMOTE) OMP 工程目录执行 git pull 与 ./do build card...${NC}"
ssh -t "$REMOTE" "cd ${VM_OMP_ROOT} && bash -lic 'git pull && ./do build card'" || {
    echo -e "${RED}VM 上 git pull 或 ./do build card 失败${NC}"
    exit 1
}
