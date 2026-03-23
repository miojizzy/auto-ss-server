# IP 可用性检测与自动切换模块

定时检测 EC2 实例 IP 质量，当 IP 不可用时自动更换弹性 IP。

## 功能特点

- 自动检测 IP 丢包率
- 丢包率超过阈值自动切换 IP
- 支持自动更新 Nginx 代理配置
- 支持 Docker Nginx 容器
- 完整的日志记录

## 工作原理

```
┌─────────────────────────────────────────────────────────────┐
│                    定时检查流程                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │ Ping 检测 │────▶│ 丢包率计算  │────▶│ 阈值判断    │    │
│  └──────────┘     └──────────────┘     └──────────────┘    │
│                                                │            │
│                           ┌────────────────────┴───────┐    │
│                           ▼                            ▼    │
│                    ┌─────────────┐              ┌──────────┐│
│                    │ 正常（结束）│              │ 切换 IP  ││
│                    └─────────────┘              └──────────┘│
│                                                          │   │
│                                                          ▼   │
│                                              ┌──────────────┐│
│                                              │ 释放旧 EIP   ││
│                                              └──────────────┘│
│                                                          │   │
│                                                          ▼   │
│                                              ┌──────────────┐│
│                                              │ 分配新 EIP   ││
│                                              └──────────────┘│
│                                                          │   │
│                                                          ▼   │
│                                              ┌──────────────┐│
│                                              │ 更新 Nginx   ││
│                                              └──────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 安装

### 配置 crontab

```bash
# 编辑 crontab
crontab -e

# 每 5 分钟检查一次
*/5 * * * * /path/to/auto_ssserver/src/crontab/update.sh check

# 或者使用系统 crontab
echo '*/5 * * * * root /path/to/auto_ssserver/src/crontab/update.sh check' > /etc/cron.d/auto_ssserver
```

### 配置文件

编辑 `src/crontab/conf` 文件：

```bash
# AWS 区域
AWS_REGION="ap-northeast-1"

# SSH 密钥名称
AWS_KEY_NAME="ap-northeast-1"

# 启动模板名称
LAUNCH_TEMPLATE_NAME="auto_ss"

# 最大丢包率阈值（%）
LOSS_MAX_LIMIT=50

# Nginx 配置文件路径
NGINX_CONF="/etc/nginx/conf.d/proxy.conf"

# Nginx Docker 容器名称（留空表示非 Docker 部署）
NGINX_DOCKER_NAME="nginx"

# 日志文件路径
LOG_FILE="/var/log/auto_ssserver.log"
```

## 使用方法

### 手动执行

```bash
# 创建实例
./update.sh create

# 检查并切换 IP
./update.sh check

# 终止实例
./update.sh terminate

# 查看帮助
./update.sh help
```

### 环境变量

可以通过环境变量覆盖配置文件：

```bash
AWS_REGION=us-west-2 LOSS_MAX_LIMIT=30 ./update.sh check
```

## 与 Nginx 配合

### Nginx 配置示例

```nginx
# /etc/nginx/conf.d/proxy.conf
upstream ss_backend {
    server 1.2.3.4:2333;  # 此 IP 会被自动更新
}

server {
    listen 80;
    
    location / {
        proxy_pass http://ss_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Docker 部署

```yaml
# docker-compose.yml
version: '3'
services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./conf.d:/etc/nginx/conf.d
    ports:
      - "80:80"
```

配置中设置：
```bash
NGINX_DOCKER_NAME="nginx"
NGINX_CONF="./conf.d/proxy.conf"
```

## 日志

日志格式：

```
[2024-01-01 12:00:00] [INFO] 检查通过: 实例 i-xxx, IP 1.2.3.4, 丢包率 0%
[2024-01-01 12:05:00] [WARN] 丢包率过高: 80%，准备切换 IP
[2024-01-01 12:05:05] [INFO] 已释放弹性 IP
[2024-01-01 12:05:10] [INFO] 已分配新弹性 IP: 5.6.7.8
[2024-01-01 12:05:11] [INFO] 已更新 Nginx 配置，新 IP: 5.6.7.8
[2024-01-01 12:05:11] [INFO] IP 切换完成: 1.2.3.4 -> 5.6.7.8
```

查看日志：

```bash
tail -f /var/log/auto_ssserver.log
```

## IAM 权限要求

运行此脚本需要的 IAM 权限：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:RunInstances",
                "ec2:TerminateInstances",
                "ec2:DescribeAddresses",
                "ec2:AllocateAddress",
                "ec2:ReleaseAddress",
                "ec2:AssociateAddress",
                "ec2:DisassociateAddress"
            ],
            "Resource": "*"
        }
    ]
}
```

## 故障排查

### 命令未找到

```bash
# 确保 aws 命令在 PATH 中
which aws

# 或使用完整路径
alias aws="/usr/local/bin/aws"
```

### 权限不足

检查 AWS 凭证配置：

```bash
aws sts get-caller-identity
```

### jq 未安装

```bash
# Ubuntu/Debian
apt-get install jq

# CentOS/RHEL
yum install jq
```

### Ping 检测失败

确保运行环境允许 ICMP：

- 安全组允许 ICMP
- 网络允许 ICMP 流量

## 注意事项

1. **弹性 IP 配额**: AWS 默认每个区域 5 个弹性 IP，释放后才能再次分配
2. **切换时间**: IP 切换需要几秒钟，期间可能短暂不可用
3. **费用**: 弹性 IP 绑定到实例免费，未绑定的弹性 IP 收费
4. **数据**: 切换 IP 不影响实例数据
