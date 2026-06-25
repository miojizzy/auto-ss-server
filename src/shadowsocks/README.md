# Shadowsocks 模块

基于 [outline-ss-server](https://github.com/Jigsaw-Code/outline-ss-server) 的 Shadowsocks 服务端，编译为二进制并以 systemd 托管；并提供 Linux 一键客户端（基于 [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust) 的 `sslocal`）。

脚本结构与 `src/xray/` 一致：`server.sh` / `client.sh`，均以子命令区分操作。

## 服务端 server.sh

### 快速开始（curl|bash）

```bash
# 默认随机端口 + 随机密码
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/shadowsocks/server.sh \
  | sudo bash -s install

# 指定端口（自动随机密码）
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/shadowsocks/server.sh \
  | sudo bash -s install 8388

# 指定端口和密码
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/shadowsocks/server.sh \
  | sudo bash -s install 8388:mypassword
```

### 本地脚本

```bash
sudo bash src/shadowsocks/server.sh install 8388:mypassword
sudo bash src/shadowsocks/server.sh config       # 查看连接信息 / ss:// 链接
sudo bash src/shadowsocks/server.sh uninstall -y # 卸载（-y 跳过确认）
```

### 子命令

| 命令 | 说明 |
|------|------|
| `install [端口[:密码]]` | 安装并启动服务端（默认随机端口 + 随机密码） |
| `uninstall [-y]` | 卸载（`-y` 跳过确认） |
| `config` | 显示连接信息 / `ss://` 分享链接 |
| `status` | 查看服务状态 |
| `start` / `stop` / `restart` | 服务控制 |
| `logs` | 查看实时日志（systemd） |
| `help` | 显示帮助 |

可选环境变量：`SS_METHOD`（默认 `chacha20-ietf-poly1305`）、`METRICS_PORT`（默认 `9091`）。

### 支持的加密方式

- `chacha20-ietf-poly1305` (推荐)
- `aes-128-gcm`
- `aes-256-gcm`
- `2022-blake3-aes-128-gcm`
- `2022-blake3-aes-256-gcm`

## 客户端 client.sh（Linux）

在客户端 Linux 机器上安装，自动检测架构、装为 systemd 服务、本地 SOCKS5 `127.0.0.1:1080`。

```bash
# 参数传链接
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/shadowsocks/client.sh \
  | sudo bash -s install "ss://..."

# 环境变量传链接
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/shadowsocks/client.sh \
  | sudo SS_LINK="ss://..." bash -s install

# 本地脚本
sudo bash src/shadowsocks/client.sh install "ss://..."
```

链接从服务端 `sudo bash src/shadowsocks/server.sh config` 获取。安装后测试：

```bash
curl -x socks5h://127.0.0.1:1080 https://ipinfo.io/ip   # 应显示服务器 IP
```

### 子命令

| 命令 | 说明 |
|------|------|
| `install "ss://..."` | 安装本地 SOCKS5 代理（也可用 `SS_LINK` 环境变量） |
| `uninstall` | 卸载客户端 |
| `status` | 查看服务状态 |
| `logs` | 查看实时日志 |
| `help` | 显示帮助 |

## 服务管理

```bash
# 服务端
sudo systemctl status shadowsocks
sudo journalctl -u shadowsocks -f

# 客户端
sudo systemctl status shadowsocks-client
sudo journalctl -u shadowsocks-client -f
```

## 文件说明

```
src/shadowsocks/
├── server.sh    # 服务端（outline-ss-server + systemd，子命令分发）
├── client.sh    # Linux 客户端（sslocal SOCKS5，子命令分发）
└── README.md    # 本文档
```

> 注：本模块与 `src/ssserver/`（旧版 Outline 安装脚本）相互独立，仅新增、不影响后者。
