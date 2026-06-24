#!/bin/bash

# Xray VLESS 服务器安装脚本（REALITY 协议，无需证书）
# Ubuntu 26 ARM版本
# 使用方法:
#   bash xray-install.sh [端口号]
#   curl -fsSL https://example.com/xray-install.sh | bash
#   curl -fsSL https://example.com/xray-install.sh | bash -s 8443
#   wget -O - https://example.com/xray-install.sh | bash
#   XRAY_PORT=8443 bash xray-install.sh

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
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

# ============ 网络诊断函数 ============
check_network() {
    print_info "检查网络连接..."

    # 测试 DNS 解析
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        print_info "无法连接到 8.8.8.8，尝试其他 DNS..."
        if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
            print_error "网络连接失败，请检查网络设置"
            return 1
        fi
    fi

    # 测试 GitHub 连接
    if ! curl -s --connect-timeout 5 https://github.com >/dev/null 2>&1; then
        print_error "无法连接到 GitHub，请检查："
        echo "  1. 网络连接是否正常"
        echo "  2. 是否需要配置代理"
        echo "  3. DNS 是否可用"
        return 1
    fi

    print_success "网络连接正常"
    return 0
}

# ============ 代理配置函数 ============
setup_proxy() {
    if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
        print_info "检测到代理设置"
        print_info "HTTP_PROXY: ${HTTP_PROXY:-未设置}"
        print_info "HTTPS_PROXY: ${HTTPS_PROXY:-未设置}"
    fi
}

# ============ 清理函数 ============
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        print_error "安装失败 (退出码: $exit_code)"
        print_info "请查看上面的错误信息"
    fi
    return $exit_code
}

trap cleanup EXIT

# 检查是否为root
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本必须以root身份运行"
    echo "请使用: sudo -i bash xray-install.sh"
    echo "或者: curl -fsSL https://example.com/xray-install.sh | sudo bash"
    exit 1
fi

# ============ 阶段0: 网络环境检查 ============
print_step "0" "网络环境检查"

setup_proxy
check_network

# ============ 阶段1: 系统准备 ============
print_step "1" "系统准备和依赖安装"

print_info "更新系统包列表..."
apt-get update
print_success "系统包列表已更新"

print_info "安装必要的依赖..."
if ! apt-get install -y curl wget unzip uuid-runtime openssl; then
    print_error "依赖安装失败"
    exit 1
fi
print_success "依赖安装完成"

# ============ 阶段2: 安装Xray核心 ============
print_step "2" "安装Xray核心"

print_info "检查Xray安装目录..."
mkdir -p /usr/local/Xray
mkdir -p /etc/xray
mkdir -p /var/log/xray

print_info "下载Xray核心（ARM64版本）..."
cd /tmp
XRAY_VERSION=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
print_info "最新版本: ${XRAY_VERSION}"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-arm64-v8a.zip"

# 尝试下载
if wget -v "$XRAY_URL" -O xray.zip 2>&1; then
    print_success "Xray核心下载成功"
else
    print_error "下载失败，请检查网络连接"
    exit 1
fi

print_info "解压Xray..."
if ! unzip -o xray.zip; then
    print_error "解压失败"
    exit 1
fi
rm -f xray.zip

print_info "安装Xray到系统目录..."
mv xray /usr/local/Xray/
chmod +x /usr/local/Xray/xray
print_success "Xray核心安装完成"

# ============ 阶段3: 配置端口 ============
print_step "3" "配置Xray端口"

# 从环境变量或参数获取端口，默认443
XRAY_PORT="${XRAY_PORT:-${1:-443}}"

# 验证端口号
if ! [[ "$XRAY_PORT" =~ ^[0-9]+$ ]] || [ "$XRAY_PORT" -lt 1 ] || [ "$XRAY_PORT" -gt 65535 ]; then
    print_error "无效的端口号: $XRAY_PORT (有效范围: 1-65535)"
    exit 1
fi

print_success "使用端口: ${YELLOW}$XRAY_PORT${NC}"

# ============ 阶段4: 生成UUID ============
print_step "4" "生成UUID"

print_info "生成随机UUID..."
XRAY_UUID=$(uuidgen)
print_success "生成的UUID: ${YELLOW}$XRAY_UUID${NC}"

# ============ 阶段5: 获取服务器IP ============
print_step "5" "获取服务器IP地址"

print_info "检测服务器公网IP地址..."
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
    || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
    || curl -s --max-time 5 https://icanhazip.com 2>/dev/null \
    || hostname -I | awk '{print $1}')
SERVER_IP=$(echo "$SERVER_IP" | tr -d '[:space:]')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="127.0.0.1"
    print_info "未检测到IP，使用localhost（请手动修改为实际IP）"
else
    print_success "检测到服务器公网IP: ${YELLOW}$SERVER_IP${NC}"
fi

# ============ 阶段5b: 生成 REALITY 密钥 ============
print_step "5" "生成 REALITY 密钥"

# 伪装目标（借用真实大站的 TLS 指纹）
REALITY_DEST="www.microsoft.com:443"
REALITY_SERVER_NAME="www.microsoft.com"

print_info "生成 x25519 密钥对..."
X25519_OUTPUT=$(/usr/local/Xray/xray x25519)
# 兼容新旧版本字段名：旧版 "Private key:" / "Public key:"，新版 "PrivateKey:" / "Password:"
REALITY_PRIVATE_KEY=$(echo "$X25519_OUTPUT" | grep -iE 'private[ ]?key' | awk -F: '{print $2}' | tr -d '[:space:]')
REALITY_PUBLIC_KEY=$(echo "$X25519_OUTPUT" | grep -iE 'public[ ]?key|password' | awk -F: '{print $2}' | tr -d '[:space:]')

