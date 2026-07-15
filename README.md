# auto_ssserver

AWS EC2 自动化 Shadowsocks 代理服务器管理工具。

## 功能特点

- 🚀 **快速部署**: 一键创建 EC2 实例并配置 Shadowsocks
- 🌍 **多区域支持**: 支持全球多个 AWS 区域
- ⚙️ **动态配置**: 运行时指定端口、密码、加密方式
- 🔄 **自动切换**: IP 质量检测与自动切换
- 📦 **模块化设计**: 各组件独立，按需安装

## 项目结构

```
auto_ssserver/
├── setup.sh                   # 统一安装入口
├── config/                    # 配置文件
│   ├── regions.yaml           # 区域配置
│   └── defaults.yaml          # 默认配置
├── docs/                      # 文档
│   ├── DESIGN.md              # 设计文档
│   ├── awsl.md                # awsl 工具文档
│   ├── launch_template.md     # 启动模板文档
│   ├── ssserver.md            # Shadowsocks 文档
│   └── crontab.md             # 定时任务文档
└── src/                       # 源代码
    ├── awsl/                  # AWS 管理工具
    ├── launch_template/       # 启动模板管理
    ├── ssserver/              # Shadowsocks 服务（旧版 Outline 安装脚本）
    ├── shadowsocks/           # Shadowsocks 一键部署（server.sh / client.sh）
    ├── xray/                  # Xray VLESS 一键部署（server.sh / client.sh）
    └── crontab/               # 定时任务
```

## 快速开始

### 1. 安装

在 AWS CloudShell 或本地 Linux 环境执行：

```bash
# 克隆项目
git clone <repository-url>
cd auto_ssserver

# 安装 awsl 工具
./setup.sh awsl

# 安装 AWS CLI（如果未安装）
./setup.sh aws

# 配置 AWS 凭证
aws configure
```

### 2. 创建启动模板

```bash
# 在东京区域创建启动模板
./setup.sh template -r ap-northeast-1
```

### 3. 创建实例

```bash
# 使用默认配置
awsl run -r ap-northeast-1

# 自定义端口和密码
awsl run -r tokyo -p 2333:myPassword123

# 多端口配置
awsl run -r singapore -p 2333:pass1,2334:pass2

# 自定义加密方式
awsl run -r us-west-2 -p 8388:mypass -m aes-256-gcm
```

### 4. 查看实例

```bash
# 查看所有实例
awsl desc

# 查看指定区域
awsl desc -r ap-northeast-1
```

### 5. 终止实例

```bash
awsl term i-0abc123def456
```

## 命令速查

### awsl 工具

| 命令 | 说明 | 示例 |
|------|------|------|
| `run` | 创建实例 | `awsl run -r tokyo -p 2333:mypass` |
| `desc` | 查看实例 | `awsl desc` |
| `term` | 终止实例 | `awsl term i-xxx` |
| `regions` | 列出区域 | `awsl regions` |
| `config` | 查看配置 | `awsl config` |
| `template` | 管理模板 | `awsl template list` |

### 参数说明

| 参数 | 简写 | 说明 |
|------|------|------|
| `--region` | `-r` | 区域代码或名称 |
| `--ports` | `-p` | 端口配置 `port:pass,port:pass` |
| `--method` | `-m` | 加密方式 |
| `--instance-type` | `-t` | 实例类型 |
| `--name` | `-n` | 实例名称 |

## 支持的区域

| 区域代码 | 名称 | 说明 |
|----------|------|------|
| ap-northeast-1 | 东京 | 低延迟，适合亚洲用户 |
| ap-northeast-2 | 首尔 | 低延迟，适合亚洲用户 |
| ap-southeast-1 | 新加坡 | 低延迟，适合东南亚用户 |
| ap-east-1 | 香港 | 低延迟，适合中国用户 |
| us-west-2 | 美西 | 价格较低 |
| eu-west-1 | 爱尔兰 | 适合欧洲用户 |

完整列表运行 `awsl regions` 查看。

## 支持的加密方式

- `chacha20-ietf-poly1305` (推荐)
- `aes-256-gcm`
- `aes-128-gcm`
- `aes-256-cfb`

## Xray VLESS 服务

在单台服务器上一键部署/卸载 Xray VLESS（REALITY 协议，无需证书），与上面的 AWS 自动化相互独立。脚本以子命令区分操作。

### 一键安装

