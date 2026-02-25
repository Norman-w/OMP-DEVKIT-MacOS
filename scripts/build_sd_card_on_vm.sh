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
VM_TARGET_BRANCH="${VM_TARGET_BRANCH:-master}"
VM_TARGET_MODE="${VM_TARGET_MODE:-branch}"
VM_TARGET_REF="${VM_TARGET_REF:-}"
VM_OMP_ROOT="$(dirname "$VM_SD_PATH")"
REMOTE="${VM_USER}@${VM_IP}"

# 兜底：避免把远程名 origin 当分支名；并兼容传入 origin/<branch>
if [ "$VM_TARGET_BRANCH" = "origin" ]; then
    VM_TARGET_BRANCH="master"
elif [[ "$VM_TARGET_BRANCH" == origin/* ]]; then
    VM_TARGET_BRANCH="${VM_TARGET_BRANCH#origin/}"
fi

if [ "$VM_TARGET_MODE" = "commit" ] && [ -z "$VM_TARGET_REF" ]; then
    VM_TARGET_MODE="branch"
fi

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 使用 bash -lic 启动 login+交互 shell，避免 .bashrc 因非交互而提前 return 导致 PLNX_PATH 未加载
echo -e "${YELLOW}在 VM ($REMOTE) OMP 工程目录执行 git pull 与 ./do build card...${NC}"
if [ "$VM_TARGET_MODE" = "commit" ]; then
    echo -e "${YELLOW}目标提交: ${VM_TARGET_REF}${NC}"
else
    echo -e "${YELLOW}目标分支: ${VM_TARGET_BRANCH}${NC}"
fi

if [ "$VM_TARGET_MODE" = "commit" ]; then
    run_checkout_commit_and_build() {
        ssh -t "$REMOTE" "cd ${VM_OMP_ROOT} && bash -lic 'git fetch origin --tags && git checkout ${VM_TARGET_REF} && ./do build card'"
    }

    set +e
    run_checkout_commit_and_build 2>&1 | tee /tmp/vm_pull_output.$$
    pull_exit=${PIPESTATUS[0]}
    set -e

    if [ "$pull_exit" -ne 0 ]; then
        if grep -q "您对下列文件的本地修改将被检出操作覆盖" /tmp/vm_pull_output.$$ 2>/dev/null || \
           grep -q "Your local changes to the following files would be overwritten by checkout" /tmp/vm_pull_output.$$ 2>/dev/null; then
            echo ""
            echo -e "${YELLOW}检测到 VM 本地修改阻止切换到目标提交。${NC}"
            read -p "是否先 stash 本地修改再继续？(y/N): " answer
            answer_lower="$(echo "$answer" | tr '[:upper:]' '[:lower:]')"
            if [[ "$answer_lower" == "y" || "$answer_lower" == "yes" ]]; then
                ssh -t "$REMOTE" "cd ${VM_OMP_ROOT} && bash -lic 'git stash push -u -m \"onekey_sd_card auto-stash-commit\" && git fetch origin --tags && git checkout ${VM_TARGET_REF} && ./do build card'" || {
                    echo -e "${RED}VM 上切换提交并构建失败${NC}"
                    rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$ 2>/dev/null || true
                    exit 1
                }
            else
                echo "已取消。请先在 VM 上处理本地修改后再运行本脚本。"
                rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$ 2>/dev/null || true
                exit 1
            fi
        else
            echo -e "${RED}VM 上切换提交或 ./do build card 失败${NC}"
            rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$ 2>/dev/null || true
            exit 1
        fi
    fi

    rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$ 2>/dev/null || true
    exit 0
fi

# 先 fetch，再尝试 pull；若因本地修改被覆盖而失败，则展示改动并询问是否覆盖
run_pull_and_build() {
    ssh -t "$REMOTE" "cd ${VM_OMP_ROOT} && bash -lic 'git fetch origin && git checkout ${VM_TARGET_BRANCH} && git pull --ff-only origin ${VM_TARGET_BRANCH} && ./do build card'"
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
			ssh -t "$REMOTE" "cd ${VM_OMP_ROOT} && bash -lic 'git stash push -u -m \"onekey_sd_card auto-stash\" && git fetch origin && git checkout ${VM_TARGET_BRANCH} && git pull --ff-only origin ${VM_TARGET_BRANCH} && ./do build card'" || {
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
        # 检查是否因分支分叉导致 --ff-only 失败
        if grep -q "无法快进" /tmp/vm_pull_output.$$ 2>/dev/null || \
           grep -q "Not possible to fast-forward" /tmp/vm_pull_output.$$ 2>/dev/null || \
           grep -q "fatal:.*fast-forward" /tmp/vm_pull_output.$$ 2>/dev/null; then
            echo ""
            echo -e "${YELLOW}检测到 VM 上 ${VM_TARGET_BRANCH} 与 origin/${VM_TARGET_BRANCH} 已分叉，--ff-only 无法继续。${NC}"
            echo -e "${YELLOW}可选处理：在 VM 上先创建备份分支，再强制对齐到 origin/${VM_TARGET_BRANCH} 后构建。${NC}"
            read -p "是否继续（会 reset --hard 到 origin/${VM_TARGET_BRANCH}）？(y/N): " answer
            answer_lower="$(echo "$answer" | tr '[:upper:]' '[:lower:]')"
            if [[ "$answer_lower" == "y" || "$answer_lower" == "yes" ]]; then
                backup_branch="backup/onekey-before-reset-$(date +%Y%m%d-%H%M%S)"
                echo -e "${YELLOW}正在 VM 上创建备份分支并强制对齐...${NC}"
                ssh -t "$REMOTE" "cd ${VM_OMP_ROOT} && bash -lic '\
                    git fetch origin && \
                    git checkout ${VM_TARGET_BRANCH} && \
                    git branch ${backup_branch} && \
                    git reset --hard origin/${VM_TARGET_BRANCH} && \
                    ./do build card'" || {
                    echo -e "${RED}VM 上 reset/build 失败${NC}"
                    rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$
                    exit 1
                }
                echo -e "${YELLOW}已在 VM 保留备份分支: ${backup_branch}${NC}"
            else
                echo "已取消。请先在 VM 上手动处理分叉后再运行本脚本。"
                rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$
                exit 1
            fi
        else
            echo -e "${RED}VM 上 git pull 或 ./do build card 失败${NC}"
            rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$
            exit 1
        fi
    fi
fi
rm -f /tmp/vm_pull_output.$$ /tmp/vm_conflict_files.$$
