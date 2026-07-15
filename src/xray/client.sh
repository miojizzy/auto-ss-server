#!/bin/bash

# Xray 客户端管理脚本（REALITY）
# 用子命令区分操作：
#   sudo bash client.sh install "vless://..."   # 安装本地 SOCKS5 代理（127.0.0.1:1080）
#   VLESS_LINK="vless://..." sudo bash client.sh install
#   sudo bash client.sh uninstall [-y]        # 卸载（-y 跳过确认）
#   sudo bash client.sh status                  # 服务状态
#   sudo bash client.sh logs                    # 实时日志
#   sudo bash client.sh help
# curl|bash 用法:
#   curl -fsSL <url>/client.sh | sudo bash -s install "vless://..."
#   curl -fsSL <url>/client.sh | sudo VLESS_LINK="vless://..." bash -s install

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step()    { echo -e "${BLUE}========================================${NC}"; echo -e "${GREEN}[步骤 $1]${NC} $2"; echo -e "${BLUE}========================================${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}"; }

CLIENT_DIR="/etc/xray-client"
CLIENT_CONFIG="$CLIENT_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/xray-client.service"
XRAY_BIN="/usr/local/Xray/xray"
SOCKS_PORT=1080

print_help() {
    echo -e "${BLUE}Xray 客户端管理工具${NC}"
    echo ""
    echo "用法: sudo bash client.sh <命令> [参数]"
    echo ""
    echo -e "${YELLOW}可用命令:${NC}"
    echo "  install \"vless://...\"   安装本地 SOCKS5 代理（127.0.0.1:$SOCKS_PORT）"
    echo "                          也可用 VLESS_LINK 环境变量传链接"
    echo "  uninstall [-y]          卸载客户端（-y 跳过确认）"
    echo "  status                  查看服务状态"
    echo "  logs                    查看实时日志"
    echo "  help                    显示此帮助信息"
    echo ""
    echo "链接从服务端获取: sudo bash server.sh config"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此操作必须以 root 身份运行"
        echo "请使用 sudo"
        exit 1
    fi
}

# 解析 vless:// 链接，导出全局变量 V_UUID V_IP V_PORT V_PBK V_SID V_SNI V_FLOW V_FP V_SECURITY
parse_link() {
    local link="$1"
    link="${link#vless://}"
    link="${link%%#*}"

    local userinfo="${link%%\?*}"     # uuid@ip:port
    local query="${link#*\?}"         # 查询串
    [[ "$query" == "$link" ]] && query=""

    V_UUID="${userinfo%%@*}"
    local hostport="${userinfo#*@}"   # ip:port
    V_IP="${hostport%%:*}"
    V_PORT="${hostport##*:}"

    _q() { echo "$query" | tr '&' '\n' | grep -E "^$1=" | head -1 | cut -d= -f2-; }
    V_SECURITY="$(_q security)"
    V_PBK="$(_q pbk)"
    V_SID="$(_q sid)"
    V_SNI="$(_q sni)"
    V_FLOW="$(_q flow)"
    V_FP="$(_q fp)"
    [[ -z "$V_FP" ]] && V_FP="chrome"

    if [[ "$V_SECURITY" != "reality" ]]; then
        print_error "链接 security 必须为 reality（当前: ${V_SECURITY:-空}）"
        exit 1
    fi
    if [[ -z "$V_UUID" || -z "$V_IP" || -z "$V_PORT" || -z "$V_PBK" ]]; then
        print_error "链接缺少必需字段 (uuid/ip/port/pbk)"
        print_help
        exit 1
    fi
}

# 检测架构并下载安装 Xray 二进制（若已存在则跳过下载）
install_xray() {
    print_step "1" "检测架构并安装 Xray"
    local arch zip
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  zip="Xray-linux-64.zip" ;;
        aarch64|arm64) zip="Xray-linux-arm64-v8a.zip" ;;
        *) print_error "不支持的架构: $arch"; exit 1 ;;
    esac
    print_success "架构: $arch -> $zip"

    if [[ -x "$XRAY_BIN" ]]; then
        print_info "检测到已存在 Xray 二进制，跳过下载"
        return 0
    fi

    print_info "安装依赖 (curl unzip)..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y curl unzip >/dev/null
    fi

    mkdir -p /usr/local/Xray
    cd /tmp
    local ver url
    ver="$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
    url="https://github.com/XTLS/Xray-core/releases/download/${ver}/${zip}"
    print_info "下载 Xray ${ver} ..."
    if ! curl -fsSL "$url" -o xray-client.zip; then
        print_error "下载失败: $url"
        exit 1
    fi
    unzip -o xray-client.zip xray -d /usr/local/Xray >/dev/null
    rm -f xray-client.zip
    chmod +x "$XRAY_BIN"
    print_success "Xray 安装完成"
}

