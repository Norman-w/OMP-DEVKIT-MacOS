#!/bin/bash
# ============================================================================
# [macOS] 配置到远程 Ubuntu VM 的 SSH 免密登录
# ============================================================================
#
# 用法: ./scripts/setup_ssh_key_to_vm.sh
#
# 作用:
#   1. 若本机没有 SSH 公钥则生成（ed25519）
#   2. 将公钥拷贝到 VM，实现 norman@10.10.10.1 免密登录
#
# 变量（可按需修改）:
#   VM_IP=10.10.10.1
#   VM_USER=norman
# ============================================================================

set -e

VM_IP="${VM_IP:-10.10.10.1}"
VM_USER="${VM_USER:-norman}"
REMOTE="${VM_USER}@${VM_IP}"
KEY_FILE="${HOME}/.ssh/id_ed25519"
PUB_FILE="${KEY_FILE}.pub"

echo "目标: $REMOTE"
echo ""

# 1. 若没有 ed25519 密钥则生成（无口令，直接回车）
if [ ! -f "$KEY_FILE" ]; then
    echo "未检测到 $KEY_FILE，正在生成 SSH 密钥（ed25519）..."
    ssh-keygen -t ed25519 -N "" -f "$KEY_FILE" -C "macos-to-vm-${VM_USER}@${VM_IP}"
    echo "密钥已生成: $KEY_FILE"
else
    echo "已存在密钥: $KEY_FILE"
fi

# 2. 将公钥拷贝到 VM（会提示输入一次 VM 上的 norman 密码）
echo ""
echo "正在将公钥拷贝到 $REMOTE（需输入一次 VM 上的用户密码）..."
if command -v ssh-copy-id &>/dev/null; then
    ssh-copy-id -i "$PUB_FILE" "$REMOTE"
else
    echo "未找到 ssh-copy-id，请手动执行："
    echo "  cat $PUB_FILE | ssh $REMOTE 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'"
    exit 1
fi

echo ""
echo "免密登录已配置完成。可执行以下命令验证："
echo "  ssh $REMOTE"
echo ""
