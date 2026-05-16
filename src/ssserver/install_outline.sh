#!/bin/bash
# Outline SS Server 一键安装脚本
# 支持 curl|bash 方式运行
#
# 用法:
#   curl -fsSL <url> | bash -s -- -p 2333:mypassword
#   curl -fsSL <url> | bash -s -- -p 2333:pass1 -p 2334:pass2 -m chacha20-ietf-poly1305
#
# 参数:
#   -p, --port PORT:PASSWORD   端口和密码（可重复使用以添加多个）
#   -m, --method METHOD        加密方式（默认: chacha20-ietf-poly1305）
#   --metrics-port PORT        Metrics 端口（默认: 9091）
#   -h, --help                 显示帮助

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 默认值
METHOD="chacha20-ietf-poly1305"
METRICS_PORT=9091
DATA_DIR="/data"
CONFIG_FILE="${DATA_DIR}/ss_config.yml"
LOG_FILE="/var/log/outline_ssserver.log"
PORTS_PASSWORDS=()

show_help() {
    cat << 'EOF'
用法: curl -fsSL <url> | bash -s -- [选项]

选项:
  -p, --port PORT:PASSWORD   端口:密码（可重复指定多个）
  -m, --method METHOD        加密方式（默认: chacha20-ietf-poly1305）
  --metrics-port PORT        Metrics 端口（默认: 9091）
  -h, --help                 显示帮助

示例:
  # 单端口
  curl -fsSL <url> | bash -s -- -p 2333:mypassword

  # 多端口
  curl -fsSL <url> | bash -s -- -p 2333:pass1 -p 2334:pass2

  # 指定加密方式
  curl -fsSL <url> | bash -s -- -p 2333:mypassword -m aes-256-gcm
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--port)
                PORTS_PASSWORDS+=("$2")
                shift 2
                ;;
            -m|--method)
                METHOD="$2"
                shift 2
                ;;
            --metrics-port)
                METRICS_PORT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 若未指定端口，使用默认值
    if [[ ${#PORTS_PASSWORDS[@]} -eq 0 ]]; then
        log_warn "未指定端口配置，使用默认: 2333:change_me_password"
        PORTS_PASSWORDS=("2333:change_me_password")
    fi
}

install_deps() {
    log_info "安装系统依赖..."

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
    fi

    case "${ID:-}" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq git wget curl
            ;;
        centos|rhel|amzn|amazon)
            yum install -y -q git wget curl
            ;;
        *)
            log_warn "未知系统 '${ID:-}'，跳过自动安装依赖，请确保 git 和 wget 已安装"
            ;;
    esac
}

install_go() {
    if command -v go &>/dev/null; then
        log_info "Go 已安装: $(go version)"
        return 0
    fi

    log_info "安装 Go 1.23.4..."
    local go_tar="go1.23.4.linux-amd64.tar.gz"
    cd /tmp
    wget -q "https://go.dev/dl/${go_tar}"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "${go_tar}"
    rm -f "${go_tar}"
    export PATH=$PATH:/usr/local/go/bin

    if ! grep -q "/usr/local/go/bin" /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi

    log_info "Go 安装完成: $(go version)"
}

generate_config() {
    log_info "生成 Outline 配置文件..."
    mkdir -p "${DATA_DIR}"

    {
        echo "services:"
        local i=0
        for entry in "${PORTS_PASSWORDS[@]}"; do
            local port="${entry%%:*}"
            local password="${entry#*:}"
            cat << EOF
  - listeners:
      - type: tcp
        address: "[::]:${port}"
      - type: udp
        address: "[::]:${port}"
    keys:
        - id: user-${i}
          cipher: ${METHOD}
          secret: ${password}
EOF
            i=$((i + 1))
        done
    } > "${CONFIG_FILE}"

    log_info "配置文件已写入: ${CONFIG_FILE}"
    for entry in "${PORTS_PASSWORDS[@]}"; do
        log_info "  端口: ${entry%%:*}  加密: ${METHOD}"
    done
}

install_outline_server() {
    log_info "克隆 Outline SS Server (v1.7.3)..."
    export PATH=$PATH:/usr/local/go/bin
    cd "${DATA_DIR}"

    if [[ ! -d "outline-ss-server" ]]; then
        git clone -b v1.7.3 --depth=1 https://github.com/Jigsaw-Code/outline-ss-server.git
    else
        log_warn "outline-ss-server 目录已存在，跳过克隆"
    fi
}

start_server() {
    log_info "启动 Outline SS Server..."
    export PATH=$PATH:/usr/local/go/bin

    if pgrep -f "outline-ss-server" > /dev/null 2>&1; then
        log_warn "Outline SS Server 已在运行，跳过启动"
        return 0
    fi

    cd "${DATA_DIR}/outline-ss-server"
    nohup go run ./cmd/outline-ss-server \
        -config "${CONFIG_FILE}" \
        -metrics "0.0.0.0:${METRICS_PORT}" \
        --replay_history=10000 \
        > "${LOG_FILE}" 2>&1 &

    sleep 3

    if pgrep -f "outline-ss-server" > /dev/null 2>&1; then
        log_info "服务启动成功 (PID: $(pgrep -f 'outline-ss-server'))"
        log_info "Metrics: http://0.0.0.0:${METRICS_PORT}/metrics"
        log_info "日志: ${LOG_FILE}"
    else
        log_error "服务启动失败，请查看日志: ${LOG_FILE}"
        exit 1
    fi
}

main() {
    parse_args "$@"

    log_info "=========================================="
    log_info "Outline SS Server 一键安装脚本"
    log_info "=========================================="

    install_deps
    install_go
    generate_config
    install_outline_server
    start_server

    log_info "=========================================="
    log_info "安装完成！"
    log_info "=========================================="
}

main "$@"
