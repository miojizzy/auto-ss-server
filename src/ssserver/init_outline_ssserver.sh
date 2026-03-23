#!/bin/bash
# Outline Shadowsocks 服务器安装脚本
# 用于在 EC2 实例上安装和配置 Outline SS Server

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 配置文件路径
CONFIG_FILE="${CONFIG_FILE:-/data/ss_config.yml}"
LOG_FILE="/var/log/outline_ssserver.log"
DATA_DIR="/data"

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config|-c)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --port|-p)
                PORT="$2"
                shift 2
                ;;
            --password|-k)
                PASSWORD="$2"
                shift 2
                ;;
            --method|-m)
                METHOD="$2"
                shift 2
                ;;
            --metrics-port)
                METRICS_PORT="$2"
                shift 2
                ;;
            --help|-h)
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
}

show_help() {
    cat << EOF
用法: $0 [选项]

选项:
  -c, --config FILE          配置文件路径
  -p, --port PORT            Shadowsocks 端口
  -k, --password PASSWORD    密码
  -m, --method METHOD        加密方式 (默认: chacha20-ietf-poly1305)
  --metrics-port PORT        Metrics 端口 (默认: 9091)
  -h, --help                 显示帮助

示例:
  $0 -p 2333 -k mypassword
  $0 -c /data/ss_config.yml
EOF
}

# 安装 Go 环境
install_go() {
    log_info "安装 Go 环境..."
    
    local go_version="1.23.4"
    local go_tar="go${go_version}.linux-amd64.tar.gz"
    
    if command -v go &> /dev/null; then
        local current_version=$(go version | awk '{print $3}')
        log_info "Go 已安装: ${current_version}"
        return 0
    fi
    
    cd /tmp
    wget -q "https://go.dev/dl/${go_tar}"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "${go_tar}"
    rm "${go_tar}"
    
    export PATH=$PATH:/usr/local/go/bin
    
    # 添加到 bashrc
    if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
        echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc
    fi
    
    log_info "Go ${go_version} 安装完成"
}

# 生成配置文件
generate_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "使用现有配置文件: ${CONFIG_FILE}"
        return 0
    fi
    
    log_info "生成配置文件..."
    
    PORT=${PORT:-2333}
    PASSWORD=${PASSWORD:-"change_me_password"}
    METHOD=${METHOD:-"chacha20-ietf-poly1305"}
    
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    cat > "$CONFIG_FILE" << EOF
services:
  - listeners:
      - type: tcp
        address: "[::]:${PORT}"
      - type: udp
        address: "[::]:${PORT}"
    keys:
        - id: user-0
          cipher: ${METHOD}
          secret: ${PASSWORD}
EOF
    
    log_info "配置文件已生成: ${CONFIG_FILE}"
    log_info "端口: ${PORT}, 加密方式: ${METHOD}"
}

# 安装 Outline SS Server
install_outline_server() {
    log_info "安装 Outline SS Server..."
    
    cd "${DATA_DIR}"
    
    if [[ ! -d "outline-ss-server" ]]; then
        git clone -b v1.7.3 --depth=1 https://github.com/Jigsaw-Code/outline-ss-server.git
    fi
    
    log_info "Outline SS Server 安装完成"
}

# 启动服务
start_server() {
    log_info "启动 Outline SS Server..."
    
    METRICS_PORT=${METRICS_PORT:-9091}
    
    # 检查是否已在运行
    if pgrep -f "outline-ss-server" > /dev/null; then
        log_warn "Outline SS Server 已在运行"
        return 0
    fi
    
    cd "${DATA_DIR}/outline-ss-server"
    
    nohup go run ./cmd/outline-ss-server \
        -config "${CONFIG_FILE}" \
        -metrics "0.0.0.0:${METRICS_PORT}" \
        --replay_history=10000 \
        > "${LOG_FILE}" 2>&1 &
    
    sleep 2
    
    if pgrep -f "outline-ss-server" > /dev/null; then
        log_info "服务启动成功"
        log_info "Metrics 地址: http://0.0.0.0:${METRICS_PORT}/metrics"
    else
        log_error "服务启动失败，请查看日志: ${LOG_FILE}"
        exit 1
    fi
}

# 显示状态
show_status() {
    echo ""
    echo "=========================================="
    echo "Outline SS Server 状态"
    echo "=========================================="
    
    if pgrep -f "outline-ss-server" > /dev/null; then
        echo "状态: 运行中"
        echo "PID: $(pgrep -f 'outline-ss-server')"
        echo "配置文件: ${CONFIG_FILE}"
        echo "日志文件: ${LOG_FILE}"
        
        if command -v ss &> /dev/null; then
            echo ""
            echo "监听端口:"
            ss -tlnp | grep -E "(ss-server|outline)" || true
        fi
    else
        echo "状态: 未运行"
    fi
    
    echo "=========================================="
}

# 主函数
main() {
    parse_args "$@"
    
    log_info "=========================================="
    log_info "Outline SS Server 安装脚本"
    log_info "=========================================="
    
    # 创建数据目录
    mkdir -p "${DATA_DIR}"
    
    # 安装依赖
    install_go
    
    # 生成配置
    generate_config
    
    # 安装服务
    install_outline_server
    
    # 启动服务
    start_server
    
    # 显示状态
    show_status
}

main "$@"
