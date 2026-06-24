#!/bin/bash

# Xray VLESS 服务器卸载脚本
# 用途：卸载由 xray-install.sh 安装的 Xray 服务及相关文件
# 使用方法:
#   sudo bash xray-uninstall.sh        # 交互式确认后卸载
#   sudo bash xray-uninstall.sh -y     # 跳过确认直接卸载

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}[步骤 $1]${NC} $2"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本必须以root身份运行"
    echo "请使用: sudo bash xray-uninstall.sh"
    exit 1
fi

XRAY_CONFIG="/etc/xray/config.json"

# 解析参数
ASSUME_YES=0
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
    ASSUME_YES=1
fi

# ============ 确认 ============
echo ""
echo -e "${YELLOW}即将卸载 Xray，并删除以下内容：${NC}"
echo "  - systemd 服务: /etc/systemd/system/xray.service"
echo "  - 程序目录:     /usr/local/Xray"
echo "  - 配置目录:     /etc/xray"
echo "  - 日志目录:     /var/log/xray"
echo "  - 相关防火墙规则（如使用 UFW）"
echo ""

if [[ $ASSUME_YES -ne 1 ]]; then
    read -r -p "确认卸载？(y/N) " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *)
            print_info "已取消卸载"
            exit 0
            ;;
    esac
fi

# ============ 步骤1: 读取端口（用于清理防火墙，须在删除配置前进行） ============
print_step "1" "读取配置信息"

XRAY_PORT=""
if [[ -f "$XRAY_CONFIG" ]]; then
    XRAY_PORT=$(grep -oP '"port":\s*\K\d+' "$XRAY_CONFIG" | head -1 || true)
    if [[ -n "$XRAY_PORT" ]]; then
        print_success "检测到监听端口: ${YELLOW}$XRAY_PORT${NC}"
    else
        print_info "未能从配置文件读取端口"
    fi
else
    print_info "配置文件不存在，跳过端口读取"
fi

# ============ 步骤2: 停止并禁用服务 ============
print_step "2" "停止并禁用服务"

if systemctl list-unit-files 2>/dev/null | grep -q '^xray\.service'; then
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    print_success "服务已停止并禁用"
else
    print_info "未找到 xray 服务（跳过）"
fi

# ============ 步骤3: 删除 systemd 服务文件 ============
print_step "3" "删除 systemd 服务文件"

if [[ -f /etc/systemd/system/xray.service ]]; then
    rm -f /etc/systemd/system/xray.service
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    print_success "服务文件已删除"
else
    print_info "服务文件不存在（跳过）"
fi

# ============ 步骤4: 清理防火墙规则 ============
print_step "4" "清理防火墙规则"

if systemctl is-active --quiet ufw && [[ -n "$XRAY_PORT" ]]; then
    ufw delete allow "$XRAY_PORT"/tcp > /dev/null 2>&1 || true
    ufw delete allow "$XRAY_PORT"/udp > /dev/null 2>&1 || true
    print_success "已删除端口 $XRAY_PORT 的防火墙规则"
else
    print_info "UFW 未启用或端口未知（跳过）"
fi

# ============ 步骤5: 删除程序、配置和日志 ============
print_step "5" "删除程序、配置和日志"

rm -rf /usr/local/Xray
rm -rf /etc/xray
rm -rf /var/log/xray
print_success "已删除程序、配置和日志目录"

# ============ 完成 ============
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
print_success "Xray 已完整卸载"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
print_info "提示：安装时装的依赖 (curl wget unzip uuid-runtime openssl) 为系统常用工具，未自动删除"
echo ""
