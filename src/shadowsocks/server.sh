#!/bin/bash

# Shadowsocks (Outline) 服务端管理脚本
# 基于 outline-ss-server，编译为二进制并以 systemd 托管
# 用子命令区分操作：
#   sudo bash server.sh install [端口[:密码]]   # 安装并启动（默认随机端口 + 随机密码）
#   sudo bash server.sh uninstall [-y]          # 卸载（-y 跳过确认）
#   sudo bash server.sh config                  # 显示连接信息 / ss:// 分享链接
#   sudo bash server.sh status                  # 查看服务状态
#   sudo bash server.sh start|stop|restart
#   sudo bash server.sh logs                    # 实时日志
#   sudo bash server.sh help
# 可选环境变量 / 参数:
#   SS_METHOD（默认 chacha20-ietf-poly1305）  METRICS_PORT（默认 9091）
# curl|bash 用法:
#   curl -fsSL <url>/server.sh | sudo bash -s install 8388:mypass
#   curl -fsSL <url>/server.sh | sudo bash -s uninstall -y

set -euo pipefail

# ============ 颜色与打印 ============
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
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}"; }

# ============ 常量 ============
SS_DIR="/etc/shadowsocks"
SS_CONFIG="$SS_DIR/config.yml"
SS_ENV="$SS_DIR/ss.env"
SS_BIN="/usr/local/bin/outline-ss-server"
SERVICE_FILE="/etc/systemd/system/shadowsocks.service"
BUILD_DIR="/usr/local/src/outline-ss-server"
OUTLINE_VERSION="v1.7.3"
DEFAULT_METHOD="chacha20-ietf-poly1305"

print_help() {
    echo -e "${BLUE}Shadowsocks (Outline) 服务端管理工具${NC}"
    echo ""
    echo "用法: sudo bash server.sh <命令> [参数]"
    echo ""
    echo -e "${YELLOW}可用命令:${NC}"
    echo "  install [端口[:密码]]  安装并启动服务端（默认随机端口 + 随机密码）"
    echo "  uninstall [-y]         卸载（-y 跳过确认）"
    echo "  config                 显示连接信息 / ss:// 分享链接"
    echo "  status                 查看服务状态"
    echo "  start                  启动服务"
    echo "  stop                   停止服务"
    echo "  restart                重启服务"
    echo "  logs                   查看实时日志（systemd）"
    echo "  help                   显示此帮助信息"
    echo ""
    echo -e "${YELLOW}可选环境变量:${NC} SS_METHOD（默认 $DEFAULT_METHOD）  METRICS_PORT（默认 9091）"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此操作必须以 root 身份运行"
        echo "请使用: sudo bash server.sh $ACTION"
        exit 1
    fi
}

# 生成标准 ss:// 分享链接：ss://base64(method:password)@ip:port#tag
ss_link() {
    local method="$1" password="$2" ip="$3" port="$4"
    local userinfo
    userinfo=$(printf '%s:%s' "$method" "$password" | base64 -w0 2>/dev/null || printf '%s:%s' "$method" "$password" | base64)
    echo "ss://${userinfo}@${ip}:${port}#shadowsocks"
}

# ============ 安装相关函数 ============
install_deps() {
    print_info "安装系统依赖..."
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
    fi
    case "${ID:-}" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq git wget curl openssl
            ;;
        centos|rhel|amzn|amazon)
            yum install -y -q git wget curl openssl
            ;;
        *)
            print_info "未知系统 '${ID:-}'，跳过自动安装依赖，请确保 git/wget/curl/openssl 已安装"
            ;;
    esac
}

