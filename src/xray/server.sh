#!/bin/bash

# Xray VLESS 服务端管理脚本（REALITY 协议，无需证书）
# 用子命令区分操作：
#   sudo bash server.sh install [端口]    # 安装并启动（默认端口 443，也可用 XRAY_PORT 环境变量）
#   sudo bash server.sh uninstall [-y]    # 卸载（-y 跳过确认）
#   sudo bash server.sh config            # 显示连接信息 / VLESS 分享链接
#   sudo bash server.sh status            # 查看服务状态
#   sudo bash server.sh start|stop|restart
#   sudo bash server.sh logs              # 实时日志
#   sudo bash server.sh error|access      # 错误 / 访问日志
#   sudo bash server.sh test              # 测试配置文件
#   sudo bash server.sh reload            # 校验并重载配置
#   sudo bash server.sh stats             # 流量 / 连接统计
#   sudo bash server.sh help
# curl|bash 用法:
#   curl -fsSL <url>/server.sh | sudo bash -s install 8443
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
XRAY_DIR="/usr/local/Xray"
XRAY_BIN="$XRAY_DIR/xray"
XRAY_CONFIG_DIR="/etc/xray"
XRAY_CONFIG="$XRAY_CONFIG_DIR/config.json"
REALITY_ENV="$XRAY_CONFIG_DIR/reality.env"
# 可选：预置固定参数(UUID/密钥/shortId/SNI/端口)的本地文件，安装时自动加载。
# 命令行/环境变量优先级更高，不会被此文件覆盖。
SERVER_ENV="/etc/xray-server.env"
XRAY_LOG_DIR="/var/log/xray"
XRAY_LOG_ERROR="$XRAY_LOG_DIR/error.log"
XRAY_LOG_ACCESS="$XRAY_LOG_DIR/access.log"
SERVICE_FILE="/etc/systemd/system/xray.service"

# ============ 通用辅助 ============
require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此操作必须以 root 身份运行"
        echo "请使用: sudo bash server.sh $ACTION"
        exit 1
    fi
}

print_help() {
    echo -e "${BLUE}Xray VLESS 服务端管理工具${NC}"
    echo ""
    echo "用法: sudo bash server.sh <命令> [参数]"
    echo ""
    echo -e "${YELLOW}可用命令:${NC}"
    echo "  install [端口]   安装并启动服务端（默认端口 443）"
    echo "  uninstall [-y]   卸载（-y 跳过确认）"
    echo "  config           显示连接信息 / VLESS 分享链接"
    echo "  status           查看服务状态"
    echo "  start            启动服务"
    echo "  stop             停止服务"
    echo "  restart          重启服务"
    echo "  logs             查看实时日志（systemd）"
    echo "  error            查看错误日志"
    echo "  access           查看访问日志"
    echo "  test             测试配置文件"
    echo "  reload           校验并重载配置"
    echo "  stats            显示流量 / 连接统计"
    echo "  help             显示此帮助信息"
    echo ""
}

