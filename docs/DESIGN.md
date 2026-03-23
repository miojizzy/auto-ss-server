# auto_ssserver 重构设计文档

## 1. 项目概述

本项目是一个 AWS EC2 自动化 Shadowsocks 代理服务器管理工具，支持快速部署、多区域选择、动态配置等功能。

## 2. 项目结构

```
/workspace/
├── README.md                      # 项目总览
├── setup.sh                       # 统一安装入口
├── config/                        # 全局配置
│   ├── regions.yaml               # 区域配置（镜像ID、默认实例类型等）
│   └── defaults.yaml              # 默认配置（端口、加密方式等）
├── docs/                          # 详细文档
│   ├── awsl.md                    # awsl 工具文档
│   ├── launch_template.md         # 启动模板文档
│   ├── ssserver.md                # Shadowsocks 部署文档
│   └── crontab.md                 # 定时任务文档
└── src/                           # 源代码
    ├── awsl/                      # AWS 简化命令行工具
    │   ├── awsl                   # 主程序
    │   ├── init.sh
    │   └── README.md
    ├── launch_template/           # 启动模板管理
    │   ├── template_manager.py    # 模板管理器
    │   ├── init_template.sh
    │   ├── user_data_generator.py # User Data 动态生成
    │   └── README.md
    ├── ssserver/                  # Shadowsocks 服务
    │   ├── init_instance.sh
    │   ├── init_outline_ssserver.sh
    │   └── README.md
    └── crontab/                   # 定时任务
        ├── update.sh
        ├── conf
        └── README.md
```

## 3. 核心改进设计

### 3.1 通用启动模板（动态配置）

**原问题**：端口、加密方式等配置硬编码在启动模板中，无法在部署时修改。

**解决方案**：

```
┌─────────────────────────────────────────────────────────────┐
│                      启动流程                                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  用户命令                                                    │
│  awsl run --region ap-northeast-1 \                         │
│           --ports 2333:password1,2334:password2 \           │
│           --method chacha20-ietf-poly1305                   │
│                        │                                    │
│                        ▼                                    │
│  ┌─────────────────────────────────────┐                    │
│  │   user_data_generator.py            │                    │
│  │   - 生成动态 User Data (base64)      │                    │
│  │   - 包含端口、密码、加密方式配置       │                    │
│  └─────────────────────────────────────┘                    │
│                        │                                    │
│                        ▼                                    │
│  ┌─────────────────────────────────────┐                    │
│  │   run-instances API 调用             │                    │
│  │   - 使用通用启动模板                  │                    │
│  │   - 覆盖 User Data                   │                    │
│  │   - 覆盖 Instance Type（可选）        │                    │
│  └─────────────────────────────────────┘                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**通用模板特点**：
- 不包含任何业务配置
- 只定义基础架构（安全组规则模版）
- User Data 在启动时动态注入

### 3.2 多区域支持

**区域配置文件** (`config/regions.yaml`)：

```yaml
regions:
  ap-northeast-1:  # 东京
    name: "东京"
    ami_id: "ami-0fe22bffdec36361c"
    default_instance_type: "t2.nano"
    key_name: "ap-northeast-1"
    
  ap-northeast-2:  # 首尔
    name: "首尔"
    ami_id: "ami-0c55b159cbfafe1f0"
    default_instance_type: "t2.nano"
    key_name: "ap-northeast-2"
    
  ap-southeast-1:  # 新加坡
    name: "新加坡"
    ami_id: "ami-0b84c2d3cb9fa32d8"
    default_instance_type: "t2.nano"
    key_name: "ap-southeast-1"
    
  us-west-2:  # 俄勒冈
    name: "美西"
    ami_id: "ami-0abcdef1234567890"
    default_instance_type: "t2.nano"
    key_name: "us-west-2"
    
  eu-west-1:  # 爱尔兰
    name: "欧洲"
    ami_id: "ami-0fedcba0987654321"
    default_instance_type: "t2.nano"
    key_name: "eu-west-1"
