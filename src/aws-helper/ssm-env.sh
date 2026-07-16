#!/bin/bash

# SSM 参数解引用器
# 把要固定的变量值设成 SSM 参数路径传入，脚本读出真实值再打印成同名变量。
#   - 变量值以 / 开头  -> 当作 SSM 参数路径，从 SSM 拉真实值
#   - 否则             -> 原样当作字面值输出
#
# 用法:
#   XRAY_UUID=/xray/uuid REALITY_SNI=www.yahoo.com \
#     bash ssm-env.sh get XRAY_UUID REALITY_SNI
#   -> 输出到 stdout:
#        XRAY_UUID='ac8a556c-...'
#        REALITY_SNI='www.yahoo.com'
#
# 典型场景(EC2 user-data)：解出真实值写成 /etc/xray-server.env，供 server.sh 自动加载：
#   XRAY_UUID=/xray/uuid ... bash ssm-env.sh get XRAY_UUID ... | sudo tee /etc/xray-server.env
#
# 职责边界：只读 SSM 并打印。不写文件、不写 SSM、不装 xray。

set -euo pipefail

# ============ 颜色与打印(全部到 stderr，避免污染 stdout) ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}" >&2; }
print_error()   { echo -e "${RED}✗ $1${NC}" >&2; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}" >&2; }

print_help() {
    cat >&2 <<'EOF'
SSM 参数解引用器

用法: [VAR=值 ...] bash ssm-env.sh <命令> VAR [VAR ...]

命令:
  get VAR...     输出 NAME='value' 行(默认命令)
  env VAR...     同 get，每行加 export 前缀，供 eval "$(... env ...)"
  help           显示此帮助

规则:
  每个列出的变量，取其当前值：
    - 值以 / 开头 -> 当作 SSM 参数路径，从 SSM 拉真实值(--with-decryption)
    - 否则        -> 原样当作字面值
  拉取失败(参数不存在/无权限)的变量跳过不输出，不中断。

区域(region):
  AWS_REGION 环境变量优先；否则从实例元数据(IMDSv2/IMDSv1)获取。

示例:
  XRAY_UUID=/xray/uuid REALITY_SNI=www.yahoo.com \
    bash ssm-env.sh get XRAY_UUID REALITY_SNI
EOF
}

# ============ 依赖检查 ============
require_aws() {
    if ! command -v aws >/dev/null 2>&1; then
        print_error "未找到 aws CLI，请先安装："
        echo "  apt-get install -y awscli   # 或参考 AWS 官方安装文档" >&2
        exit 1
    fi
}

# ============ 获取 region ============
# 优先 AWS_REGION，否则 IMDSv2(带 token) -> IMDSv1 回落
detect_region() {
    if [[ -n "${AWS_REGION:-}" ]]; then
        echo "$AWS_REGION"
        return 0
    fi
    local token region
    token=$(curl -s --max-time 3 -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 300" 2>/dev/null || true)
    if [[ -n "$token" ]]; then
        region=$(curl -s --max-time 3 -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/meta-data/placement/region" 2>/dev/null || true)
    fi
    if [[ -z "${region:-}" ]]; then
        # IMDSv1 回落
        region=$(curl -s --max-time 3 \
            "http://169.254.169.254/latest/meta-data/placement/region" 2>/dev/null || true)
    fi
    if [[ -z "$region" ]]; then
        print_error "无法获取 region，请设置 AWS_REGION 环境变量"
        exit 1
    fi
    echo "$region"
}

# 从 SSM 拉单个参数真实值；失败返回非 0
ssm_fetch() {
    local path="$1" region="$2"
    aws ssm get-parameter \
        --region "$region" \
        --name "$path" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text 2>/dev/null
}

# 单引号安全转义：把值包成 '...'，内部 ' 替换为 '\''
shell_quote() {
    local v="$1"
    printf "'%s'" "${v//\'/\'\\\'\'}"
}

# ============ 主流程 ============
do_get() {
    local prefix="$1"; shift   # "" 或 "export "
    if [[ $# -eq 0 ]]; then
        print_error "未指定变量名"
        print_help
        exit 1
    fi

    local region="" name val real
    for name in "$@"; do
        # 取变量当前值(未定义则空)
        val="${!name:-}"
        if [[ -z "$val" ]]; then
            print_info "变量 $name 未设置或为空，跳过"
            continue
        fi

        if [[ "$val" == /* ]]; then
            # SSM 路径：首次用到时才检查依赖 / 取 region
            require_aws
            [[ -z "$region" ]] && region="$(detect_region)"
            if real="$(ssm_fetch "$val" "$region")"; then
                print_success "$name <- SSM $val"
                printf '%s%s=%s\n' "$prefix" "$name" "$(shell_quote "$real")"
            else
                print_error "$name: SSM 参数 $val 拉取失败(不存在/无权限)，跳过"
            fi
        else
            # 字面值原样输出
            printf '%s%s=%s\n' "$prefix" "$name" "$(shell_quote "$val")"
        fi
    done
}

# ===== 入口：子命令分发 =====
ACTION="${1:-help}"
case "$ACTION" in
    get)            shift; do_get "" "$@" ;;
    env)            shift; do_get "export " "$@" ;;
    help|-h|--help) print_help ;;
    *)
        print_error "未知命令: $ACTION"
        print_help
        exit 1
        ;;
esac