# ============ 安装相关函数 ============
check_network() {
    print_info "检查网络连接..."
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        print_info "无法连接到 8.8.8.8，尝试其他 DNS..."
        if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
            print_error "网络连接失败，请检查网络设置"
            return 1
        fi
    fi
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

setup_proxy() {
    if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
        print_info "检测到代理设置"
        print_info "HTTP_PROXY: ${HTTP_PROXY:-未设置}"
        print_info "HTTPS_PROXY: ${HTTPS_PROXY:-未设置}"
    fi
}

do_install() {
    require_root

    # 加载本地预置参数(若存在)。已在环境中设置的变量优先，不被文件覆盖。
    if [[ -f "$SERVER_ENV" ]]; then
        print_info "加载预置参数: $SERVER_ENV"
        local __k __v
        while IFS='=' read -r __k __v; do
            [[ "$__k" =~ ^[[:space:]]*# || -z "$__k" ]] && continue
            __k="$(echo -n "$__k" | tr -d '[:space:]')"
            # 去掉值两端引号/空白
            __v="$(echo -n "$__v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")"
            # 仅当该变量当前为空时才采用文件值（命令行环境变量优先）
            [[ -z "${!__k:-}" ]] && export "$__k=$__v"
        done < "$SERVER_ENV"
    fi

    # ---- 阶段0: 网络环境检查 ----
    print_step "0" "网络环境检查"
    setup_proxy
    check_network

    # ---- 阶段1: 系统准备 ----
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

    # ---- 阶段2: 安装 Xray 核心 ----
    print_step "2" "安装Xray核心"
    print_info "检查Xray安装目录..."
    mkdir -p "$XRAY_DIR" "$XRAY_CONFIG_DIR" "$XRAY_LOG_DIR"

    print_info "下载Xray核心（ARM64版本）..."
    cd /tmp
    local xray_version xray_url
    xray_version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
    print_info "最新版本: ${xray_version}"
    xray_url="https://github.com/XTLS/Xray-core/releases/download/${xray_version}/Xray-linux-arm64-v8a.zip"

    if wget -v "$xray_url" -O xray.zip 2>&1; then
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
    mv xray "$XRAY_DIR/"
    chmod +x "$XRAY_BIN"
    print_success "Xray核心安装完成"

    # ---- 阶段3: 配置端口 ----
    print_step "3" "配置Xray端口"
    local xray_port="${XRAY_PORT:-${INSTALL_PORT:-443}}"
    if ! [[ "$xray_port" =~ ^[0-9]+$ ]] || [ "$xray_port" -lt 1 ] || [ "$xray_port" -gt 65535 ]; then
        print_error "无效的端口号: $xray_port (有效范围: 1-65535)"
        exit 1
    fi
    print_success "使用端口: ${YELLOW}$xray_port${NC}"

    # ---- 阶段4: 生成 UUID ----
    print_step "4" "生成UUID"
    local xray_uuid
    if [[ -n "${XRAY_UUID:-}" ]]; then
        xray_uuid="$XRAY_UUID"
        print_success "使用指定UUID: ${YELLOW}$xray_uuid${NC}"
    else
        xray_uuid=$(uuidgen)
        print_success "生成的随机UUID: ${YELLOW}$xray_uuid${NC}"
    fi

    # ---- 阶段5: 获取服务器IP ----
    print_step "5" "获取服务器IP地址"
    print_info "检测服务器公网IP地址..."
    local server_ip
    server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
        || curl -s --max-time 5 https://icanhazip.com 2>/dev/null \
        || hostname -I | awk '{print $1}')
    server_ip=$(echo "$server_ip" | tr -d '[:space:]')
    if [ -z "$server_ip" ]; then
        server_ip="127.0.0.1"
        print_info "未检测到IP，使用localhost（请手动修改为实际IP）"
    else
        print_success "检测到服务器公网IP: ${YELLOW}$server_ip${NC}"
    fi

    # ---- 阶段6: 生成 REALITY 密钥 ----
    print_step "6" "生成 REALITY 密钥"
    # 伪装目标(dest/SNI)：默认 www.yahoo.com。
    # 注意 www.microsoft.com 的 TLS 握手与 REALITY 借壳转发不兼容，
    # 会导致客户端 "handshake did not complete"，切勿用作默认。
    # 可用 REALITY_SNI（或旧名 REALITY_DEST）环境变量覆盖(只写域名，端口固定 443)。
    local reality_domain="${REALITY_SNI:-${REALITY_DEST:-www.yahoo.com}}"
    reality_domain="${reality_domain%:*}"   # 容错：去掉误带的 :443
    local reality_dest="${reality_domain}:443"
    local reality_server_name="$reality_domain"
    print_success "伪装目标(SNI): ${YELLOW}$reality_server_name${NC}"

    local reality_private_key reality_public_key
    if [[ -n "${REALITY_PRIVATE_KEY:-}" && -n "${REALITY_PUBLIC_KEY:-}" ]]; then
        reality_private_key="$REALITY_PRIVATE_KEY"
        reality_public_key="$REALITY_PUBLIC_KEY"
        print_success "使用指定 x25519 密钥对"
    elif [[ -n "${REALITY_PRIVATE_KEY:-}" ]]; then
        # 只给了私钥：用 xray 反推公钥
        reality_private_key="$REALITY_PRIVATE_KEY"
        reality_public_key=$("$XRAY_BIN" x25519 -i "$REALITY_PRIVATE_KEY" 2>/dev/null \
            | grep -iE 'public[ ]?key|password' | awk -F: '{print $2}' | tr -d '[:space:]')
        if [[ -z "$reality_public_key" ]]; then
            print_error "REALITY_PRIVATE_KEY 无法反推公钥，请同时提供 REALITY_PUBLIC_KEY"
            exit 1
        fi
        print_success "使用指定私钥，已反推公钥"
    else
        print_info "生成 x25519 密钥对..."
        local x25519_output
        x25519_output=$("$XRAY_BIN" x25519)
        # 兼容新旧版本字段名：旧版 "Private key:" / "Public key:"，新版 "PrivateKey:" / "Password:"
        reality_private_key=$(echo "$x25519_output" | grep -iE 'private[ ]?key' | awk -F: '{print $2}' | tr -d '[:space:]')
        reality_public_key=$(echo "$x25519_output" | grep -iE 'public[ ]?key|password' | awk -F: '{print $2}' | tr -d '[:space:]')
        if [ -z "$reality_private_key" ] || [ -z "$reality_public_key" ]; then
            print_error "REALITY 密钥生成失败，无法解析 xray x25519 输出"
            echo "$x25519_output"
            exit 1
        fi
        print_success "x25519 密钥对生成完成"
    fi

    local reality_short_id
    if [[ -n "${REALITY_SHORT_ID:-}" ]]; then
        reality_short_id="$REALITY_SHORT_ID"
        print_success "使用指定 shortId: ${YELLOW}$reality_short_id${NC}"
    else
        reality_short_id=$(openssl rand -hex 8)
        print_success "生成随机 shortId: ${YELLOW}$reality_short_id${NC}"
    fi

    # ---- 阶段7: 创建配置文件 ----
    print_step "7" "创建Xray配置文件"
    print_info "生成配置文件: $XRAY_CONFIG"
    cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$XRAY_LOG_ACCESS",
    "error": "$XRAY_LOG_ERROR"
  },
  "inbounds": [
    {
      "port": $xray_port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$xray_uuid",
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
          "dest": "$reality_dest",
          "xver": 0,
          "serverNames": ["$reality_server_name"],
          "privateKey": "$reality_private_key",
          "shortIds": ["$reality_short_id"]
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

    print_info "保存 REALITY 参数到 $REALITY_ENV"
    cat > "$REALITY_ENV" <<EOF
XRAY_PORT=$xray_port
XRAY_UUID=$xray_uuid
PUBLIC_KEY=$reality_public_key
SHORT_ID=$reality_short_id
SERVER_NAME=$reality_server_name
SERVER_IP=$server_ip
EOF
    chmod 600 "$REALITY_ENV"
    print_success "REALITY 参数已保存"

    # ---- 阶段8: 验证配置 ----
    print_step "8" "验证配置文件"
    print_info "检查配置文件语法..."
    if "$XRAY_BIN" -c "$XRAY_CONFIG" -test; then
        print_success "配置文件验证通过"
    else
        print_error "配置文件验证失败"
        exit 1
    fi

    # ---- 阶段9: 创建 systemd 服务 ----
    print_step "9" "创建Systemd服务"
    print_info "创建服务文件: $SERVICE_FILE"
    cat > "$SERVICE_FILE" <<'EOF'
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

    # ---- 阶段10: 启动服务 ----
    print_step "10" "启动Xray服务"
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

    # ---- 阶段11: 防火墙 ----
    print_step "11" "防火墙配置"
    print_info "检查ufw防火墙状态..."
    if systemctl is-active --quiet ufw; then
        print_info "UFW已启用，添加规则..."
        ufw allow "$xray_port"/tcp > /dev/null 2>&1
        ufw allow "$xray_port"/udp > /dev/null 2>&1
        print_success "防火墙规则已添加"
    else
        print_info "UFW未启用（跳过）"
    fi

    # ---- 阶段12: 显示连接信息 ----
    do_config
    print_success "所有安装步骤已完成！"
    echo ""
}

# ============ 卸载 ============
do_uninstall() {
    require_root

    # 幂等：完全没装过就直接返回
    if ! systemctl list-unit-files 2>/dev/null | grep -q '^xray\.service' \
       && [[ ! -f "$SERVICE_FILE" ]] \
       && [[ ! -d "$XRAY_DIR" ]] \
       && [[ ! -d "$XRAY_CONFIG_DIR" ]]; then
        print_info "未检测到 xray 安装痕迹，无需卸载"
        return 0
    fi

    local assume_yes=0
    if [[ "${UNINSTALL_FLAG:-}" == "-y" || "${UNINSTALL_FLAG:-}" == "--yes" ]]; then
        assume_yes=1
    fi

    echo ""
    echo -e "${YELLOW}即将卸载 Xray，并删除以下内容：${NC}"
    echo "  - systemd 服务: $SERVICE_FILE"
    echo "  - 程序目录:     $XRAY_DIR"
    echo "  - 配置目录:     $XRAY_CONFIG_DIR"
    echo "  - 日志目录:     $XRAY_LOG_DIR"
    echo "  - 相关防火墙规则（如使用 UFW）"
    echo ""

    if [[ $assume_yes -ne 1 ]]; then
        read -r -p "确认卸载？(y/N) " answer
        case "$answer" in
            [yY]|[yY][eE][sS]) ;;
            *) print_info "已取消卸载"; exit 0 ;;
        esac
    fi

    # 读端口（清理防火墙用，须在删配置前）
    print_step "1" "读取配置信息"
    local xray_port=""
    if [[ -f "$XRAY_CONFIG" ]]; then
        xray_port=$(grep -oP '"port":\s*\K\d+' "$XRAY_CONFIG" | head -1 || true)
        if [[ -n "$xray_port" ]]; then
            print_success "检测到监听端口: ${YELLOW}$xray_port${NC}"
        else
            print_info "未能从配置文件读取端口"
        fi
    else
        print_info "配置文件不存在，跳过端口读取"
    fi

    print_step "2" "停止并禁用服务"
    if systemctl list-unit-files 2>/dev/null | grep -q '^xray\.service'; then
        systemctl stop xray 2>/dev/null || true
        systemctl disable xray 2>/dev/null || true
        print_success "服务已停止并禁用"
    else
        print_info "未找到 xray 服务（跳过）"
    fi

    # 兜底：systemctl stop 在某些环境（service 文件被改坏 / daemon 卡死）会失败
    # 残留 xray 进程会导致端口继续监听。强制 pkill 兜底并校验端口已释放。
    if pgrep -f "$XRAY_BIN" >/dev/null 2>&1; then
        print_info "检测到 xray 进程残留，强制终止..."
        pkill -9 -f "$XRAY_BIN" 2>/dev/null || true
        sleep 1
    fi
    if pgrep -f "$XRAY_BIN" >/dev/null 2>&1; then
        print_error "xray 进程仍在运行，请手动检查: ps -ef | grep xray"
    else
        print_success "xray 进程已确认退出"
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
    if systemctl is-active --quiet ufw && [[ -n "$xray_port" ]]; then
        ufw delete allow "$xray_port"/tcp > /dev/null 2>&1 || true
        ufw delete allow "$xray_port"/udp > /dev/null 2>&1 || true
        print_success "已删除端口 $xray_port 的防火墙规则"
    else
        print_info "UFW 未启用或端口未知（跳过）"
    fi

    print_step "5" "删除程序、配置和日志"
    rm -rf "$XRAY_DIR" "$XRAY_CONFIG_DIR" "$XRAY_LOG_DIR"
    print_success "已删除程序、配置和日志目录"

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    print_success "Xray 已完整卸载"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    print_info "提示：安装时装的依赖 (curl wget unzip uuid-runtime openssl) 为系统常用工具，未自动删除"
    echo ""
}

# ============ 显示连接信息 ============
do_config() {
    if [ ! -f "$REALITY_ENV" ]; then
        print_error "未检测到 REALITY 配置: $REALITY_ENV"
        echo "请先运行: sudo bash server.sh install"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$REALITY_ENV"

    if [ -z "${XRAY_PORT:-}" ] || [ -z "${XRAY_UUID:-}" ] || [ -z "${PUBLIC_KEY:-}" ] \
       || [ -z "${SHORT_ID:-}" ] || [ -z "${SERVER_NAME:-}" ] || [ -z "${SERVER_IP:-}" ]; then
        print_error "REALITY 配置不完整，请重新运行安装"
        return 1
    fi

    local link="vless://$XRAY_UUID@$SERVER_IP:$XRAY_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&sid=$SHORT_ID&sni=$SERVER_NAME&fp=chrome&flow=xtls-rprx-vision&type=tcp#xray-reality"

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
    echo "$link"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============ 服务控制 / 日志 ============
show_status() {
    require_root
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}服务状态${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    systemctl status xray
}

start_service() {
    require_root
    print_info "正在启动Xray服务..."
    systemctl start xray
    sleep 2
    if systemctl is-active --quiet xray; then
        print_success "服务启动成功"
    else
        print_error "服务启动失败"
        return 1
    fi
}

stop_service() {
    require_root
    print_info "正在停止Xray服务..."
    systemctl stop xray
    sleep 1
    print_success "服务已停止"
}

restart_service() {
    require_root
    print_info "正在重启Xray服务..."
    systemctl restart xray
    sleep 2
    if systemctl is-active --quiet xray; then
        print_success "服务重启成功"
    else
        print_error "服务重启失败"
        return 1
    fi
}

show_logs() {
    require_root
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}实时日志（按 Ctrl+C 退出）${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    journalctl -u xray -f
}

show_error_log() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}错误日志${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    if [ -f "$XRAY_LOG_ERROR" ]; then
        tail -n 50 "$XRAY_LOG_ERROR"
    else
        print_error "错误日志文件不存在"
    fi
}

show_access_log() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}访问日志${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    if [ -f "$XRAY_LOG_ACCESS" ]; then
        tail -n 50 "$XRAY_LOG_ACCESS"
    else
        print_error "访问日志文件不存在"
    fi
}

