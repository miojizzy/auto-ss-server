#!/bin/bash

# Xray VLESS 服务器一键安装脚本
# 使用方法:
#   curl -fsSL https://raw.githubusercontent.com/你的用户名/auto-ss-server/main/install.sh | sudo bash
#   wget -O - https://raw.githubusercontent.com/你的用户名/auto-ss-server/main/install.sh | sudo bash

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# 检查权限
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本必须以 root 身份运行"
    echo "请使用: sudo curl -fsSL ... | bash"
    exit 1
fi

# GitHub 仓库信息（需要手动配置或从环境变量读取）
GITHUB_USER="${GITHUB_USER:-你的用户名}"
GITHUB_REPO="${GITHUB_REPO:-auto-ss-server}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

REPO_RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"
INSTALL_SCRIPT_URL="${REPO_RAW_URL}/src/xray/xray-install.sh"

print_info "准备安装 Xray..."
print_info "仓库: ${GITHUB_USER}/${GITHUB_REPO} (${GITHUB_BRANCH})"
print_info "脚本URL: ${INSTALL_SCRIPT_URL}"

# 临时目录
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# 下载安装脚本
print_info "正在下载安装脚本..."
if ! curl -fsSL "${INSTALL_SCRIPT_URL}" -o "${TEMP_DIR}/xray-install.sh"; then
    print_error "下载失败，请检查网络和仓库配置"
    echo "环境变量:"
    echo "  GITHUB_USER=${GITHUB_USER}"
    echo "  GITHUB_REPO=${GITHUB_REPO}"
    echo "  GITHUB_BRANCH=${GITHUB_BRANCH}"
    exit 1
fi

print_success "脚本下载成功"

# 执行安装脚本
print_info "执行安装脚本..."
bash "${TEMP_DIR}/xray-install.sh"