```

### 3.3 命令行接口设计

#### awsl 工具新接口

```bash
# 创建实例
awsl run [options]
  --region, -r        区域代码或名称 (如: ap-northeast-1 或 "东京")
  --ports, -p         端口配置，格式: port:password,port:password
                      示例: 2333:mypass1,2334:mypass2
  --method, -m        加密方式 (默认: chacha20-ietf-poly1305)
  --instance-type, -t 实例类型 (默认: t2.nano)
  --template, -T      启动模板名 (默认: auto_ss)
  --name, -n          实例名称标签

# 查看实例
awsl desc [--region REGION]

# 终止实例
awsl term <instance-id> [--region REGION]

# 列出可用区域
awsl regions

# 查看当前配置
awsl config
```

#### 示例用法

```bash
# 在东京区域创建实例，使用默认配置
awsl run -r ap-northeast-1

# 在新加坡创建实例，自定义端口和密码
awsl run -r singapore \
         -p 8388:mySecretPass123,8389:anotherPass456 \
         -m aes-256-gcm

# 查看所有区域
awsl regions

# 查看指定区域的实例
awsl desc -r ap-northeast-1

# 终止实例
awsl term i-0abc123def456
```

### 3.4 User Data 动态生成

**生成流程**：

```python
def generate_user_data(ports_config, method, server_type="outline"):
    """
    生成 Shadowsocks 配置并编码为 User Data
    
    Args:
        ports_config: [(port, password), ...]
        method: 加密方式
        server_type: "outline" 或 "python"
    
    Returns:
        base64 编码的 User Data
    """
    if server_type == "outline":
        config = generate_outline_config(ports_config, method)
    else:
        config = generate_python_ss_config(ports_config, method)
    
    script = f"""#!/bin/bash
mkdir -p /data
cd /data

# 写入配置
cat > /data/ss_config.yml << 'SSCONFIGEOF'
{config}
SSCONFIGEOF

# 安装并启动服务
{get_install_script(server_type)}
"""
    return base64.b64encode(script.encode()).decode()
```

### 3.5 安全组动态管理

由于不同端口配置需要不同的安全组规则，改为：

1. **创建通用安全组模板**：只包含基础规则（SSH、ICMP、监控端口）
2. **运行时动态添加规则**：根据用户指定的端口自动添加入站规则
3. **实例终止时清理**：可选清理不再使用的安全组规则

## 4. 模块详细设计

### 4.1 awsl 模块

**文件**: `src/awsl/awsl`

```python
#!/usr/bin/env python3
"""
AWS EC2 Shadowsocks 实例管理工具

子命令:
  run       创建并启动新实例
  desc      描述现有实例
  term      终止实例
  regions   列出可用区域
  config    显示当前配置
"""

import argparse
import yaml
import json
from pathlib import Path

# ... 详细实现见 src/awsl/awsl
```

### 4.2 launch_template 模块

**文件**: `src/launch_template/template_manager.py`

负责：
- 创建/更新/删除启动模板
- 管理区域相关的 AMI ID
- 生成通用模板结构

### 4.3 user_data_generator 模块

**文件**: `src/launch_template/user_data_generator.py`

负责：
- 解析用户传入的端口配置
- 生成 Outline/Python SS 配置
- 生成安装脚本
- Base64 编码输出

## 5. 配置优先级

```
命令行参数 > 区域配置 > 默认配置
```

示例：
- 用户指定 `--method aes-256-gcm` → 使用指定值
- 用户未指定，检查区域默认 → 使用区域默认值
- 区域未配置 → 使用全局默认值

## 6. 文档结构

每个模块的 README.md 包含：

1. **功能说明**：该模块的作用
2. **依赖关系**：需要的前置条件
3. **安装方法**：如何安装
4. **使用示例**：常见用法
5. **参数说明**：详细参数列表
6. **注意事项**：常见问题和限制
7. **故障排查**：问题诊断方法

## 7. 兼容性考虑

- 支持 Python 3.6+
- 兼容原项目的命令格式（可选）
- 配置文件同时支持 YAML 和 JSON

## 8. 后续扩展

预留扩展点：
- 支持更多云服务商（GCP、Azure）
- 支持 WireGuard 协议
- 支持 VLESS/VMess 协议
- Web 管理界面
