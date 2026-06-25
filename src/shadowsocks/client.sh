#!/bin/bash

# Shadowsocks 客户端管理脚本（shadowsocks-rust sslocal）
# 用子命令区分操作：
#   sudo bash client.sh install "ss://..."   # 安装本地 SOCKS5 代理（127.0.0.1:1080）
#   SS_LINK="ss://..." sudo bash client.sh install
#   sudo bash client.sh uninstall            # 卸载
#   sudo bash client.sh status               # 服务状态
#   sudo bash client.sh logs                 # 实时日志
#   sudo bash client.sh help
# curl|bash 用法:
#   curl -fsSL <url>/client.sh | sudo bash -s install "ss://..."
#   curl -fsSL <url>/client.sh | sudo SS_LINK="ss://..." bash -s install

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

CLIENT_DIR="/etc/shadowsocks-client"
CLIENT_CONFIG="$CLIENT_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/shadowsocks-client.service"
SSLOCAL_BIN="/usr/local/bin/sslocal"
SOCKS_PORT=1080
SS_RUST_VERSION="v1.20.3"

print_help() {
    echo -e "${BLUE}Shadowsocks 客户端管理工具${NC}"
    echo ""
    echo "用法: sudo bash client.sh <命令> [参数]"
    echo ""
    echo -e "${YELLOW}可用命令:${NC}"
    echo "  install \"ss://...\"   安装本地 SOCKS5 代理（127.0.0.1:$SOCKS_PORT）"
    echo "                       也可用 SS_LINK 环境变量传链接"
    echo "  uninstall            卸载客户端"
    echo "  status               查看服务状态"
    echo "  logs                 查看实时日志"
    echo "  help                 显示此帮助信息"
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

# 解析 ss:// 链接，导出全局变量 S_METHOD S_PASSWORD S_HOST S_PORT
# 兼容两种编码：
#   ss://base64(method:password)@host:port#tag        （SIP002）
#   ss://base64(method:password@host:port)#tag        （旧版整体 base64）
parse_ss_link() {
    local link="$1"
    link="${link#ss://}"
    link="${link%%#*}"          # 去掉 #tag
    link="${link%%/\?*}"        # 去掉可能的 /?plugin=...
    link="${link%%\?*}"

    local b64decode
    b64decode() {
        # 容错：补齐 base64 padding 并兼容 URL-safe
        local s="$1"
        s="${s//-/+}"; s="${s//_/\/}"
        local pad=$(( ${#s} % 4 ))
        [[ $pad -gt 0 ]] && s="${s}$(printf '=%.0s' $(seq 1 $((4 - pad))))"
        echo "$s" | base64 -d 2>/dev/null
    }

    if [[ "$link" == *@* ]]; then
        # SIP002: userinfo 部分是 base64(method:password)
        local userinfo="${link%@*}"
        local hostport="${link##*@}"
        local decoded
        decoded="$(b64decode "$userinfo")"
        # 若 userinfo 不是 base64（明文 method:password），直接使用
        [[ -z "$decoded" ]] && decoded="$userinfo"
        S_METHOD="${decoded%%:*}"
        S_PASSWORD="${decoded#*:}"
        S_HOST="${hostport%%:*}"
        S_PORT="${hostport##*:}"
    else
        # 旧版：整体 base64(method:password@host:port)
        local decoded
        decoded="$(b64decode "$link")"
        if [[ -z "$decoded" ]]; then
            print_error "无法解析 ss:// 链接（base64 解码失败）"
            exit 1
        fi
        local creds="${decoded%@*}"     # method:password
        local hostport="${decoded##*@}" # host:port
        S_METHOD="${creds%%:*}"
        S_PASSWORD="${creds#*:}"
        S_HOST="${hostport%%:*}"
        S_PORT="${hostport##*:}"
    fi

    if [[ -z "${S_METHOD:-}" || -z "${S_PASSWORD:-}" || -z "${S_HOST:-}" || -z "${S_PORT:-}" ]]; then
        print_error "ss:// 链接缺少必需字段 (method/password/host/port)"
        exit 1
    fi
    print_success "解析成功: $S_HOST:$S_PORT ($S_METHOD)"
}

# 检测架构并下载安装 shadowsocks-rust sslocal（若已存在则跳过）
install_sslocal() {
    print_step "1" "检测架构并安装 sslocal"
    local arch target
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  target="x86_64-unknown-linux-gnu" ;;
        aarch64|arm64) target="aarch64-unknown-linux-gnu" ;;
        *) print_error "不支持的架构: $arch"; exit 1 ;;
    esac
    print_success "架构: $arch -> $target"

    if [[ -x "$SSLOCAL_BIN" ]]; then
        print_info "检测到已存在 sslocal，跳过下载"
        return 0
    fi

    print_info "安装依赖 (curl xz-utils)..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y curl xz-utils >/dev/null
    fi

    cd /tmp
    local url tar
    tar="shadowsocks-${SS_RUST_VERSION}.${target}.tar.xz"
    url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_RUST_VERSION}/${tar}"
    print_info "下载 shadowsocks-rust ${SS_RUST_VERSION} ..."
    if ! curl -fsSL "$url" -o ss-rust.tar.xz; then
        print_error "下载失败: $url"
        exit 1
    fi
    tar -xJf ss-rust.tar.xz sslocal
    mv sslocal "$SSLOCAL_BIN"
    rm -f ss-rust.tar.xz
    chmod +x "$SSLOCAL_BIN"
    print_success "sslocal 安装完成"
}

# 生成客户端 config.json
write_config() {
    print_step "2" "生成客户端配置"
    mkdir -p "$CLIENT_DIR"
    cat > "$CLIENT_CONFIG" <<EOF
{
    "server": "$S_HOST",
    "server_port": $S_PORT,
    "password": "$S_PASSWORD",
    "method": "$S_METHOD",
    "local_address": "127.0.0.1",
    "local_port": $SOCKS_PORT,
    "mode": "tcp_and_udp"
}
EOF
    print_success "配置已写入 $CLIENT_CONFIG"
}

# 安装并启动 systemd 服务
setup_service() {
    print_step "3" "配置 systemd 服务"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Shadowsocks Client (sslocal)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$SSLOCAL_BIN -c $CLIENT_CONFIG
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl restart shadowsocks-client
    sleep 2
    if systemctl is-active --quiet shadowsocks-client; then
        print_success "shadowsocks-client 服务已启动"
    else
        print_error "服务启动失败"
        journalctl -u shadowsocks-client -n 20
        exit 1
    fi
    systemctl enable shadowsocks-client >/dev/null 2>&1
    print_success "已设置开机自启"
}

print_result() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    print_success "Shadowsocks 客户端已启动，SOCKS5 代理: 127.0.0.1:$SOCKS_PORT"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}测试连接:${NC}"
    echo "  curl -x socks5h://127.0.0.1:$SOCKS_PORT https://www.google.com"
    echo "  curl -x socks5h://127.0.0.1:$SOCKS_PORT https://ipinfo.io/ip"
    echo ""
    echo -e "${YELLOW}管理命令:${NC}"
    echo "  sudo bash client.sh status"
    echo "  sudo bash client.sh logs"
    echo "  sudo bash client.sh uninstall"
    echo ""
}

