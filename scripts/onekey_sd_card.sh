#!/bin/bash
# ============================================================================
# [macOS] 一键：从 VM 拉取 sd_card + 烧录 SD 卡
# ============================================================================
#
# 运行环境: macOS
#
# 功能:
#   1. 从 VM 拉取 PetaLinux sd_card 到本仓库（带进度）
#   2. 检测 SD 卡并烧录（BOOT + rootfs.ext4）
#
# 用法:
#   ./scripts/onekey_sd_card.sh
#
# 环境变量: 与 pull_sd_card_from_vm.sh 一致（VM_IP, VM_USER, VM_SD_PATH）
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

# 先拉取，再烧录
"${SCRIPT_DIR}/pull_sd_card_from_vm.sh"
"${SCRIPT_DIR}/step5_flash_sd_card.sh"
