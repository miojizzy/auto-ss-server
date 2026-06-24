# Xray VLESS 客户端配置指南

## 快速获取连接信息

在服务器上运行：

```bash
sudo bash src/xray/show-config.sh
```

或者查看配置文件：

```bash
cat /etc/xray/config.json
sudo journalctl -u xray -n 1
```

## 客户端应用

### 1. Windows / PC 用户

#### V2rayN (推荐)
- 下载：https://github.com/2dust/v2rayN/releases
- 步骤：
  1. 打开 V2rayN
  2. 点击"服务器" → "添加 [VLESS]"
  3. 填写信息：
     - 地址：`your_server_ip`
     - 端口：`your_port` (默认 443)
     - 用户ID (UUID)：`your_uuid`
     - 传输层安全：`tls`
     - 流：`xtls-rprx-vision`
     - 跳过证书验证：`是`
  4. 保存并启用

#### Clash 系列
- Clash for Windows: https://github.com/Fndroid/clash_for_windows_pkg
- ClashX: https://github.com/yichengchen/clashx

配置示例：
```yaml
proxies:
  - name: "Xray"
    type: vless
    server: your_server_ip
    port: your_port
    uuid: your_uuid
    network: tcp
    tls: true
    flow: xtls-rprx-vision
    servername: your_server_ip
    skip-cert-verify: true
```

### 2. macOS 用户

#### V2rayU
- 下载：https://github.com/yanue/v2rayU/releases
- 配置同 V2rayN

#### Clash
- ClashX：https://github.com/yichengchen/clashx/releases
- Clash for Windows (也支持 macOS)

### 3. iOS / iPad 用户

#### Shadowrocket (小火箭) - 推荐
- App Store 购买：https://apps.apple.com/us/app/shadowrocket/id932747118

配置步骤：
1. 打开 Shadowrocket
2. 点击"+"或"扫描"
3. 选择"VLESS"
4. 填写信息：
   - 服务器：`your_server_ip`
   - 端口：`your_port`
   - UUID：`your_uuid`
   - 传输方式：TCP
   - TLS：开启
   - 流：`xtls-rprx-vision`
   - 允许不安全连接：开启
5. 点击"保存"

或直接导入 VLESS 链接：
```
vless://uuid@server_ip:port?security=tls&flow=xtls-rprx-vision&type=tcp&allowInsecure=1
```

#### Quantumult X
- App Store 购买

配置示例：
```
vless = server_ip:port, method=none, password=uuid, obfs=off, tls13=1, tag=Xray
```

#### Surge
- 支持导入 VLESS URI

### 4. Android 用户

#### V2rayNG - 推荐
- 下载：https://github.com/2dust/v2rayNG/releases

配置步骤：
1. 打开 V2rayNG
2. 点击"+"
3. 选择"手动输入"
4. 填写信息：
   - 协议：VLESS
   - 地址：`your_server_ip`
   - 端口：`your_port`
   - ID (UUID)：`your_uuid`
   - 传输：tcp
   - 安全：tls
   - 流：`xtls-rprx-vision`
   - SNI：`your_server_ip`
   - 跳过证书验证：开启
5. 保存

#### Clash for Android
- 下载：https://github.com/Kr328/ClashForAndroid/releases

### 5. Linux 用户

#### 一键安装（REALITY，推荐）

在客户端 Linux 机器上执行（自动检测架构、装为 systemd 服务、本地 SOCKS5 1080）：

```bash
# 方式 A：参数传链接
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/xray-client-install.sh \
  | sudo bash -s -- "vless://uuid@ip:port?security=reality&pbk=...&sid=...&sni=...&flow=xtls-rprx-vision&type=tcp"

# 方式 B：环境变量传链接
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/xray-client-install.sh \
  | sudo VLESS_LINK="vless://..." bash
```

链接从服务器 `sudo bash src/xray/show-config.sh` 获取。

安装后本地 SOCKS5 代理在 `127.0.0.1:1080`，测试：

```bash
curl -x socks5h://127.0.0.1:1080 https://ipinfo.io/ip   # 应显示服务器 IP
```

管理 / 卸载：

```bash
sudo systemctl status xray-client
sudo journalctl -u xray-client -f
sudo bash xray-client-install.sh uninstall
```

## 分享链接导入

### 方式 1: 使用分享链接
大多数客户端都支持直接扫描或导入 VLESS 链接：

```
vless://UUID@SERVER_IP:PORT?security=tls&flow=xtls-rprx-vision&type=tcp&allowInsecure=1
```

### 方式 2: 二维码
可以使用在线工具生成二维码，然后用手机客户端扫描。

## 连接测试

配置完成后，测试连接：

```bash
# 访问国外网站
curl -I https://google.com

# 或者用 wget
wget --spider https://google.com

# 检查 IP 是否改变
curl https://ipinfo.io/ip
```

## 常见问题

### 连接失败

1. **检查服务器状态**
```bash
sudo systemctl status xray
sudo journalctl -u xray -n 50
```

2. **检查端口是否开放**
```bash
sudo ss -tlnp | grep xray
```

3. **检查防火墙**
```bash
sudo ufw status
# 确保 PORT/tcp 已开放
sudo ufw allow PORT/tcp
```

### 流量缓慢

1. 检查服务器网络状况
2. 尝试更换客户端
3. 检查 ISP 是否有限制

### 客户端无法连接

1. 确认 UUID、地址、端口是否正确
2. 确认跳过证书验证选项已启用
3. 检查客户端日志
4. 尝试更换传输方式（如改用 TCP）

## 配置参数说明

| 参数 | 说明 | 示例 |
|------|------|------|
| 协议 | VLESS | vless |
| 地址 | 服务器 IP 或域名 | 1.2.3.4 |
| 端口 | 服务器端口 | 443, 8443 等 |
| UUID | 用户 ID | (从服务器获取) |
| 传输 | TCP / UDP | tcp |
| 安全 | TLS / XTLS | tls |
| 流 | Flow 参数 | xtls-rprx-vision |
| SNI | 服务器名称指示 | 服务器 IP |
| 跳过证书验证 | 自签证书需要启用 | 是 |

## 推荐客户端

| 平台 | 应用 | 推荐度 |
|------|------|--------|
| Windows | V2rayN | ⭐⭐⭐⭐⭐ |
| macOS | V2rayU / ClashX | ⭐⭐⭐⭐ |
| iOS | Shadowrocket | ⭐⭐⭐⭐⭐ |
| Android | V2rayNG | ⭐⭐⭐⭐⭐ |
| Linux | Xray CLI | ⭐⭐⭐⭐ |

## 更新日志

- 2026-06-17：支持自定义端口和 VLESS 协议
