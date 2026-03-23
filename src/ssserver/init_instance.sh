#!/bin/bash
# Shadowsocks 服务器初始化脚本
# 提供多种 Shadowsocks 实现的安装入口

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

show_help() {
    cat << EOF
用法: $0 [类型] [选项]

类型:
  outline    安装 Outline SS Server (推荐)
  python     安装 Python Shadowsocks
  libev      安装 Shadowsocks-libev

选项:
  -c, --config FILE          配置文件路径
  -p, --port PORT            Shadowsocks 端口
  -k, --password PASSWORD    密码
  -m, --method METHOD        加密方式
  -h, --help                 显示帮助

示例:
  $0 outline -p 2333 -k mypassword
  $0 python -p 8388 -k mypass -m aes-256-gcm
EOF
}

# 主函数
main() {
    local server_type="${1:-outline}"
    shift || true
    
    case "$server_type" in
        outline|Outline)
            log_info "安装 Outline SS Server..."
            "$(dirname "$0")/init_outline_ssserver.sh" "$@"
            ;;
        python|Python)
            log_info "安装 Python Shadowsocks..."
            "$(dirname "$0")/init_python_ssserver.sh" "$@"
            ;;
        libev)
            log_info "安装 Shadowsocks-libev..."
            log_warn "暂不支持，请使用 outline 或 python"
            exit 1
            ;;
        -h|--help|help)
            show_help
            ;;
        *)
            log_error "未知的服务类型: $server_type"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