install_go() {
    if command -v go >/dev/null 2>&1; then
        print_success "Go 已安装: $(go version)"
        return 0
    fi
    print_info "安装 Go 1.23.4..."
    local go_tar="go1.23.4.linux-amd64.tar.gz"
    # 根据架构选择 Go 包
    case "$(uname -m)" in
        aarch64|arm64) go_tar="go1.23.4.linux-arm64.tar.gz" ;;
        x86_64|amd64)  go_tar="go1.23.4.linux-amd64.tar.gz" ;;
    esac
    cd /tmp
    wget -q "https://go.dev/dl/${go_tar}"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "${go_tar}"
    rm -f "${go_tar}"
    export PATH=$PATH:/usr/local/go/bin
    if ! grep -q "/usr/local/go/bin" /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi
    print_success "Go 安装完成: $(go version)"
}

build_binary() {
    print_info "编译 outline-ss-server ($OUTLINE_VERSION)..."
    export PATH=$PATH:/usr/local/go/bin
    mkdir -p "$(dirname "$BUILD_DIR")"
    if [[ ! -d "$BUILD_DIR" ]]; then
        git clone -b "$OUTLINE_VERSION" --depth=1 https://github.com/Jigsaw-Code/outline-ss-server.git "$BUILD_DIR"
    else
        print_info "源码目录已存在，跳过克隆"
    fi
    cd "$BUILD_DIR"
    go build -o "$SS_BIN" ./cmd/outline-ss-server
    chmod +x "$SS_BIN"
    print_success "二进制已编译: $SS_BIN"
}

do_install() {
    require_root

    # ---- 阶段1: 解析端口 / 密码 / 加密 ----
    print_step "1" "解析配置参数"
    local arg="${INSTALL_ARG:-}"
    local ss_port ss_password
    if [[ -n "$arg" ]]; then
        ss_port="${arg%%:*}"
        if [[ "$arg" == *:* ]]; then
            ss_password="${arg#*:}"
        fi
    fi
    [[ -z "${ss_port:-}" ]] && ss_port=$(( (RANDOM % 20000) + 20000 ))
    [[ -z "${ss_password:-}" ]] && ss_password=$(openssl rand -base64 16)
    local ss_method="${SS_METHOD:-$DEFAULT_METHOD}"
    local metrics_port="${METRICS_PORT:-9091}"

    if ! [[ "$ss_port" =~ ^[0-9]+$ ]] || [ "$ss_port" -lt 1 ] || [ "$ss_port" -gt 65535 ]; then
        print_error "无效的端口号: $ss_port (有效范围: 1-65535)"
        exit 1
    fi
    print_success "端口: ${YELLOW}$ss_port${NC}  加密: ${YELLOW}$ss_method${NC}"

    # ---- 阶段2: 依赖与编译 ----
    print_step "2" "安装依赖并编译二进制"
    install_deps
    install_go
    build_binary

    # ---- 阶段3: 生成配置 ----
    print_step "3" "生成配置文件"
    mkdir -p "$SS_DIR"
    cat > "$SS_CONFIG" <<EOF
services:
  - listeners:
      - type: tcp
        address: "[::]:${ss_port}"
      - type: udp
        address: "[::]:${ss_port}"
    keys:
        - id: user-0
          cipher: ${ss_method}
          secret: ${ss_password}
EOF
    print_success "配置文件已写入 $SS_CONFIG"

    # ---- 阶段4: 获取公网 IP ----
    print_step "4" "获取服务器IP地址"
    local server_ip
    server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
        || curl -s --max-time 5 https://icanhazip.com 2>/dev/null \
        || hostname -I | awk '{print $1}')
    server_ip=$(echo "$server_ip" | tr -d '[:space:]')
    if [ -z "$server_ip" ]; then
        server_ip="127.0.0.1"
        print_info "未检测到IP，使用localhost（请手动替换为实际IP）"
    else
        print_success "检测到服务器公网IP: ${YELLOW}$server_ip${NC}"
    fi

    print_info "保存连接参数到 $SS_ENV"
    cat > "$SS_ENV" <<EOF
