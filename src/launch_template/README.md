# 启动模板管理模块

创建和管理 AWS EC2 启动模板，用于快速部署 Shadowsocks 服务器实例。

## 设计理念

### 通用模板设计

传统方式将端口、密码、加密方式等配置硬编码在启动模板中，导致：

- 每次修改配置需要重新创建模板
- 无法在同一模板下部署不同配置的实例
- 管理复杂度高

本模块采用**通用模板 + 动态配置**的设计：

```
┌─────────────────────────────────────────────────────────────┐
│                     启动模板 (通用)                          │
├─────────────────────────────────────────────────────────────┤
│  包含内容:                                                   │
│  - AMI ID (区域相关)                                         │
│  - 实例类型 (可覆盖)                                          │
│  - 安全组 ID                                                 │
│  - 基础 User Data (占位符)                                   │
│                                                             │
│  不包含:                                                     │
│  - 端口配置                                                  │
│  - 密码                                                     │
│  - 加密方式                                                  │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  运行时配置覆盖                              │
├─────────────────────────────────────────────────────────────┤
│  awsl run 命令执行时:                                        │
│  1. 根据参数生成 Shadowsocks 配置                            │
│  2. 生成 User Data 脚本 (base64)                            │
│  3. 调用 run-instances API 覆盖 User Data                   │
└─────────────────────────────────────────────────────────────┘
```

## 安装

```bash
./setup.sh launch_template
```

或：

```bash
cd src/launch_template
./init_template.sh --region ap-northeast-1
```

## 使用方法

### 创建启动模板

```bash
# 基本用法
./init_template.sh --region ap-northeast-1

# 指定模板名称
./init_template.sh -r ap-northeast-1 -n my-template

# 指定 AMI ID
./init_template.sh -r ap-northeast-1 --ami-id ami-xxxxx

# 指定实例类型
./init_template.sh -r ap-northeast-1 -t t3.micro
```

### 删除启动模板

```bash
./init_template.sh --region ap-northeast-1 --delete
```

## 命令行参数

| 参数 | 简写 | 说明 | 示例 |
|------|------|------|------|
| --region | -r | AWS 区域代码 | `-r ap-northeast-1` |
| --name | -n | 模板名称 | `-n my-template` |
| --ami-id | - | AMI ID | `--ami-id ami-xxxxx` |
| --instance-type | -t | 实例类型 | `-t t3.micro` |
| --delete | - | 删除模式 | `--delete` |
| --help | -h | 显示帮助 | `--help` |

## 安全组配置

自动创建的安全组包含以下规则：

| 端口 | 协议 | 说明 |
|------|------|------|
| 22 | TCP | SSH 访问 |
| -1 | ICMP | Ping |
| 9091 | TCP | Prometheus Metrics |
| 用户指定 | TCP/UDP | Shadowsocks (运行时添加) |

## 文件说明

```
src/launch_template/
├── init_template.sh       # 模板创建/删除脚本
└── README.md              # 本文档
```

## 与 awsl 的配合

启动模板通常不需要单独管理，`awsl` 工具会自动处理：

```bash
# awsl 会自动创建模板（如果不存在）
awsl run -r ap-northeast-1 -p 2333:mypass

# 查看和管理模板
awsl template list
awsl template create -r ap-northeast-1
awsl template delete -r ap-northeast-1
```

## 注意事项

1. **AMI ID 区域相关性**: 每个 AWS 区域的 AMI ID 不同，模板是区域级别的资源
2. **模板覆盖**: 创建同名模板会覆盖已有模板
3. **安全组依赖**: 删除模板时不会自动删除安全组
4. **权限要求**: 需要 EC2 相关 IAM 权限

## 故障排查

### AMI ID 未找到

```
错误: 无法获取 AMI ID
```

解决方案：
- 检查 `config/regions.yaml` 中是否配置了该区域
- 使用 `--ami-id` 参数手动指定

### 安全组创建失败

```
错误: SecurityGroupAlreadyExists
```

解决方案：
- 安全组名称已存在，脚本会自动复用
- 或删除现有安全组后重试

### 权限不足

```
错误: UnauthorizedOperation
```

解决方案：
- 检查 AWS IAM 权限
- 确保有 `ec2:*` 相关权限
