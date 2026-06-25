# Xray VLESS 安装指南

## 快速安装

> 服务端脚本 `server.sh` 以子命令区分操作：`install` / `uninstall` / `config` / `status` / `restart` 等。

### 方法 1: 直接运行（推荐）

```bash
# 从 GitHub 直接安装
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/server.sh | sudo bash -s install
```

或者使用 wget：

```bash
wget -O - https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/server.sh | sudo bash -s install
```

### 方法 2: 下载后运行

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/server.sh -o server.sh

# 或使用 wget
wget https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/server.sh

# 运行脚本（默认端口 443，可在 install 后跟端口）
sudo bash server.sh install
sudo bash server.sh install 8443
```

### 方法 3: 使用本地文件

```bash
cd /path/to/auto-ss-server
sudo bash src/xray/server.sh install
```

## 脚本特性

✅ **详细的错误输出** - 任何步骤失败都会显示具体错误信息
✅ **网络诊断** - 自动检查网络连接和 DNS
✅ **代理支持** - 支持 HTTP/HTTPS 代理
✅ **幂等性** - 可以安全地重复运行
✅ **自动清理** - 失败时显示具体错误
✅ **REALITY 协议** - 借用真实大站 TLS 指纹，无需证书，抗封锁更强

## 故障排查

### 1. 网络连接失败

```bash
# 检查 DNS
nslookup github.com
ping 8.8.8.8

# 如果需要代理
export HTTP_PROXY=http://proxy:port
export HTTPS_PROXY=http://proxy:port
```

### 2. 权限不足

确保使用 `sudo` 运行：

```bash
sudo bash server.sh install
# 或
curl -fsSL ... | sudo bash -s install
```

### 3. 检查日志

安装完成后查看日志：

```bash
# 实时日志
sudo journalctl -u xray -f

# 错误日志
sudo tail -f /var/log/xray/error.log

# 访问日志
sudo tail -f /var/log/xray/access.log
```

## 管理命令

`server.sh` 内置常用管理子命令：

```bash
# 查看服务状态
sudo bash src/xray/server.sh status

# 重启 / 停止 / 启动服务
sudo bash src/xray/server.sh restart
sudo bash src/xray/server.sh stop
sudo bash src/xray/server.sh start

# 查看连接信息 / VLESS 分享链接
sudo bash src/xray/server.sh config

# 实时日志 / 错误日志 / 访问日志
sudo bash src/xray/server.sh logs
sudo bash src/xray/server.sh error
sudo bash src/xray/server.sh access

# 测试 / 重载配置
sudo bash src/xray/server.sh test
sudo bash src/xray/server.sh reload
```

> 也可直接使用 systemd：`sudo systemctl status xray`、`sudo systemctl restart xray`。

## 卸载

在已安装的机器上运行卸载子命令，会停止服务并删除程序、配置、日志及防火墙规则：

```bash
# 交互式确认后卸载
sudo bash src/xray/server.sh uninstall

# 跳过确认直接卸载
sudo bash src/xray/server.sh uninstall -y
```

卸载内容：

- systemd 服务：`/etc/systemd/system/xray.service`
- 程序目录：`/usr/local/Xray`
- 配置目录：`/etc/xray`
- 日志目录：`/var/log/xray`
- 相关防火墙规则（如使用 UFW）

> 安装时装的依赖（`curl wget unzip uuid-runtime openssl`）为系统常用工具，不会被删除。

## 环境变量

```bash
# 设置代理
export HTTP_PROXY=http://proxy:port
export HTTPS_PROXY=http://proxy:port

# 然后运行脚本
curl -fsSL ... | sudo bash
```

## 注意事项

⚠️ 脚本必须以 root 身份运行
⚠️ 会覆盖 `/etc/xray/config.json`
⚠️ 使用 REALITY 协议，无需证书，客户端无需 allowInsecure
⚠️ 默认伪装目标 www.microsoft.com:443
⚠️ 需要有效的网络连接和 DNS

## 支持

如遇问题，请检查：
1. 网络连接
2. DNS 设置
3. 防火墙规则
4. 系统日志