SS_PORT=$ss_port
SS_PASSWORD=$ss_password
SS_METHOD=$ss_method
SERVER_IP=$server_ip
METRICS_PORT=$metrics_port
EOF
    chmod 600 "$SS_ENV"
    print_success "连接参数已保存"

    # ---- 阶段5: systemd 服务 ----
    print_step "5" "创建Systemd服务"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Shadowsocks (Outline) Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$SS_BIN -config $SS_CONFIG -metrics 0.0.0.0:${metrics_port} --replay_history=10000
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    print_success "服务文件创建完成"

    systemctl daemon-reload
    systemctl start shadowsocks
    sleep 2
    if systemctl is-active --quiet shadowsocks; then
        print_success "Shadowsocks 服务启动成功"
    else
        print_error "服务启动失败，请检查日志"
        journalctl -u shadowsocks -n 20
        exit 1
    fi
    systemctl enable shadowsocks >/dev/null 2>&1
    print_success "开机自启已启用"

    # ---- 阶段6: 防火墙 ----
    print_step "6" "防火墙配置"
    if systemctl is-active --quiet ufw; then
        print_info "UFW已启用，添加规则..."
        ufw allow "$ss_port"/tcp > /dev/null 2>&1
        ufw allow "$ss_port"/udp > /dev/null 2>&1
        print_success "防火墙规则已添加"
    else
        print_info "UFW未启用（跳过）"
    fi

    # ---- 阶段7: 显示连接信息 ----
    do_config
    print_success "所有安装步骤已完成！"
    echo ""
}

# ============ 卸载 ============
do_uninstall() {
    require_root

    # 幂等：完全没装过就直接返回
    if ! systemctl list-unit-files 2>/dev/null | grep -q '^shadowsocks\.service' \
       && [[ ! -f "$SERVICE_FILE" ]] \
       && [[ ! -d "$SS_DIR" ]] \
       && [[ ! -x "$SS_BIN" ]]; then
        print_info "未检测到 shadowsocks 安装痕迹，无需卸载"
        return 0
    fi

    local assume_yes=0
    if [[ "${UNINSTALL_FLAG:-}" == "-y" || "${UNINSTALL_FLAG:-}" == "--yes" ]]; then
        assume_yes=1
    fi

    echo ""
    echo -e "${YELLOW}即将卸载 Shadowsocks，并删除以下内容：${NC}"
    echo "  - systemd 服务: $SERVICE_FILE"
    echo "  - 二进制:       $SS_BIN"
    echo "  - 配置目录:     $SS_DIR"
    echo "  - 编译源码:     $BUILD_DIR"
    echo "  - 相关防火墙规则（如使用 UFW）"
    echo ""

    if [[ $assume_yes -ne 1 ]]; then
        read -r -p "确认卸载？(y/N) " answer
        case "$answer" in
            [yY]|[yY][eE][sS]) ;;
            *) print_info "已取消卸载"; exit 0 ;;
        esac
    fi

    # 读端口（清理防火墙用）
    print_step "1" "读取配置信息"
    local ss_port=""
    if [[ -f "$SS_ENV" ]]; then
        # shellcheck disable=SC1090
        source "$SS_ENV"
        ss_port="${SS_PORT:-}"
        [[ -n "$ss_port" ]] && print_success "检测到监听端口: ${YELLOW}$ss_port${NC}"
    else
        print_info "未找到 $SS_ENV，跳过端口读取"
    fi

    print_step "2" "停止并禁用服务"
    if systemctl list-unit-files 2>/dev/null | grep -q '^shadowsocks\.service'; then
        systemctl stop shadowsocks 2>/dev/null || true
        systemctl disable shadowsocks 2>/dev/null || true
        print_success "服务已停止并禁用"
    else
        print_info "未找到 shadowsocks 服务（跳过）"
    fi

    # 兜底：systemctl stop 失败时强制终止进程
    if pgrep -f "$SS_BIN" >/dev/null 2>&1; then
        print_info "检测到 outline-ss-server 进程残留，强制终止..."
        pkill -9 -f "$SS_BIN" 2>/dev/null || true
        sleep 1
    fi
    if pgrep -f "$SS_BIN" >/dev/null 2>&1; then
        print_error "outline-ss-server 进程仍在运行，请手动检查: ps -ef | grep outline-ss-server"
    else
        print_success "outline-ss-server 进程已确认退出"
    fi

    print_step "3" "删除 systemd 服务文件"
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        systemctl reset-failed 2>/dev/null || true
        print_success "服务文件已删除"
    else
        print_info "服务文件不存在（跳过）"
    fi

    print_step "4" "清理防火墙规则"
    if systemctl is-active --quiet ufw && [[ -n "$ss_port" ]]; then
        ufw delete allow "$ss_port"/tcp > /dev/null 2>&1 || true
        ufw delete allow "$ss_port"/udp > /dev/null 2>&1 || true
        print_success "已删除端口 $ss_port 的防火墙规则"
    else
        print_info "UFW 未启用或端口未知（跳过）"
    fi

    print_step "5" "删除二进制、配置和源码"
    rm -f "$SS_BIN"
    rm -rf "$SS_DIR" "$BUILD_DIR"
    print_success "已删除二进制、配置和源码目录"

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    print_success "Shadowsocks 已完整卸载"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    print_info "提示：安装时装的依赖 (git wget curl openssl Go) 为系统常用工具，未自动删除"
    echo ""
}

