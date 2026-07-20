#!/bin/bash

# WireGuard 分流管理脚本（Surfshark 出口）
# 让 xray 转发的流量走 WireGuard → Surfshark，SSH 和 xray 入站不受影响
#
# 用子命令区分操作：
#   sudo bash wg.sh install <wg.conf>   # 安装 WireGuard 并配置分流
#   sudo bash wg.sh enable              # 启动 WireGuard 分流
#   sudo bash wg.sh disable             # 停止 WireGuard 分流（回滚到直连）
#   sudo bash wg.sh status              # 查看分流状态
#   sudo bash wg.sh uninstall [-y]      # 卸载（-y 跳过确认）
#   sudo bash wg.sh help
# curl|bash 用法:
#   curl -fsSL <url>/wg.sh | sudo bash -s install /path/to/wg0.conf
#   curl -fsSL <url>/wg.sh | sudo bash -s enable
#   curl -fsSL <url>/wg.sh | sudo bash -s disable
#   curl -fsSL <url>/wg.sh | sudo bash -s uninstall -y

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
WG_CONF="/etc/wireguard/wg0.conf"
WG_IFACE="wg0"
RT_TABLE_NAME="surfshark"
RT_TABLE_ID="100"
FWMARK="0x1"
XRAY_USER="xrayuser"
SERVICE_FILE="/etc/systemd/system/wg-split.service"
IPRULES_FILE="/etc/wireguard/iprules.sh"

# ============ 通用辅助 ============
require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此操作必须以 root 身份运行"
        echo "请使用: sudo bash wg.sh $ACTION"
        exit 1
    fi
}

print_help() {
    echo -e "${BLUE}WireGuard 分流管理工具${NC}"
    echo ""
    echo "用法: sudo bash wg.sh <命令> [参数]"
    echo ""
    echo -e "${YELLOW}可用命令:${NC}"
    echo "  install <conf>    安装 WireGuard 并配置分流（conf 为 Surfshark 配置文件路径）"
    echo "  enable            启动 WireGuard 分流"
    echo "  disable           停止 WireGuard 分流（回滚到直连）"
    echo "  status            查看分流状态"
    echo "  uninstall [-y]    卸载（-y 跳过确认）"
    echo "  help              显示此帮助信息"
    echo ""
}