test_config() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}测试配置文件${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    if "$XRAY_BIN" -c "$XRAY_CONFIG" -test; then
        print_success "配置文件有效"
    else
        print_error "配置文件有错误"
        return 1
    fi
}

reload_service() {
    require_root
    print_info "正在重新加载配置..."
    if "$XRAY_BIN" -c "$XRAY_CONFIG" -test > /dev/null 2>&1; then
        systemctl restart xray
        sleep 2
        print_success "配置已重新加载"
    else
        print_error "配置文件有错误，未重新加载"
        return 1
    fi
}

show_stats() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}流量统计${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}内存使用:${NC}"
    ps aux | grep xray | grep -v grep | awk '{print $6 " KB"}'
    echo ""
    echo -e "${YELLOW}最近连接:${NC}"
    if [ -f "$XRAY_LOG_ACCESS" ]; then
        tail -n 5 "$XRAY_LOG_ACCESS"
    fi
}

# ===== 入口：子命令分发 =====
ACTION="${1:-help}"

case "$ACTION" in
    install)
        # 端口作为第二个参数；也兼容 XRAY_PORT 环境变量
        INSTALL_PORT="${2:-}"
        do_install
        ;;
    uninstall)
        UNINSTALL_FLAG="${2:-}"
        do_uninstall
        ;;
    config|info)
        do_config
        ;;
    status)   show_status ;;
    start)    start_service ;;
    stop)     stop_service ;;
    restart)  restart_service ;;
    logs)     show_logs ;;
    error)    show_error_log ;;
    access)   show_access_log ;;
    test)     test_config ;;
    reload)   reload_service ;;
    stats)    show_stats ;;
    help|-h|--help) print_help ;;
    *)
        print_error "未知命令: $ACTION"
        echo ""
        print_help
        exit 1
        ;;
esac