# ============ 显示连接信息 ============
do_config() {
    if [ ! -f "$SS_ENV" ]; then
        print_error "未检测到配置: $SS_ENV"
        echo "请先运行: sudo bash server.sh install"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$SS_ENV"

    if [ -z "${SS_PORT:-}" ] || [ -z "${SS_PASSWORD:-}" ] || [ -z "${SS_METHOD:-}" ] || [ -z "${SERVER_IP:-}" ]; then
        print_error "配置不完整，请重新运行安装"
        return 1
    fi

    local link
    link=$(ss_link "$SS_METHOD" "$SS_PASSWORD" "$SERVER_IP" "$SS_PORT")

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Shadowsocks 服务器连接信息${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BLUE}地址:${NC} $SERVER_IP"
    echo -e "  ${BLUE}端口:${NC} $SS_PORT"
    echo -e "  ${BLUE}密码:${NC} $SS_PASSWORD"
    echo -e "  ${BLUE}加密:${NC} $SS_METHOD"
    echo ""
    echo -e "${YELLOW}ss:// 分享链接:${NC}"
    echo ""
    echo "$link"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============ 服务控制 / 日志 ============
show_status() {
    require_root
    systemctl status shadowsocks
}
start_service() {
    require_root
    print_info "正在启动 Shadowsocks 服务..."
    systemctl start shadowsocks
    sleep 2
    systemctl is-active --quiet shadowsocks && print_success "服务启动成功" || { print_error "服务启动失败"; return 1; }
}
stop_service() {
    require_root
    print_info "正在停止 Shadowsocks 服务..."
    systemctl stop shadowsocks
    sleep 1
    print_success "服务已停止"
}
restart_service() {
    require_root
    print_info "正在重启 Shadowsocks 服务..."
    systemctl restart shadowsocks
    sleep 2
    systemctl is-active --quiet shadowsocks && print_success "服务重启成功" || { print_error "服务重启失败"; return 1; }
}
show_logs() {
    require_root
    journalctl -u shadowsocks -f
}

# ===== 入口：子命令分发 =====
ACTION="${1:-help}"

case "$ACTION" in
    install)
        INSTALL_ARG="${2:-}"
        do_install
        ;;
    uninstall)
        UNINSTALL_FLAG="${2:-}"
        do_uninstall
        ;;
    config|info) do_config ;;
    status)      show_status ;;
    start)       start_service ;;
    stop)        stop_service ;;
    restart)     restart_service ;;
    logs)        show_logs ;;
    help|-h|--help) print_help ;;
    *)
        print_error "未知命令: $ACTION"
        echo ""
        print_help
        exit 1
        ;;
esac