# ============ 安装 ============
do_install() {
    require_root

    local conf_file="${1:-}"
    if [[ -z "$conf_file" ]]; then
        print_error "请提供 Surfshark WireGuard 配置文件路径"
        echo "用法: sudo bash wg.sh install /path/to/wg0.conf"
        exit 1
    fi
    if [[ ! -f "$conf_file" ]]; then
        print_error "配置文件不存在: $conf_file"
        exit 1
    fi

    # ---- 阶段0: 检查 xrayuser ----
    print_step "0" "检查前置条件"
    if ! id -u "$XRAY_USER" >/dev/null 2>&1; then
        print_error "用户 $XRAY_USER 不存在，请先安装 xray server.sh"
        exit 1
    fi
    if ! systemctl is-active --quiet xray; then
        print_error "xray 服务未运行，请先启动: systemctl start xray"
        exit 1
    fi
    print_success "前置条件检查通过"

    # ---- 阶段1: 安装 WireGuard ----
    print_step "1" "安装 WireGuard"
    apt-get update -qq
    apt-get install -y wireguard wireguard-tools iptables
    print_success "WireGuard 安装完成"

    # ---- 阶段2: 处理配置文件 ----
    print_step "2" "配置 WireGuard"

    # 读取原始配置，提取必要字段
    local privkey address dns peer_pubkey endpoint allowedips
    # 取 '=' 之后的完整值并去掉首尾空白，避免只截首个字段（DNS 有多个 IP 时会漏且留逗号）
    _wg_val() { grep -i "^[[:space:]]*$1[[:space:]]*=" "$conf_file" | head -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]+$//'; }
    privkey=$(_wg_val 'PrivateKey')
    address=$(_wg_val 'Address')
    dns=$(_wg_val 'DNS')
    peer_pubkey=$(_wg_val 'PublicKey')
    endpoint=$(_wg_val 'Endpoint')
    allowedips=$(_wg_val 'AllowedIPs')

    if [[ -z "$privkey" || -z "$address" || -z "$peer_pubkey" || -z "$endpoint" ]]; then
        print_error "配置文件缺少必要字段 (PrivateKey/Address/PublicKey/Endpoint)"
        exit 1
    fi

    # x25519 密钥应为 44 字符 base64（末尾 '='）。格式不对通常意味着 conf 被改坏，
    # 会导致握手失败但服务端静默丢包（rx=0），极难排查——提前拦截。
    local _keyre='^[A-Za-z0-9+/]{43}=$'
    if [[ ! "$privkey" =~ $_keyre ]]; then
        print_error "PrivateKey 格式非法（应为 44 字符 base64 x25519 私钥），请核对 Surfshark 原始配置"
        exit 1
    fi
    if [[ ! "$peer_pubkey" =~ $_keyre ]]; then
        print_error "PublicKey 格式非法（应为 44 字符 base64 x25519 公钥），请核对 Surfshark 原始配置"
        exit 1
    fi

    print_info "Endpoint: $endpoint"
    print_info "Address: $address"
    print_info "本机公钥(pubkey): $(echo "$privkey" | wg pubkey 2>/dev/null || echo '解析失败')"

    mkdir -p /etc/wireguard

    # 写入配置，强制 Table=off 防止 SSH 断开
    cat > "$WG_CONF" <<EOF
[Interface]
PrivateKey = $privkey
Address = $address
MTU = 1280
Table = off
${dns:+DNS = $dns}

[Peer]
PublicKey = $peer_pubkey
AllowedIPs = 0.0.0.0/0
Endpoint = $endpoint
PersistentKeepalive = 25
EOF
    chmod 600 "$WG_CONF"
    print_success "WireGuard 配置写入完成: $WG_CONF"

    # ---- 阶段3: 配置策略路由和 iptables ----
    print_step "3" "配置策略路由和 iptables"

    # 路由表
    if ! grep -q "$RT_TABLE_ID.*$RT_TABLE_NAME" /etc/iproute2/rt_tables 2>/dev/null; then
        echo "$RT_TABLE_ID $RT_TABLE_NAME" >> /etc/iproute2/rt_tables
        print_success "添加路由表: $RT_TABLE_ID $RT_TABLE_NAME"
    fi

    # 写入 iprules 脚本（enable/disable 共用）
    cat > "$IPRULES_FILE" <<'EOF'
#!/bin/bash
set -euo pipefail

WG_IFACE="wg0"
RT_TABLE_NAME="surfshark"
RT_TABLE_ID="100"
FWMARK="0x1"
XRAY_USER="xrayuser"

case "${1:-}" in
enable)
    # 路由表默认路由走 wg0
    ip route add default dev "$WG_IFACE" table "$RT_TABLE_NAME" 2>/dev/null || true
    # fwmark 规则：只有带标记的包才查 surfshark 表；未标记的包（含 SSH/root）
    # 自然落到后面的 main 表走 eth0，无需额外 uidrange 规则。
    ip rule add fwmark "$FWMARK" table "$RT_TABLE_NAME" 2>/dev/null || true
    # 标记 xrayuser 发起的新连接走 wg0
    # 只标记 NEW 连接，已建立连接（如 SSH）不受影响
    iptables -t mangle -A OUTPUT -m owner --uid-owner "$XRAY_USER" -m conntrack --ctstate NEW -j MARK --set-mark "$FWMARK"
    # MSS 钳制：wg0 MTU=1280，TLS 大包（ClientHello）会超 PMTU 被静默丢弃，
    # 表现为 HTTP 通、HTTPS 卡死。钳到 1240 (=1280-40) 修复。
    iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -m owner --uid-owner "$XRAY_USER" -j TCPMSS --set-mss 1240
    # wg0 出口做 SNAT（只对 xrayuser 的包）
    iptables -t nat -A POSTROUTING -o "$WG_IFACE" -m owner --uid-owner "$XRAY_USER" -j MASQUERADE
    # 确保 ip_forward 开启
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    ;;
disable)
    # 删除 iptables 规则
    iptables -t mangle -D OUTPUT -m owner --uid-owner "$XRAY_USER" -m conntrack --ctstate NEW -j MARK --set-mark "$FWMARK" 2>/dev/null || true
    iptables -t mangle -D OUTPUT -p tcp --tcp-flags SYN,RST SYN -m owner --uid-owner "$XRAY_USER" -j TCPMSS --set-mss 1240 2>/dev/null || true
    iptables -t nat -D POSTROUTING -o "$WG_IFACE" -m owner --uid-owner "$XRAY_USER" -j MASQUERADE 2>/dev/null || true
    # 删除路由规则
    ip rule del fwmark "$FWMARK" table "$RT_TABLE_NAME" 2>/dev/null || true
    ip route flush table "$RT_TABLE_NAME" 2>/dev/null || true
    ;;
