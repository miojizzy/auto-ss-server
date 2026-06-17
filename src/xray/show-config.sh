#!/bin/bash

# 显示 Xray 连接信息脚本
# 用途：获取已安装的 Xray 服务器的连接信息

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

CONFIG_FILE="/etc/xray/config.json"

# 检查配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "配置文件不存在: $CONFIG_FILE"
    echo "请先运行安装脚本"
    exit 1
fi

# 提取连接信息
XRAY_PORT=$(grep -oP '"port":\s*\K\d+' "$CONFIG_FILE" | head -1)
XRAY_UUID=$(grep -oP '"id":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)
SERVER_IP=$(hostname -I | awk '{print $1}')

if [ -z "$XRAY_PORT" ] || [ -z "$XRAY_UUID" ] || [ -z "$SERVER_IP" ]; then
    print_error "无法提取连接信息"
    exit 1
fi

# 生成分享链接
VLESS_LINK="vless://$XRAY_UUID@$SERVER_IP:$XRAY_PORT?security=tls&flow=xtls-rprx-vision&type=tcp&allowInsecure=1"

# 显示信息
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Xray 服务器连接信息${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BLUE}协议:${NC} VLESS"
echo -e "  ${BLUE}地址:${NC} $SERVER_IP"
echo -e "  ${BLUE}端口:${NC} $XRAY_PORT"
echo -e "  ${BLUE}UUID:${NC} $XRAY_UUID"
echo -e "  ${BLUE}传输:${NC} TCP"
echo -e "  ${BLUE}安全:${NC} TLS"
echo -e "  ${BLUE}流控:${NC} xtls-rprx-vision"
echo -e "  ${BLUE}跳过证书验证:${NC} 是"
echo ""
echo -e "${YELLOW}VLESS 分享链接:${NC}"
echo ""
echo "$VLESS_LINK"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
