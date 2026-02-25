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


# 自动加载env文件（如dev.env）
ENV_FILE="${SCRIPT_DIR}/../dev.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    . "$ENV_FILE"
    set +a
fi

# 与子脚本一致的默认值，便于单独跑一键时生效
export VM_IP="${VM_IP:-192.168.7.234}"
export VM_USER="${VM_USER:-norman}"
export VM_SD_PATH="${VM_SD_PATH:-/home/norman/petalinux-projects/OMP/sd_card}"
export VM_PASSWORD="${VM_PASSWORD:-}" # 密码可选
export VM_TARGET_BRANCH="${VM_TARGET_BRANCH:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  一键：VM 构建 + 拉取 + 烧录 SD 卡${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 选择 VM 构建分支：若检测到最新提交不在 master，可交互选择 latest/master/自定义
if [ -z "${VM_TARGET_BRANCH}" ]; then
    OMP_AC820="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)/OMP-AC820-PetaLinux"
    if [ -d "${OMP_AC820}/.git" ]; then
        git -C "${OMP_AC820}" fetch origin --quiet || true
        latest_remote_ref="$(git -C "${OMP_AC820}" for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin | grep -v '^origin/HEAD$' | head -n 1)"
        latest_branch="${latest_remote_ref#origin/}"
        [ -z "${latest_branch}" ] && latest_branch="master"

        echo -e "${YELLOW}检测到 OMP-AC820-PetaLinux 最新远程分支: ${latest_branch}${NC}"
        if [ "${latest_branch}" != "master" ]; then
            echo "请选择 VM 上用于构建 sd_card 的分支:"
            echo "  1) 最新分支 (${latest_branch})"
            echo "  2) master"
            echo "  3) 自定义分支"
            read -r -p "输入选项 [1/2/3, 默认1]: " branch_pick
            case "${branch_pick}" in
                2)
                    VM_TARGET_BRANCH="master"
                    ;;
                3)
                    read -r -p "请输入分支名: " custom_branch
                    if [ -n "${custom_branch}" ]; then
                        VM_TARGET_BRANCH="${custom_branch}"
                    else
                        VM_TARGET_BRANCH="${latest_branch}"
                    fi
                    ;;
                *)
                    VM_TARGET_BRANCH="${latest_branch}"
                    ;;
            esac
        else
            VM_TARGET_BRANCH="master"
        fi
    else
        echo -e "${YELLOW}⚠ 未找到本地 OMP-AC820-PetaLinux 仓库，默认使用 master 构建。${NC}"
        VM_TARGET_BRANCH="master"
    fi
fi
export VM_TARGET_BRANCH
echo -e "${GREEN}VM 构建分支: ${VM_TARGET_BRANCH}${NC}"
echo ""

echo -e "${YELLOW}[1/3] VM 上拉取代码并构建 sd_card...${NC}"
"${SCRIPT_DIR}/build_sd_card_on_vm.sh"
echo ""

echo -e "${YELLOW}[2/3] 从 VM 拉取 sd_card 到本机...${NC}"
"${SCRIPT_DIR}/pull_sd_card_from_vm.sh"
echo ""

# 首屏 splash：VM 上构建时没有 splash.rgb565，拉取后在 Mac 上注入（与本仓库或 OMP-AC820-PetaLinux 仓库根目录一致）
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SD_BOOT="${REPO_ROOT}/sd_card/BOOT_partition"
OMP_AC820="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)/OMP-AC820-PetaLinux"
if [ -f "${REPO_ROOT}/splash.rgb565" ]; then
    cp "${REPO_ROOT}/splash.rgb565" "${SD_BOOT}/splash.rgb565"
    echo -e "${GREEN}  ✓ 已注入 splash.rgb565（来自本仓库根）${NC}"
elif [ -f "${OMP_AC820}/splash.rgb565" ]; then
    cp "${OMP_AC820}/splash.rgb565" "${SD_BOOT}/splash.rgb565"
    echo -e "${GREEN}  ✓ 已注入 splash.rgb565（来自 OMP-AC820-PetaLinux 仓库根）${NC}"
else
    echo -e "${YELLOW}  ⚠ 未找到 splash.rgb565，BOOT 分区无首屏图。可在 OMP-AC820-PetaLinux 根目录运行 ./scripts/make_splash.sh 生成后重新执行本一键脚本。${NC}"
fi
echo ""

echo -e "${YELLOW}[3/3] 烧录 SD 卡...${NC}"
"${SCRIPT_DIR}/step5_flash_sd_card.sh"
