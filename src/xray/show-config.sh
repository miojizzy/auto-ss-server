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

REALITY_ENV="/etc/xray/reality.env"

# 检查 REALITY 配置
if [ ! -f "$REALITY_ENV" ]; then
    print_error "未检测到 REALITY 配置: $REALITY_ENV"
    echo "请先运行安装脚本 (xray-install.sh)"
    exit 1
fi

# shellcheck disable=SC1090
source "$REALITY_ENV"

if [ -z "${XRAY_PORT:-}" ] || [ -z "${XRAY_UUID:-}" ] || [ -z "${PUBLIC_KEY:-}" ] \
   || [ -z "${SHORT_ID:-}" ] || [ -z "${SERVER_NAME:-}" ] || [ -z "${SERVER_IP:-}" ]; then
    print_error "REALITY 配置不完整，请重新运行安装脚本"
    exit 1
fi

# 生成分享链接
VLESS_LINK="vless://$XRAY_UUID@$SERVER_IP:$XRAY_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&sid=$SHORT_ID&sni=$SERVER_NAME&fp=chrome&flow=xtls-rprx-vision&type=tcp#xray-reality"

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
echo -e "  ${BLUE}安全:${NC} REALITY"
echo -e "  ${BLUE}流控:${NC} xtls-rprx-vision"
echo -e "  ${BLUE}SNI:${NC} $SERVER_NAME"
echo -e "  ${BLUE}公钥(pbk):${NC} $PUBLIC_KEY"
echo -e "  ${BLUE}shortId(sid):${NC} $SHORT_ID"
echo ""
echo -e "${YELLOW}VLESS 分享链接:${NC}"
echo ""
echo "$VLESS_LINK"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