if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
    print_error "REALITY 密钥生成失败，无法解析 xray x25519 输出"
    echo "$X25519_OUTPUT"
    exit 1
fi
print_success "x25519 密钥对生成完成"

print_info "生成 shortId..."
REALITY_SHORT_ID=$(openssl rand -hex 8)
print_success "shortId: ${YELLOW}$REALITY_SHORT_ID${NC}"

# ============ 阶段6: 创建Xray配置文件 ============
print_step "6" "创建Xray配置文件"

print_info "生成配置文件: /etc/xray/config.json"

cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$XRAY_UUID",
            "flow": "xtls-rprx-vision",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DEST",
          "xver": 0,
          "serverNames": ["$REALITY_SERVER_NAME"],
          "privateKey": "$REALITY_PRIVATE_KEY",
          "shortIds": ["$REALITY_SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

print_success "配置文件创建完成"

print_info "保存 REALITY 参数到 /etc/xray/reality.env"
cat > /etc/xray/reality.env <<EOF
XRAY_PORT=$XRAY_PORT
XRAY_UUID=$XRAY_UUID
PUBLIC_KEY=$REALITY_PUBLIC_KEY
SHORT_ID=$REALITY_SHORT_ID
SERVER_NAME=$REALITY_SERVER_NAME
SERVER_IP=$SERVER_IP
EOF
chmod 600 /etc/xray/reality.env
print_success "REALITY 参数已保存"

# ============ 阶段7: 验证配置文件 ============
print_step "7" "验证配置文件"

print_info "检查配置文件语法..."
if /usr/local/Xray/xray -c /etc/xray/config.json -test; then
    print_success "配置文件验证通过"
else
    print_error "配置文件验证失败"
    exit 1
fi

# ============ 阶段8: 创建Systemd服务 ============
print_step "8" "创建Systemd服务"

print_info "创建服务文件: /etc/systemd/system/xray.service"

cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/Xray/xray -c /etc/xray/config.json
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

print_success "服务文件创建完成"

# ============ 阶段9: 启动服务 ============
print_step "9" "启动Xray服务"

print_info "重新加载systemd配置..."
systemctl daemon-reload
print_success "systemd配置已重新加载"

print_info "启动Xray服务..."
systemctl start xray
sleep 2

if systemctl is-active --quiet xray; then
    print_success "Xray服务启动成功"
else
    print_error "服务启动失败，请检查日志"
    journalctl -u xray -n 20
    exit 1
fi

print_info "设置开机自启..."
systemctl enable xray
print_success "开机自启已启用"

# ============ 阶段10: 防火墙配置 ============
print_step "10" "防火墙配置"

print_info "检查ufw防火墙状态..."
if systemctl is-active --quiet ufw; then
    print_info "UFW已启用，添加规则..."
    ufw allow "$XRAY_PORT"/tcp > /dev/null 2>&1
    ufw allow "$XRAY_PORT"/udp > /dev/null 2>&1
    print_success "防火墙规则已添加"
else
    print_info "UFW未启用（跳过）"
fi

# ============ 阶段11: 显示连接信息 ============
print_step "11" "配置完成 - 客户端连接信息"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}服务器配置信息${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BLUE}协议:${NC} VLESS"
echo -e "  ${BLUE}地址:${NC} $SERVER_IP"
echo -e "  ${BLUE}端口:${NC} $XRAY_PORT"
echo -e "  ${BLUE}UUID:${NC} $XRAY_UUID"
echo -e "  ${BLUE}传输:${NC} TCP"
echo -e "  ${BLUE}安全:${NC} REALITY"
echo -e "  ${BLUE}流控:${NC} xtls-rprx-vision"
echo -e "  ${BLUE}SNI:${NC} $REALITY_SERVER_NAME"
echo -e "  ${BLUE}公钥(pbk):${NC} $REALITY_PUBLIC_KEY"
echo -e "  ${BLUE}shortId(sid):${NC} $REALITY_SHORT_ID"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}VLESS分享链接${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "vless://$XRAY_UUID@$SERVER_IP:$XRAY_PORT?security=reality&encryption=none&pbk=$REALITY_PUBLIC_KEY&sid=$REALITY_SHORT_ID&sni=$REALITY_SERVER_NAME&fp=chrome&flow=xtls-rprx-vision&type=tcp#xray-reality"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""

# ============ 显示常用命令 ============
print_step "12" "常用管理命令"

echo -e "${YELLOW}查看服务状态:${NC}"
echo "  sudo systemctl status xray"
echo ""
echo -e "${YELLOW}重启服务:${NC}"
echo "  sudo systemctl restart xray"
echo ""
echo -e "${YELLOW}停止服务:${NC}"
echo "  sudo systemctl stop xray"
echo ""
echo -e "${YELLOW}查看实时日志:${NC}"
echo "  sudo journalctl -u xray -f"
echo ""
echo -e "${YELLOW}查看错误日志:${NC}"
echo "  sudo tail -f /var/log/xray/error.log"
echo ""
echo -e "${YELLOW}查看访问日志:${NC}"
echo "  sudo tail -f /var/log/xray/access.log"
echo ""

print_success "所有安装步骤已完成！"
echo ""
