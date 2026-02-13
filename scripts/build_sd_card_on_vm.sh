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

# 先 fetch，再尝试 pull；若因本地修改被覆盖而失败，则展示改动并询问是否覆盖
run_pull_and_build() {
    ssh -t "$REMOTE" "cd ${VM_OMP_ROOT} && bash -lic 'git pull && ./do build card'"
}

set +e
run_pull_and_build 2>&1 | tee /tmp/vm_pull_output.$$
pull_exit=${PIPESTATUS[0]}
set -e
if [ "$pull_exit" -ne 0 ]; then
    # 检查是否因「本地修改将被合并覆盖」而失败
    if grep -q "您对下列文件的本地修改将被合并操作覆盖" /tmp/vm_pull_output.$$ 2>/dev/null || \
       grep -q "Your local changes to the following files would be overwritten by merge" /tmp/vm_pull_output.$$ 2>/dev/null; then
        echo ""
        echo -e "${YELLOW}---------- VM 上以下文件有本地修改，会被 pull 覆盖 ----------${NC}"
        # 从错误信息中提取文件列表（下一行缩进空格开头的路径；兼容 macOS BSD sed/grep）
        sed -E -n '/本地修改将被合并操作覆盖|would be overwritten by merge/,/请在合并前|Please commit or stash/p' /tmp/vm_pull_output.$$ | grep -E '^[[:space:]]+[a-zA-Z0-9_/].*' | sed 's/^[[:space:]]*//' | sort -u > /tmp/vm_conflict_files.$$
        conflict_files="$(cat /tmp/vm_conflict_files.$$)"
        echo "$conflict_files"
        echo ""
        echo -e "${YELLOW}---------- 这些文件在 VM 上的本地改动（git diff）----------${NC}"
        # 在 VM 上对上述文件执行 git diff，展示改动内容
        for f in $conflict_files; do
            echo "--- $f ---"
            ssh "$REMOTE" "cd ${VM_OMP_ROOT} && git diff -- '${f}'" 2>/dev/null || true
        done
        echo -e "${YELLOW}-----------------------------------------------------------${NC}"
        echo ""
        read -p "是否用远程版本覆盖上述本地修改并继续 pull？(y/N): " answer
        answer_lower="$(echo "$answer" | tr '[:upper:]' '[:lower:]')"
        if [[ "$answer_lower" == "y" || "$answer_lower" == "yes" ]]; then
            echo -e "${YELLOW}正在 VM 上 stash 本地修改并重新 pull...${NC}"
            ssh -t "$REMOTE" "cd ${VM_OMP_ROOT} && bash -lic 'git stash push -u -m \"onekey_sd_card auto-stash\" && git pull && ./do build card'" || {
                echo -e "${RED}VM 上 git stash/pull 或 ./do build card 失败${NC}"
                rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$
                exit 1
            }
        else
            echo "已取消。请先在 VM 上提交或贮藏修改后再运行本脚本。"
            rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$
            exit 1
        fi
        rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$
    else
        echo -e "${RED}VM 上 git pull 或 ./do build card 失败${NC}"
        rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$
        exit 1
    fi
fi
rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$
