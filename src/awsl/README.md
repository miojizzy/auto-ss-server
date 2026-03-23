# awsl - AWS EC2 Shadowsocks 管理工具

一个简化 AWS EC2 Shadowsocks 实例管理的命令行工具。

## 功能特点

- 快速创建/销毁 EC2 实例
- 支持多区域部署
- 动态配置端口和加密方式
- 简洁的命令行接口

## 安装

### 前置要求

- Python 3.6+ 或 Python 2.7
- AWS CLI 已安装并配置
- PyYAML 库（可选，用于更好的配置解析）

### 安装步骤

```bash
cd /path/to/auto_ssserver
./setup.sh awsl
```

或手动安装：

```bash
cd src/awsl
./init.sh
```

## 使用方法

### 创建实例

```bash
# 基本用法（使用默认配置）
awsl run -r ap-northeast-1

# 自定义端口和密码
awsl run -r tokyo -p 2333:mypassword,2334:anotherpass

# 自定义加密方式和实例类型
awsl run -r singapore -p 8388:mypass -m aes-256-gcm -t t3.micro

# 带名称标签
awsl run -r tokyo -p 2333:mypass -n "my-ss-server"
```

### 查看实例

```bash
# 查看当前区域所有实例
awsl desc

# 查看指定区域实例
awsl desc -r ap-northeast-1
```

### 终止实例

```bash
# 终止实例（会要求确认）
awsl term i-0abc123def456

# 强制终止（不确认）
awsl term i-0abc123def456 -f
```

### 查看可用区域

```bash
awsl regions
```

### 查看当前配置

```bash
awsl config
```

### 管理启动模板

```bash
# 列出模板
awsl template list

# 创建模板
awsl template create -n my-template

# 删除模板
awsl template delete -n my-template
```

## 命令行参数

### run 命令

| 参数 | 简写 | 说明 | 示例 |
|------|------|------|------|
| --region | -r | 区域代码或名称 | `-r tokyo` 或 `-r ap-northeast-1` |
| --ports | -p | 端口配置 | `-p 2333:pass1,2334:pass2` |
| --method | -m | 加密方式 | `-m aes-256-gcm` |
| --instance-type | -t | 实例类型 | `-t t3.micro` |
| --template | -T | 启动模板名称 | `-T my-template` |
| --name | -n | 实例名称 | `-n my-server` |

### desc 命令

| 参数 | 简写 | 说明 |
|------|------|------|
| --region | -r | 区域代码或名称 |

### term 命令

| 参数 | 简写 | 说明 |
|------|------|------|
| instance_id | - | 实例ID（位置参数） |
| --region | -r | 区域代码或名称 |
| --force | -f | 强制终止，不确认 |

## 支持的加密方式

- `chacha20-ietf-poly1305` (推荐，默认)
- `aes-256-gcm`
- `aes-128-gcm`
- `aes-256-cfb`

## 区域名称映射

可以使用简短名称代替区域代码：

| 简短名称 | 区域代码 |
|----------|----------|
| 东京 | ap-northeast-1 |
| 首尔 | ap-northeast-2 |
| 大阪 | ap-northeast-3 |
| 新加坡 | ap-southeast-1 |
| 悉尼 | ap-southeast-2 |
| 香港 | ap-east-1 |
| 美西 | us-west-2 |
| 美东 | us-east-1 |

## 配置文件

配置文件位于项目 `config/` 目录：

- `regions.yaml` - 区域配置（AMI ID、实例类型等）
- `defaults.yaml` - 默认配置（端口、加密方式等）

## 故障排查

### 命令未找到

```bash
# 检查 PATH
echo $PATH

# 手动添加
export PATH=$PATH:/root/bin
```

### AWS 凭证未配置

```bash
aws configure
```

### 区域不支持

检查 `config/regions.yaml` 中是否配置了该区域的 AMI ID。

## 注意事项

1. 终止实例后，数据将永久丢失
2. 请确保安全组规则正确配置
3. 定期检查并清理未使用的资源
