# Xray 改用 REALITY 替换自签证书 — 设计文档

日期：2026-06-24

## 背景与目标

当前 `xray-install.sh` 使用 openssl 生成 RSA 自签证书，TLS 模式运行，客户端必须 `allowInsecure=1` 跳过证书校验。改为 **REALITY**：无需证书，服务器握手时借用真实大站（默认 `www.microsoft.com`）的证书指纹，客户端不再需要 `allowInsecure`，抗封锁更强。

**决策**：直接替换自签方案（不并存）；伪装目标内置默认 `www.microsoft.com:443`；安装/显示配置/管理三个脚本同步改；REALITY 公钥等参数持久化到 `/etc/xray/reality.env`。

## 受影响文件

- `src/xray/xray-install.sh` — 移除证书生成，改为生成 REALITY 密钥 + 写 env
- `src/xray/show-config.sh` — 读 env 生成 REALITY 分享链接
- `src/xray/xray-manage.sh` — `info` 命令读 env 生成 REALITY 分享链接
- `src/xray/xray-uninstall.sh` — 删除整 `/etc/xray` 已覆盖 env，无功能改动
- `XRAY_INSTALL.md` / `README.md` — 文档措辞从"自签证书"改为"REALITY"

## 安装脚本 (xray-install.sh) 改动

阶段顺序调整为：下载安装 Xray → 生成 UUID → 获取公网 IP → **生成 REALITY 密钥** → 写配置。`xray x25519` 必须在 Xray 二进制就绪后调用。

| 阶段 | 原（自签） | 改为（REALITY） |
|------|-----------|----------------|
| 获取 IP | 公网 IP 探测 | 不变 |
| 证书 | openssl 生成 RSA 自签 | 删除 |
| 密钥 | — | `xray x25519` 生成 x25519 密钥对 |
| shortId | — | `openssl rand -hex 8` |
| streamSettings | `security: tls` + 证书路径 | `security: reality` + realitySettings |
| 持久化 | — | 写 `/etc/xray/reality.env`（600 权限） |

默认参数：dest = `www.microsoft.com:443`，serverName = `www.microsoft.com`，fingerprint = `chrome`。

### 密钥解析容错

`xray x25519` 输出在不同版本字段名不同（旧版 `Private key:` / `Public key:`，新版 `PrivateKey:` / `Password:`）。用 grep 容错提取私钥和公钥，任一提取为空则报错退出。

## config.json 结构

inbounds 的 vless / clients / `flow=xtls-rprx-vision` 保持不变。streamSettings 替换为：

```json
"streamSettings": {
  "network": "tcp",
  "security": "reality",
  "realitySettings": {
    "show": false,
    "dest": "www.microsoft.com:443",
    "xver": 0,
    "serverNames": ["www.microsoft.com"],
    "privateKey": "<x25519 私钥>",
    "shortIds": ["<8字节 hex>"]
  }
}
```

## /etc/xray/reality.env

```
XRAY_PORT=443
XRAY_UUID=xxxx
PUBLIC_KEY=xxxx
SHORT_ID=xxxx
SERVER_NAME=www.microsoft.com
SERVER_IP=1.2.3.4
```

权限 600。show-config / manage 读取此文件生成链接，IP 以 env 中保存的（安装时探测的公网 IP）为准。

## 分享链接格式（三脚本统一）

```
vless://<uuid>@<ip>:<port>?security=reality&encryption=none&pbk=<公钥>&sid=<shortId>&sni=www.microsoft.com&fp=chrome&flow=xtls-rprx-vision&type=tcp#xray-reality
```

## show-config.sh / xray-manage.sh (info)

改为优先读 `/etc/xray/reality.env` 取全部参数，按上面格式拼链接，不再用 `grep port/id` + 运行时 IP 探测。若 env 不存在 → 提示"未检测到 REALITY 配置，请重新运行安装脚本"并退出。

## 错误处理

- `xray x25519` 在 Xray 安装完成后调用；密钥提取失败则退出。
- `reality.env` 权限 600。
- show-config / manage info：env 缺失给出明确提示。

## 文档

- `XRAY_INSTALL.md`：脚本特性、注意事项、客户端说明把"自签证书 / allowInsecure"改为"REALITY 无需证书"。
- `README.md`：Xray 章节描述从"自签证书 + IP"改为"REALITY"。

## 测试

- 三脚本 `bash -n` 语法检查。
- 用样例 `xray x25519` 输出（新旧两种格式）验证密钥解析 grep 逻辑。
- 人工核对分享链接字段齐全。
- 真实端到端连接需在实际服务器验证 —— 本环境无法运行安装，交付时会明确标注此点。

## 不做的事（YAGNI）

- 不保留自签证书并存模式。
- 不支持安装时交互选择 dest（curl|bash 管道无法交互）。
- 不做 dest 自定义环境变量（用户确认用内置默认即可）。
