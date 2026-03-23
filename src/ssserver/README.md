# Shadowsocks 服务器模块

在 EC2 实例上自动安装和配置 Shadowsocks 服务器。

## 支持的实现

### 1. Outline SS Server (推荐)

基于 Go 语言实现的高性能 Shadowsocks 服务器。

**特点:**
- 性能优异，资源占用低
- 支持多端口和多用户
- 内置 Prometheus metrics
- 支持重放攻击防护
- 活跃维护

**安装:**
```bash
./init_instance.sh outline -p 2333 -k mypassword -m chacha20-ietf-poly1305
```

### 2. Python Shadowsocks

基于 Python 的经典实现。

**特点:**
- 成熟稳定
- 配置简单
- 社区资源丰富

**安装:**
```bash
./init_instance.sh python -p 8388 -k mypassword
```

## 使用方法

### 命令行安装

```bash
# Outline (推荐)
./init_outline_ssserver.sh -p 2333 -k mypassword

# 或使用入口脚本
./init_instance.sh outline -p 2333 -k mypassword
```

### 使用配置文件

```bash
# 先创建配置文件
cat > /data/ss_config.yml << EOF
services:
  - listeners:
      - type: tcp
        address: "[::]:2333"
      - type: udp
        address: "[::]:2333"
    keys:
        - id: user-0
          cipher: chacha20-ietf-poly1305
          secret: mypassword
  - listeners:
      - type: tcp
        address: "[::]:2334"
      - type: udp
        address: "[::]:2334"
    keys:
        - id: user-1
          cipher: chacha20-ietf-poly1305
          secret: anotherpassword
EOF

# 使用配置文件启动
./init_outline_ssserver.sh -c /data/ss_config.yml
```

## 命令行参数

| 参数 | 简写 | 说明 | 默认值 |
|------|------|------|--------|
| --config | -c | 配置文件路径 | /data/ss_config.yml |
| --port | -p | 监听端口 | 2333 |
| --password | -k | 密码 | change_me_password |
| --method | -m | 加密方式 | chacha20-ietf-poly1305 |
| --metrics-port | - | Metrics 端口 | 9091 |
| --help | -h | 显示帮助 | - |

## 支持的加密方式

### Outline SS Server
- `chacha20-ietf-poly1305` (推荐)
- `aes-128-gcm`
- `aes-256-gcm`
- `2022-blake3-aes-128-gcm`
- `2022-blake3-aes-256-gcm`

### Python Shadowsocks
- `aes-256-cfb`
- `aes-128-cfb`
- `chacha20`
- `chacha20-ietf`
- `aes-256-gcm`
- `aes-128-gcm`

## 配置文件格式

### Outline SS Server (YAML)

```yaml
services:
  - listeners:
      - type: tcp
        address: "[::]:2333"
      - type: udp
        address: "[::]:2333"
    keys:
        - id: user-0
          cipher: chacha20-ietf-poly1305
          secret: your_password
```

### Python Shadowsocks (JSON)

```json
{
    "server": "0.0.0.0",
    "server_port": 8388,
    "password": "your_password",
    "timeout": 300,
    "method": "aes-256-cfb"
}
```

## 服务管理

### 查看状态

```bash
ps aux | grep ss-server
ss -tlnp | grep -E "2333|8388"
```

### 查看日志

```bash
# Outline
tail -f /var/log/outline_ssserver.log

# Python
tail -f /var/log/ssserver.log
```

### 重启服务

```bash
# 停止
pkill -f outline-ss-server
pkill -f ssserver

# 启动（重新执行安装脚本或手动启动）
./init_outline_ssserver.sh -c /data/ss_config.yml
```

## 自动启动配置

### Systemd 服务

创建 systemd 服务文件实现开机自启：

```bash
cat > /etc/systemd/system/outline-ss.service << EOF
[Unit]
Description=Outline Shadowsocks Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/go/bin/go run /data/outline-ss-server/cmd/outline-ss-server -config /data/ss_config.yml -metrics 0.0.0.0:9091
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable outline-ss
systemctl start outline-ss
```

## 性能调优

### 内核参数

```bash
# 增加文件描述符限制
ulimit -n 65535

# TCP 调优
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216'
sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216'
```

## 故障排查

### 端口被占用

```bash
# 查看端口占用
ss -tlnp | grep 2333

# 结束占用进程
kill -9 <PID>
```

### 权限问题

```bash
# 确保有执行权限
chmod +x /data/outline-ss-server/cmd/outline-ss-server
```

### Go 环境问题

```bash
# 检查 Go 版本
go version

# 重新设置 PATH
export PATH=$PATH:/usr/local/go/bin
```

## 文件说明

```
src/ssserver/
├── init_instance.sh           # 入口脚本
├── init_outline_ssserver.sh   # Outline 安装脚本
└── README.md                  # 本文档
```

## 注意事项

1. **安全性**: 请修改默认密码
2. **防火墙**: 确保安全组开放了相应端口
3. **资源**: t2.nano 实例可以支持数十个并发连接
4. **日志**: 日志文件会持续增长，建议定期清理
