# WireGuard 分流指南

让 xray 转发的流量走 WireGuard → Surfshark 出口，SSH 和 xray 入站不受影响。

## 前置条件

- 已安装 xray server.sh（xray 以 `xrayuser` 用户运行）
- 有 Surfshark WireGuard 配置文件（从 https://my.surfshark.com → Manual setup → WireGuard 获取）

## 快速安装

### 方法 1: 直接运行（推荐）

```bash
# 先上传 Surfshark 配置文件到 EC2
# 然后执行安装
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/wg/wg.sh | sudo bash -s install /path/to/wg0.conf
```

### 方法 2: 下载后运行

```bash
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/wg/wg.sh -o wg.sh
sudo bash wg.sh install /path/to/wg0.conf
```

## 管理命令

```bash
# 查看分流状态
sudo bash wg.sh status

# 启动分流
sudo bash wg.sh enable

# 停止分流（回滚到直连，xray 不受影响）
sudo bash wg.sh disable

# 卸载（-y 跳过确认）
sudo bash wg.sh uninstall -y
```

## 原理

```
客户端 → eth0:443 → xray 解密 → [新连接] → wg0 → Surfshark → 互联网
                                                    ↓
                                              返回流量 → wg0 → xray 加密 → eth0:443 → 客户端
```

- `Table = off`：WireGuard 不改主路由表，SSH 不断
- `xrayuser` 发起的新连接被 iptables 标记 fwmark 1
- fwmark 1 的包走 surfshark 路由表 → wg0
- SSH 和 xray 入站走 eth0，不受影响

## 安装内容

| 文件 | 说明 |
|------|------|
| `/etc/wireguard/wg0.conf` | WireGuard 配置（Table=off, MTU=1280） |
| `/etc/wireguard/iprules.sh` | iptables 规则脚本（enable/disable） |
| `/etc/systemd/system/wg-split.service` | systemd 服务 |
| `/etc/iproute2/rt_tables` | 追加路由表 `100 surfshark` |

## 卸载内容

- systemd 服务：`wg-split.service`
- WireGuard 配置：`/etc/wireguard/`
- iptables 规则（自动清理）
- 路由表条目（自动清理）

> wireguard 软件包不删除，xray 服务不受影响，xrayuser 用户不删除。

## 故障排查

### SSH 断了

不会发生（Table=off 保证）。如果真的断了，销毁 EC2 重建即可。

### 分流未生效

```bash
# 检查 wg0 是否存在
ip link show wg0

# 检查 iptables 标记规则
iptables -t mangle -L OUTPUT -n | grep xrayuser

# 检查路由规则
ip rule list | grep surfshark

# 检查 wg 出口 IP
curl --interface wg0 http://ip.sb

# 查看服务日志
journalctl -u wg-split -n 20
```

### 更换 Surfshark 服务器

```bash
# 停止分流
sudo bash wg.sh disable

# 替换配置文件后重新安装
sudo bash wg.sh install /path/to/new-wg0.conf
```

## 注意事项

- 需要先安装 xray server.sh（依赖 xrayuser 用户）
- MTU 固定 1280，避免分片
- WireGuard 配置中 `AllowedIPs = 0.0.0.0/0` 但因 `Table = off` 不会影响主路由
- `PersistentKeepalive = 25` 保持隧道不断
