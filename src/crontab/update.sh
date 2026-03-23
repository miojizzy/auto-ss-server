#!/usr/bin/env bash
# IP 可用性检测与自动切换脚本
# 定时检测实例 IP 质量，自动更换 IP

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >> "$LOG_FILE"
}

# 默认配置
LOG_FILE="${LOG_FILE:-./auto_ssserver.log}"
CONF_FILE="${CONF_FILE:-./conf}"
LOSS_MAX_LIMIT="${LOSS_MAX_LIMIT:-50}"
LAUNCH_TEMPLATE_NAME="${LAUNCH_TEMPLATE_NAME:-auto_ss}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/conf.d/proxy.conf}"
NGINX_DOCKER_NAME="${NGINX_DOCKER_NAME:-nginx}"

# 解析配置文件
load_config() {
    if [[ -f "$CONF_FILE" ]]; then
        source "$CONF_FILE"
    fi
}

# 获取实例信息
# 返回: insta_id ip
get_instance_info() {
    local ret
    ret=$(aws ec2 describe-instances --region "${AWS_REGION:-ap-northeast-1}")
    
    insta_id=$(echo "$ret" | jq -r '[ .Reservations[] | select(.Instances[0].State.Name == "running") ][0].Instances[0].InstanceId // empty')
    ip=$(echo "$ret" | jq -r '[ .Reservations[] | select(.Instances[0].State.Name == "running") ][0].Instances[0].PublicIpAddress // empty')
    
    [[ -z "$insta_id" || "$insta_id" == "null" ]] && insta_id=""
    [[ -z "$ip" || "$ip" == "null" ]] && ip=""
}

# 释放实例
# 参数: insta_id
release_instance() {
    if [[ -n "$1" ]]; then
        aws ec2 terminate-instances --region "${AWS_REGION:-ap-northeast-1}" --instance-ids "$1" > /dev/null
        log_info "已释放实例: $1"
    fi
}

# 分配实例
# 参数: template_name
allocate_instance() {
    aws ec2 run-instances \
        --region "${AWS_REGION:-ap-northeast-1}" \
        --launch-template "LaunchTemplateName=$1" \
        --key-name="${AWS_KEY_NAME:-ap-northeast-1}" > /dev/null
    log_info "已分配新实例，模板: $1"
}

# 获取弹性 IP 信息
# 参数: insta_id
# 返回: assoc_id alloc_id ip
get_address_info() {
    local ret
    ret=$(aws ec2 describe-addresses --region "${AWS_REGION:-ap-northeast-1}")
    
    assoc_id=$(echo "$ret" | jq -r ".Addresses[] | select(.InstanceId==\"$1\") | .AssociationId // empty")
    alloc_id=$(echo "$ret" | jq -r ".Addresses[] | select(.InstanceId==\"$1\") | .AllocationId // empty")
    ip=$(echo "$ret" | jq -r ".Addresses[] | select(.InstanceId==\"$1\") | .PublicIp // empty")
    
    [[ -z "$assoc_id" || "$assoc_id" == "null" ]] && assoc_id=""
    [[ -z "$alloc_id" || "$alloc_id" == "null" ]] && alloc_id=""
    [[ -z "$ip" || "$ip" == "null" ]] && ip=""
}

# 释放弹性 IP
# 参数: assoc_id alloc_id
release_address() {
    if [[ -n "$1" ]]; then
        aws ec2 disassociate-address --region "${AWS_REGION:-ap-northeast-1}" --association-id "$1" > /dev/null
    fi
    if [[ -n "$2" ]]; then
        aws ec2 release-address --region "${AWS_REGION:-ap-northeast-1}" --allocation-id "$2" > /dev/null
    fi
    log_info "已释放弹性 IP"
}

# 分配弹性 IP
# 参数: insta_id
# 返回: alloc_id ip
allocate_address() {
    local ret
    ret=$(aws ec2 allocate-address --region "${AWS_REGION:-ap-northeast-1}")
    
    alloc_id=$(echo "$ret" | jq -r ".AllocationId")
    ip=$(echo "$ret" | jq -r ".PublicIp")
    
    aws ec2 associate-address \
        --region "${AWS_REGION:-ap-northeast-1}" \
        --allocation-id "$alloc_id" \
        --instance-id "$1" > /dev/null
    
    log_info "已分配新弹性 IP: $ip"
}

# 检测丢包率
# 参数: ip
# 返回: loss
check_ping_loss() {
    local loss
    loss=$(ping -c 4 -W 5 "$1" 2>/dev/null | grep "packet loss" | grep -oP '\d+(?=% packet loss)' || echo "100")
    echo "$loss"
}