# 生成客户端 config.json
write_config() {
    print_step "2" "生成客户端配置"
    mkdir -p "$CLIENT_DIR"
    cat > "$CLIENT_CONFIG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": $SOCKS_PORT,
      "protocol": "socks",
      "settings": { "udp": true }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$V_IP",
            "port": $V_PORT,
            "users": [
              { "id": "$V_UUID", "encryption": "none", "flow": "$V_FLOW" }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "$V_SNI",
          "fingerprint": "$V_FP",
          "publicKey": "$V_PBK",
          "shortId": "$V_SID"
        }
      }
    }
  ]
}
EOF
    print_success "配置已写入 $CLIENT_CONFIG"

    print_info "验证配置..."
    if ! "$XRAY_BIN" -test -c "$CLIENT_CONFIG" >/dev/null 2>&1; then
        print_error "配置验证失败"
        "$XRAY_BIN" -test -c "$CLIENT_CONFIG"
        exit 1
    fi
    print_success "配置验证通过"
}

# 安装并启动 systemd 服务
setup_service() {
    print_step "3" "配置 systemd 服务"
    cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Xray Client Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/Xray/xray -c /etc/xray-client/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl restart xray-client
    sleep 2
    if systemctl is-active --quiet xray-client; then
        print_success "xray-client 服务已启动"
    else
        print_error "服务启动失败"
        journalctl -u xray-client -n 20
        exit 1
    fi
    systemctl enable xray-client >/dev/null 2>&1
    print_success "已设置开机自启"
}

print_result() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    print_success "Xray 客户端已启动，SOCKS5 代理: 127.0.0.1:$SOCKS_PORT"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}测试连接:${NC}"
    echo "  curl -x socks5h://127.0.0.1:$SOCKS_PORT https://www.google.com"
    echo "  curl -x socks5h://127.0.0.1:$SOCKS_PORT https://ipinfo.io/ip"
    echo ""
    echo -e "${YELLOW}管理命令:${NC}"
    echo "  sudo bash client.sh status"
    echo "  sudo bash client.sh logs"
    echo "  sudo bash client.sh uninstall      # 交互确认"
    echo "  sudo bash client.sh uninstall -y   # 跳过确认"
    echo ""
}

do_install() {
    require_root
    local link="${1:-${VLESS_LINK:-}}"
    if [[ -z "$link" ]]; then
        print_error "未提供 vless:// 链接"
        print_help
        exit 1
    fi
    parse_link "$link"
    install_xray
    write_config
    setup_service
    print_result
}

do_uninstall() {
    require_root
    local force="${1:-}"
    print_step "1" "卸载 Xray 客户端"

    # 幂等：完全没装过就直接返回
    if ! systemctl list-unit-files 2>/dev/null | grep -q '^xray-client\.service' \
       && [[ ! -f "$SERVICE_FILE" ]] \
       && [[ ! -d "$CLIENT_DIR" ]] \
       && [[ ! -x "$XRAY_BIN" ]]; then
        print_info "未检测到 xray-client 安装痕迹，无需卸载"
        return 0
    fi

    # 交互确认（-y 跳过）
    if [[ "$force" != "-y" && "$force" != "--yes" ]]; then
        echo ""
        echo "将删除以下内容："
        [[ -f "$SERVICE_FILE" ]] && echo "  - 服务: $SERVICE_FILE"
        [[ -d "$CLIENT_DIR" ]]   && echo "  - 配置目录: $CLIENT_DIR"
        [[ -x "$XRAY_BIN" ]]     && echo "  - 二进制: $XRAY_BIN"
        echo ""
        read -rp "确认卸载？[y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] || { print_info "已取消"; return 0; }
    fi

    # 1) 停服务
    if systemctl list-unit-files 2>/dev/null | grep -q '^xray-client\.service'; then
        systemctl stop xray-client 2>/dev/null || true
        systemctl disable xray-client 2>/dev/null || true
        print_success "服务已停止并禁用"
    fi

    # 2) 删服务文件
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        systemctl reset-failed 2>/dev/null || true
        print_success "服务文件已删除"
    fi

    # 3) 删配置目录
    if [[ -d "$CLIENT_DIR" ]]; then
        rm -rf "$CLIENT_DIR"
        print_success "已删除 $CLIENT_DIR"
    fi

    # 4) 二进制：只在没有服务端/其它用户时删
    if [[ -x "$XRAY_BIN" ]]; then
        if ss -tlnp 2>/dev/null | grep -q xray; then
            print_info "检测到其它 xray 进程在运行，保留 $XRAY_BIN"
        elif [[ -f /etc/systemd/system/xray.service ]]; then
            print_info "检测到 xray.service 服务端，保留 $XRAY_BIN"
        else
            rm -f "$XRAY_BIN"
            # 如果 /usr/local/Xray 是空的（连 geoip 之类也没有），一起清
            rmdir /usr/local/Xray 2>/dev/null && \
                print_success "已删除 $XRAY_BIN 及 /usr/local/Xray" || \
                print_success "已删除 $XRAY_BIN"
        fi
    fi

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    print_success "Xray 客户端卸载完成"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
}

show_status() {
    require_root
    systemctl status xray-client
}

show_logs() {
    require_root
    journalctl -u xray-client -f
}

# ===== 入口：子命令分发 =====
ACTION="${1:-help}"

case "$ACTION" in
    install)        do_install "${2:-}" ;;
    uninstall)      do_uninstall "${2:-}" ;;
    status)         show_status ;;
    logs)           show_logs ;;
    help|-h|--help) print_help ;;
    *)
        print_error "未知命令: $ACTION"
        echo ""
        print_help
        exit 1
        ;;
esac
