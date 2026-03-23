#!/bin/bash
# 启动模板管理脚本
# 创建通用的 EC2 启动模板

set -e

# 默认值
DEFAULT_TEMPLATE_NAME="auto_ss"
DEFAULT_INSTANCE_TYPE="t2.nano"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region|-r)
                REGION="$2"
                shift 2
                ;;
            --name|-n)
                TEMPLATE_NAME="$2"
                shift 2
                ;;
            --ami-id)
                AMI_ID="$2"
                shift 2
                ;;
            --instance-type|-t)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            --delete)
                DELETE_MODE=true
                shift
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
  -r, --region REGION        AWS 区域代码
  -n, --name NAME            模板名称 (默认: auto_ss)
  --ami-id AMI_ID            AMI ID
  -t, --instance-type TYPE   实例类型 (默认: t2.nano)
  --delete                   删除模式
  -h, --help                 显示帮助信息

示例:
  $0 --region ap-northeast-1 --ami-id ami-0fe22bffdec36361c
  $0 -r ap-northeast-1 -n my-template
  $0 --delete -r ap-northeast-1
EOF
}

# 从配置文件获取区域信息
get_region_config() {
    local config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config"
    local regions_file="${config_dir}/regions.yaml"
    
    if [[ -f "$regions_file" ]]; then
        # 简单解析 YAML
        AMI_ID=$(grep -A 10 "${REGION}:" "$regions_file" | grep "ami_id:" | head -1 | awk '{print $2}' | tr -d '"')
        INSTANCE_TYPE=${INSTANCE_TYPE:-$(grep -A 10 "${REGION}:" "$regions_file" | grep "default_instance_type:" | head -1 | awk '{print $2}')}
    fi
}

# 创建安全组
create_security_group() {
    local sg_name="${TEMPLATE_NAME}_sg"
    
    log_info "检查安全组 ${sg_name}..."
    
    # 检查安全组是否存在
    local sg_id=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-names "$sg_name" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [[ "$sg_id" != "None" && -n "$sg_id" ]]; then
        log_warn "安全组 ${sg_name} 已存在: ${sg_id}"
        SG_ID="$sg_id"
        return 0
    fi
    
    # 创建安全组
    log_info "创建安全组 ${sg_name}..."
    SG_ID=$(aws ec2 create-security-group \
        --region "$REGION" \
        --group-name "$sg_name" \
        --description "Security group for ${TEMPLATE_NAME}" \
        --query 'GroupId' \
        --output text)
    
    log_info "安全组已创建: ${SG_ID}"
    
    # 添加基础入站规则
    log_info "配置安全组规则..."
    
    # SSH
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 2>/dev/null || log_warn "SSH 规则可能已存在"
    
    # ICMP (ping)
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$SG_ID" \
        --protocol icmp \
        --port -1 \
        --cidr 0.0.0.0/0 2>/dev/null || log_warn "ICMP 规则可能已存在"
    
    # Metrics 端口
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 9091 \
        --cidr 0.0.0.0/0 2>/dev/null || log_warn "Metrics 规则可能已存在"
    
    log_info "安全组规则配置完成"
}

# 删除安全组
delete_security_group() {
    local sg_name="${TEMPLATE_NAME}_sg"
    
    log_info "查找安全组 ${sg_name}..."
    local sg_id=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-names "$sg_name" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
        log_warn "安全组 ${sg_name} 不存在"
        return 0
    fi
    
    log_info "删除安全组 ${sg_id}..."
    aws ec2 delete-security-group \
        --region "$REGION" \
        --group-id "$sg_id"
    
    log_info "安全组已删除"
}

# 创建启动模板
create_launch_template() {
    TEMPLATE_NAME=${TEMPLATE_NAME:-$DEFAULT_TEMPLATE_NAME}
    INSTANCE_TYPE=${INSTANCE_TYPE:-$DEFAULT_INSTANCE_TYPE}
    
    if [[ -z "$REGION" ]]; then
        log_error "请指定区域 (--region)"
        exit 1
    fi
    
    # 获取区域配置
    get_region_config
    
    if [[ -z "$AMI_ID" ]]; then
        log_error "无法获取 AMI ID，请使用 --ami-id 指定"
        exit 1
    fi
    
    log_info "=========================================="
    log_info "创建启动模板"
    log_info "=========================================="
    log_info "区域: ${REGION}"
    log_info "模板名称: ${TEMPLATE_NAME}"
    log_info "AMI ID: ${AMI_ID}"
    log_info "实例类型: ${INSTANCE_TYPE}"
    log_info "=========================================="
    
    # 创建安全组
    create_security_group
    
    # 生成基础 User Data（空模板，运行时覆盖）
    local user_data=$(echo "#!/bin/bash
# 这是通用启动模板
# 实际配置将在实例启动时通过 --user-data 参数传入
echo 'Starting instance...'" | base64 -w 0)
    
    # 删除已存在的模板
    log_info "检查并删除已存在的模板..."
    aws ec2 delete-launch-template \
        --region "$REGION" \
        --launch-template-name "$TEMPLATE_NAME" 2>/dev/null || true
    
    # 创建启动模板
    log_info "创建启动模板..."
    aws ec2 create-launch-template \
        --region "$REGION" \
        --launch-template-name "$TEMPLATE_NAME" \
        --launch-template-data "{
            \"ImageId\": \"${AMI_ID}\",
            \"InstanceType\": \"${INSTANCE_TYPE}\",
            \"SecurityGroupIds\": [\"${SG_ID}\"],
            \"UserData\": \"${user_data}\",
            \"EbsOptimized\": false,
            \"Monitoring\": {\"Enabled\": false},
            \"CreditSpecification\": {\"CpuCredits\": \"standard\"}
        }"
    
    log_info "=========================================="
    log_info "启动模板创建完成!"
    log_info "使用方法: awsl run -r ${REGION} -T ${TEMPLATE_NAME} -p 2333:yourpassword"
    log_info "=========================================="
}

# 删除启动模板
delete_launch_template() {
    if [[ -z "$REGION" ]]; then
        log_error "请指定区域 (--region)"
        exit 1
    fi
    
    TEMPLATE_NAME=${TEMPLATE_NAME:-$DEFAULT_TEMPLATE_NAME}
    
    log_info "删除启动模板 ${TEMPLATE_NAME}..."
    
    aws ec2 delete-launch-template \
        --region "$REGION" \
        --launch-template-name "$TEMPLATE_NAME" 2>/dev/null || log_warn "模板不存在或已删除"
    
    # 删除安全组
    delete_security_group
    
    log_info "清理完成"
}

# 主函数
main() {
    # 检查 AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安装"
        log_info "请运行: ./setup.sh aws"
        exit 1
    fi
    
    parse_args "$@"
    
    if [[ "${DELETE_MODE}" == "true" ]]; then
        delete_launch_template
    else
        create_launch_template
    fi
}

main "$@"