```bash
# 默认端口 443
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/server.sh | sudo bash -s install

# 自定义端口（如 8443）
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/server.sh | sudo bash -s install 8443

# 使用本地脚本
sudo bash src/xray/server.sh install 8443
```

### 一键卸载

```bash
# 交互式确认后卸载
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/server.sh | sudo bash -s uninstall

# 跳过确认直接卸载
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/server.sh | sudo bash -s uninstall -y

# 使用本地脚本
sudo bash src/xray/server.sh uninstall -y
```

### 查看连接信息

```bash
sudo bash src/xray/server.sh config
```

### Linux 一键客户端

在客户端 Linux 机器上安装（解析分享链接，本地 SOCKS5 1080）：

```bash
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/client.sh \
  | sudo bash -s install "vless://..."
```

### 一键卸载

```bash
# 交互确认后卸载
sudo bash src/xray/client.sh uninstall

# 跳过确认直接卸载
sudo bash src/xray/client.sh uninstall -y
# 或
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/client.sh \
  | sudo bash -s uninstall -y
```

详细说明见 [docs/xray-install.md](docs/xray-install.md)。

## Shadowsocks (Outline) 服务

在单台服务器上一键部署/卸载 Shadowsocks（基于 outline-ss-server，编译二进制 + systemd 托管），脚本结构与 Xray 一致。

### 一键安装 / 卸载 / 查看

```bash
# 安装（默认随机端口 + 随机密码，也可 install 8388:mypass）
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/shadowsocks/server.sh | sudo bash -s install

# 查看连接信息 / ss:// 链接
sudo bash src/shadowsocks/server.sh config

# 卸载
sudo bash src/shadowsocks/server.sh uninstall -y
```

### Linux 一键客户端

```bash
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/shadowsocks/client.sh \
  | sudo bash -s install "ss://..."
```

### 一键卸载

```bash
# 交互确认后卸载
sudo bash src/shadowsocks/client.sh uninstall

# 跳过确认直接卸载
sudo bash src/shadowsocks/client.sh uninstall -y
# 或
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/shadowsocks/client.sh \
  | sudo bash -s uninstall -y
```

详细说明见 [src/shadowsocks/README.md](src/shadowsocks/README.md)。

## 定时任务

配置 IP 自动检测和切换：

```bash
# 编辑配置
vim src/crontab/conf

# 添加 crontab
crontab -e
# 添加: */5 * * * * /path/to/src/crontab/update.sh check
```

详细配置见 [src/crontab/README.md](src/crontab/README.md)。

## 文档

- [设计文档](docs/DESIGN.md)
- [Xray VLESS 安装文档](docs/xray-install.md)
- [客户端配置指南](docs/client-config.md)
- [awsl 工具文档](src/awsl/README.md)
- [启动模板文档](src/launch_template/README.md)
- [Shadowsocks 文档（旧版 Outline）](src/ssserver/README.md)
- [Shadowsocks 一键部署文档](src/shadowsocks/README.md)
- [Xray VLESS 安装文档](docs/xray-install.md)
- [定时任务文档](src/crontab/README.md)

## 前置要求

- Python 3.6+ 或 Python 2.7
- AWS CLI
- jq (JSON 处理)

## IAM 权限

需要的最小权限：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:RunInstances",
                "ec2:TerminateInstances",
                "ec2:DescribeInstances",
                "ec2:DescribeLaunchTemplates",
                "ec2:CreateLaunchTemplate",
                "ec2:DeleteLaunchTemplate",
                "ec2:CreateSecurityGroup",
                "ec2:DeleteSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:DescribeSecurityGroups",
                "ec2:AllocateAddress",
                "ec2:ReleaseAddress",
                "ec2:AssociateAddress",
                "ec2:DisassociateAddress",
                "ec2:DescribeAddresses"
            ],
            "Resource": "*"
        }
    ]
}
```

## 常见问题

### Q: 如何修改默认配置？

编辑 `config/defaults.yaml` 文件。

### Q: 如何添加新区域？

编辑 `config/regions.yaml`，添加区域配置和对应的 AMI ID。

### Q: 支持哪些实例类型？

默认使用 `t2.nano`，可通过 `-t` 参数指定其他类型。

## 注意事项

1. **安全**: 请使用强密码
2. **成本**: 记得终止不用的实例
3. **合规**: 请遵守当地法律法规

## License

MIT License
