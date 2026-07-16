#!/bin/bash

# AWS CLI v2 一键安装脚本（官方安装包方式，版本最新）
# 自动识别架构(x86_64 / aarch64)，幂等(已装则跳过，除非 --force)。
#
# 用法:
#   curl -fsSL <url>/install-awscli.sh | sudo bash
#   sudo bash install-awscli.sh          # 本地
#   sudo bash install-awscli.sh --force  # 强制重装/升级

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}"; }

FORCE=0
[[ "${1:-}" == "--force" || "${1:-}" == "-f" ]] && FORCE=1

# root 检查(安装到 /usr/local 需要)
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本需要 root 权限，请用 sudo"
    exit 1
fi

# 幂等：已装且非强制则跳过
if command -v aws >/dev/null 2>&1 && [[ $FORCE -ne 1 ]]; then
    print_success "AWS CLI 已安装: $(aws --version 2>&1)"
    print_info "如需重装/升级，请加 --force"
    exit 0
fi

# 识别架构
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)  AWS_ZIP="awscli-exe-linux-x86_64.zip" ;;
    aarch64|arm64) AWS_ZIP="awscli-exe-linux-aarch64.zip" ;;
    *) print_error "不支持的架构: $ARCH"; exit 1 ;;
esac
print_info "架构: $ARCH -> $AWS_ZIP"

# 装依赖 unzip
if ! command -v unzip >/dev/null 2>&1; then
    print_info "安装 unzip..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq unzip
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q unzip
    else
        print_error "未找到 apt-get/yum，请手动安装 unzip 后重试"
        exit 1
    fi
fi

# 临时目录，退出时清理
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cd "$TMP_DIR"

print_info "下载 AWS CLI v2 ..."
if ! curl -fsSL "https://awscli.amazonaws.com/${AWS_ZIP}" -o awscliv2.zip; then
    print_error "下载失败，请检查网络"
    exit 1
fi

print_info "解压..."
unzip -q awscliv2.zip

# 已装过时 install 需要 --update
print_info "安装到 /usr/local ..."
if command -v aws >/dev/null 2>&1; then
    ./aws/install --update
else
    ./aws/install
fi

# 验证
if command -v aws >/dev/null 2>&1; then
    print_success "安装完成: $(aws --version 2>&1)"
else
    # /usr/local/bin 可能不在当前 PATH
    if [[ -x /usr/local/bin/aws ]]; then
        print_success "安装完成: $(/usr/local/bin/aws --version 2>&1)"
        print_info "若命令未找到，请确认 /usr/local/bin 在 PATH 中"
    else
        print_error "安装后未找到 aws 命令"
        exit 1
    fi
fi

echo ""
print_info "下一步：在 EC2 上推荐挂 IAM 角色(Instance Profile)，无需 aws configure"
print_info "  验证凭据: aws sts get-caller-identity"