esac
EOF
    chmod +x "$IPRULES_FILE"
    print_success "策略路由脚本写入完成: $IPRULES_FILE"

    # ---- 阶段4: 创建 systemd 服务 ----
    print_step "4" "创建 systemd 服务"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=WireGuard Split Tunnel (Surfshark)
After=network-online.target xray.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/wg-quick up $WG_IFACE
ExecStart=$IPRULES_FILE enable
ExecStop=$IPRULES_FILE disable
ExecStopPost=/usr/bin/wg-quick down $WG_IFACE

[Install]
WantedBy=multi-user.target
EOF
    print_success "服务文件创建完成: $SERVICE_FILE"

    # ---- 阶段5: 准备启动 ----
    print_step "5" "配置完成"
    systemctl daemon-reload
    systemctl enable wg-split.service
    print_success "服务已配置，未自动启动（避免安装过程中断 SSH）"
    print_info "手动启动: sudo bash wg.sh enable"
    print_info "手动停止: sudo bash wg.sh disable"

    # ---- 阶段6: 验证配置 ----
    print_step "6" "验证配置"
    if wg-quick strip "$WG_IFACE" >/dev/null 2>&1; then
        print_success "WireGuard 配置验证通过"
    else
        print_error "WireGuard 配置验证失败"
        exit 1
    fi
    if systemctl is-enabled --quiet wg-split.service; then
        print_success "wg-split 服务已启用（开机自启）"
    fi

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}WireGuard 分流安装完成${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo "  配置文件: $WG_CONF"
    echo "  路由表:   $RT_TABLE_ID $RT_TABLE_NAME"
    echo "  服务:     $SERVICE_FILE"
    echo ""
    echo "  启动分流: sudo bash wg.sh enable"
    echo "  停止分流: sudo bash wg.sh disable"
    echo "  查看状态: sudo bash wg.sh status"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============ 启用 ============
do_enable() {
    require_root
    if [[ ! -f "$WG_CONF" ]]; then
        print_error "WireGuard 未安装，请先运行: sudo bash wg.sh install <conf>"
        exit 1
    fi
    systemctl start wg-split.service
    sleep 2
    if systemctl is-active --quiet wg-split.service; then
        print_success "WireGuard 分流已启动"
        wg show
        # 握手自检：私钥错/endpoint 被墙时服务仍显示 active，但握手永不完成、
        # 流量全黑洞（rx=0）。主动等一次握手，失败则明确报错，避免沉默失败。
        print_info "等待 WireGuard 握手（最多 15s）..."
        local rx="" latest=""
        for _ in $(seq 1 15); do
            latest=$(wg show "$WG_IFACE" latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)
            rx=$(wg show "$WG_IFACE" transfer 2>/dev/null | awk '{print $2}' | head -1)
            if [[ -n "$latest" && "$latest" != "0" && "${rx:-0}" -gt 0 ]]; then
                print_success "握手成功，隧道已通（rx=${rx}B）"
                # 出口 IP 自检（走 wg0）
                local wg_ip
                wg_ip=$(timeout 8 curl -s --interface "$WG_IFACE" https://api.ipify.org 2>/dev/null || echo "")
                [[ -n "$wg_ip" ]] && print_info "WG 出口 IP: $wg_ip"
                return 0
            fi
            sleep 1
        done
        print_error "握手未完成（rx=${rx:-0}B）：隧道不通"
        echo "  常见原因：① PrivateKey 与 Surfshark 账户不匹配（服务端静默丢包）"
        echo "           ② Endpoint 被墙 / UDP 51820 不通"
        echo "  排查：wg show $WG_IFACE  以及  echo <私钥> | wg pubkey  与账户注册公钥核对"
        exit 1
    else
        print_error "启动失败"
        journalctl -u wg-split -n 20
        exit 1
    fi
}

# ============ 停用 ============
do_disable() {
    require_root
    systemctl stop wg-split.service
    sleep 1
    print_success "WireGuard 分流已停止，xray 回到直连模式"
}

# ============ 状态 ============
do_status() {
    require_root
    echo "=== WireGuard 分流状态 ==="
    if systemctl is-active --quiet wg-split.service; then
        echo "  服务状态: 运行中"
    else
        echo "  服务状态: 已停止"
    fi

    if ip link show "$WG_IFACE" >/dev/null 2>&1; then
        echo "  $WG_IFACE: 存在"
        wg show 2>/dev/null || true
        local wg_ip
        wg_ip=$(curl -s --max-time 5 --interface "$WG_IFACE" http://ip.sb 2>/dev/null || echo "获取失败")
        echo "  WG 出口 IP: $wg_ip"
    else
        echo "  $WG_IFACE: 不存在"
    fi

    local direct_ip
    direct_ip=$(curl -s --max-time 5 http://ip.sb 2>/dev/null || echo "获取失败")
    echo "  直连出口 IP: $direct_ip"

    echo ""
    echo "=== iptables mangle 规则 ==="
    iptables -t mangle -L OUTPUT -n 2>/dev/null | grep -i "xray\|MARK\|CONNMARK" || echo "  (无分流规则)"
}

# ============ 卸载 ============
do_uninstall() {
    require_root
    local force="${1:-}"

    echo ""
    if [[ "$force" != "-y" ]]; then
        echo -e "${YELLOW}即将卸载 WireGuard 分流${NC}"
        echo "  - 停止 WireGuard 和分流规则"
        echo "  - 删除配置文件和服务"
        echo "  - 不删除 wireguard 软件包（系统常用）"
        echo ""
        read -rp "确认卸载? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }
    fi

    print_step "1" "停止服务"
    systemctl stop wg-split.service 2>/dev/null || true
    systemctl disable wg-split.service 2>/dev/null || true
    print_success "服务已停止"

    print_step "2" "清理 iptables 规则"
    $IPRULES_FILE disable 2>/dev/null || true
    # 兜底清理
    iptables -t mangle -D OUTPUT -m owner --uid-owner "$XRAY_USER" -m conntrack --ctstate NEW -j MARK --set-mark "$FWMARK" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -o "$WG_IFACE" -m owner --uid-owner "$XRAY_USER" -j MASQUERADE 2>/dev/null || true
    print_success "iptables 规则已清理"

    print_step "3" "删除文件和服务"
    rm -f "$SERVICE_FILE"
    rm -f "$IPRULES_FILE"
    rm -f "$WG_CONF"
    systemctl daemon-reload
    print_success "配置文件和服务已删除"

    print_step "4" "清理路由表"
    ip rule del fwmark "$FWMARK" table "$RT_TABLE_NAME" 2>/dev/null || true
    ip route flush table "$RT_TABLE_NAME" 2>/dev/null || true
    sed -i "/^${RT_TABLE_ID} ${RT_TABLE_NAME}$/d" /etc/iproute2/rt_tables 2>/dev/null || true
    print_success "路由表已清理"

    echo ""
    print_success "WireGuard 分流已卸载"
    print_info "提示: wireguard 软件包未删除，xray 服务未受影响"
    print_info "提示: 专用用户 $XRAY_USER 未删除（属 xray server.sh 管理）"
    echo ""
}

# ============ 入口 ============
ACTION="${1:-help}"
shift 2>/dev/null || true

case "$ACTION" in
    install)   do_install "$@" ;;
    enable)    do_enable ;;
    disable)   do_disable ;;
    status)    do_status ;;
    uninstall) do_uninstall "$@" ;;
    help)      print_help ;;
    *)         echo "未知命令: $ACTION"; print_help; exit 1 ;;
esac