# 更新 Nginx 配置
# 参数: nginx_conf newip
change_nginx() {
    if [[ -f "$1" ]]; then
        sed -r "s/^( *server ).*(:[0-9]+;)$/\1$2\2/g" -i "$1"
        nginx -s reload 2>/dev/null || systemctl reload nginx 2>/dev/null || true
        log_info "已更新 Nginx 配置，新 IP: $2"
    fi
}

# 更新 Docker Nginx 配置
# 参数: nginx_conf newip docker_name
change_nginx_docker() {
    if [[ -f "$1" ]]; then
        sed -r "s/^( *server ).*(:[0-9]+;)$/\1$2\2/g" -i "$1"
        docker exec "$3" nginx -s reload 2>/dev/null || true
        log_info "已更新 Docker Nginx 配置，新 IP: $2"
    fi
}

# 创建新实例
create_instance() {
    get_instance_info
    
    if [[ -n "$insta_id" ]]; then
        log_warn "实例已存在: $insta_id"
        return 1
    fi
    
    allocate_instance "$LAUNCH_TEMPLATE_NAME"
    
    # 等待实例就绪
    local wait_count=0
    while [[ -z "$insta_id" || -z "$ip" ]]; do
        sleep 5
        get_instance_info
        ((wait_count++))
        if [[ $wait_count -gt 30 ]]; then
            log_error "等待实例超时"
            return 1
        fi
    done
    
    # 更新 Nginx
    if [[ -n "$NGINX_DOCKER_NAME" ]]; then
        change_nginx_docker "$NGINX_CONF" "$ip" "$NGINX_DOCKER_NAME"
    else
        change_nginx "$NGINX_CONF" "$ip"
    fi
    
    log_info "创建实例完成: $insta_id, IP: $ip"
}

# 终止实例
terminate_instance() {
    get_instance_info
    
    if [[ -z "$insta_id" ]]; then
        log_warn "没有运行中的实例"
        return 0
    fi
    
    get_address_info "$insta_id"
    
    if [[ -n "$assoc_id" || -n "$alloc_id" ]]; then
        release_address "$assoc_id" "$alloc_id"
    fi
    
    release_instance "$insta_id"
    
    log_info "终止实例完成: $insta_id"
}

# 检查并切换 IP
check_and_switch() {
    get_instance_info
    
    if [[ -z "$insta_id" ]]; then
        log_warn "没有运行中的实例"
        return 1
    fi
    
    local loss
    loss=$(check_ping_loss "$ip")
    
    if [[ $loss -lt $LOSS_MAX_LIMIT ]]; then
        log_info "检查通过: 实例 $insta_id, IP $ip, 丢包率 ${loss}%"
        return 0
    fi
    
    log_warn "丢包率过高: ${loss}%，准备切换 IP"
    
    local old_ip="$ip"
    get_address_info "$insta_id"
    
    # 释放旧 IP
    release_address "$assoc_id" "$alloc_id"
    
    # 分配新 IP
    allocate_address "$insta_id"
    
    # 更新 Nginx
    if [[ -n "$NGINX_DOCKER_NAME" ]]; then
        change_nginx_docker "$NGINX_CONF" "$ip" "$NGINX_DOCKER_NAME"
    else
        change_nginx "$NGINX_CONF" "$ip"
    fi
    
    log_info "IP 切换完成: $old_ip -> $ip"
}

# 显示帮助
show_help() {
    cat << EOF
用法: $0 <命令> [选项]

命令:
  create      创建新实例
  check       检查 IP 可用性，必要时切换
  terminate   终止实例
  help        显示帮助

环境变量:
  AWS_REGION          AWS 区域 (默认: ap-northeast-1)
  AWS_KEY_NAME        SSH 密钥名称
  LOSS_MAX_LIMIT      最大丢包率阈值 (默认: 50)
  LAUNCH_TEMPLATE_NAME 启动模板名称 (默认: auto_ss)
  NGINX_CONF          Nginx 配置文件路径
  NGINX_DOCKER_NAME   Nginx Docker 容器名称
  LOG_FILE            日志文件路径

配置文件:
  $CONF_FILE

示例:
  $0 create
  $0 check
  $0 terminate
EOF
}

# 主函数
main() {
    load_config
    
    local cmd="${1:-help}"
    shift || true
    
    case "$cmd" in
        create)
            create_instance
            ;;
        check)
            check_and_switch
            ;;
        terminate)
            terminate_instance
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
