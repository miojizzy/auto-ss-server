#!/bin/bash
# auto_ssserver 统一安装入口
# 管理所有模块的安装和初始化

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 显示帮助
show_help() {
    cat << EOF
用法: $0 <命令> [选项]

命令:
  aws             安装 AWS CLI
  awsl            安装 awsl 工具
  template        创建启动模板
  ssserver        在当前机器安装 Shadowsocks 服务器
  all             安装所有组件

选项:
  -r, --region    指定区域 (用于 template 命令)
  -h, --help      显示帮助

示例:
  $0 aws                          # 安装 AWS CLI
  $0 awsl                         # 安装 awsl 管理工具
  $0 template -r ap-northeast-1   # 在东京区域创建启动模板
  $0 ssserver                     # 安装 Shadowsocks 服务器
  $0 all                          # 安装所有组件

快速开始:
  $0 awsl
  $0 template -r ap-northeast-1
  awsl run -r ap-northeast-1 -p 2333:yourpassword
EOF
}

# 安装 AWS CLI
install_aws_cli() {
    log_step "安装 AWS CLI..."
    
    if command -v aws &> /dev/null; then
        log_info "AWS CLI 已安装: $(aws --version)"
        return 0
    fi
    
    # 检测系统类型
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
    fi
    
    case "$ID" in
        ubuntu|debian)
            log_info "检测到 Debian/Ubuntu 系统"
            apt-get update -qq
            apt-get install -y -qq unzip curl
            ;;
        centos|rhel|amazon)
            log_info "检测到 RHEL/CentOS/Amazon Linux 系统"
            yum install -y -q unzip curl
            ;;
        *)
            log_warn "未知系统: $ID，尝试继续安装"
            ;;
    esac
    
    # 下载并安装 AWS CLI
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    
    log_info "下载 AWS CLI..."
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    
    log_info "安装 AWS CLI..."
    unzip -q awscliv2.zip
    ./aws/install
    
    cd "$SCRIPT_DIR"
    rm -rf "$tmp_dir"
    
    log_info "AWS CLI 安装完成: $(aws --version)"
    log_warn "请运行 'aws configure' 配置凭证"
}

# 安装 awsl 工具
install_awsl() {
    log_step "安装 awsl 工具..."
    
    cd "${SCRIPT_DIR}/src/awsl"
    ./init.sh
    
    log_info "awsl 工具安装完成"
    log_info "使用方法: awsl --help"
}

# 创建启动模板
create_template() {
    log_step "创建启动模板..."
    
    local region=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                region="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$region" ]]; then
        log_warn "未指定区域，使用默认区域: ap-northeast-1"
        region="ap-northeast-1"
    fi
    
    cd "${SCRIPT_DIR}/src/launch_template"
    ./init_template.sh --region "$region"
    
    log_info "启动模板创建完成"
}

# 安装 Shadowsocks 服务器
install_ssserver() {
    log_step "安装 Shadowsocks 服务器..."
    
    cd "${SCRIPT_DIR}/src/ssserver"
    ./init_instance.sh outline
    
    log_info "Shadowsocks 服务器安装完成"
}

# 安装所有组件
install_all() {
    log_step "安装所有组件..."
    
    install_aws_cli
    echo ""
    install_awsl
    echo ""
    
    log_info "请运行以下命令完成配置:"
    log_info "  1. aws configure        # 配置 AWS 凭证"
    log_info "  2. $0 template -r <region>  # 创建启动模板"
    log_info "  3. awsl run -r <region> -p <port:password>  # 创建实例"
}

# 主函数
main() {
    local cmd="${1:-help}"
    shift || true
    
    case "$cmd" in
        aws)
            install_aws_cli
            ;;
        awsl)
            install_awsl
            ;;
        template|st)
            create_template "$@"
            ;;
        ssserver|si|osi)
            install_ssserver
            ;;
        all)
            install_all
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