do_install() {
    require_root
    local link="${1:-${SS_LINK:-}}"
    if [[ -z "$link" ]]; then
        print_error "未提供 ss:// 链接"
        print_help
        exit 1
    fi
    parse_ss_link "$link"
    install_sslocal
    write_config
    setup_service
    print_result
}

do_uninstall() {
    require_root
    print_step "1" "卸载 Shadowsocks 客户端"
    if systemctl list-unit-files 2>/dev/null | grep -q '^shadowsocks-client\.service'; then
        systemctl stop shadowsocks-client 2>/dev/null || true
        systemctl disable shadowsocks-client 2>/dev/null || true
        print_success "服务已停止并禁用"
    else
        print_info "未找到 shadowsocks-client 服务（跳过）"
    fi
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        systemctl reset-failed 2>/dev/null || true
        print_success "服务文件已删除"
    fi
    rm -rf "$CLIENT_DIR"
    rm -f "$SSLOCAL_BIN"
    print_success "已删除 $CLIENT_DIR 及 sslocal 二进制"
}

show_status() {
    require_root
    systemctl status shadowsocks-client
}

show_logs() {
    require_root
    journalctl -u shadowsocks-client -f
}

# ===== 入口：子命令分发 =====
ACTION="${1:-help}"

case "$ACTION" in
    install)        do_install "${2:-}" ;;
    uninstall)      do_uninstall ;;
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
