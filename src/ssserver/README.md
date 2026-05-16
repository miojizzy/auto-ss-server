# Shadowsocks 服务器模块

在 EC2 实例上自动安装和配置 Outline Shadowsocks 服务器。

## 快速开始（curl|bash）

```bash
# 单端口
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/ssserver/install_outline.sh \
  | bash -s -- -p 2333:mypassword

# 多端口
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/ssserver/install_outline.sh \
  | bash -s -- -p 2333:pass1 -p 2334:pass2

# 指定加密方式
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/ssserver/install_outline.sh \
  | bash -s -- -p 2333:mypassword -m aes-256-gcm
```

## 命令行参数

| 参数 | 简写 | 说明 | 默认值 |
|------|------|------|--------|
| --port PORT:PASS | -p | 端口:密码（可重复） | 2333:change_me_password |
| --method | -m | 加密方式 | chacha20-ietf-poly1305 |
| --metrics-port | - | Metrics 端口 | 9091 |
| --help | -h | 显示帮助 | - |

## 支持的加密方式

- `chacha20-ietf-poly1305` (推荐)
- `aes-128-gcm`
- `aes-256-gcm`
- `2022-blake3-aes-128-gcm`
- `2022-blake3-aes-256-gcm`

## 服务管理

```bash
# 查看状态
ps aux | grep outline-ss-server

# 查看日志
tail -f /var/log/outline_ssserver.log

# 停止服务
pkill -f outline-ss-server
```


## 文件说明

```
src/ssserver/
├── install_outline.sh   # Outline 一键安装脚本（curl|bash）
├── legacy/              # 旧版脚本（已归档）
│   ├── init_instance.sh
│   └── init_outline_ssserver.sh
└── README.md            # 本文档
```

