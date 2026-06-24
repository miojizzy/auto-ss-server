# Linux 一键安装 Xray 客户端 — 设计文档

日期：2026-06-24

## 背景与目标

服务端已用 REALITY。需要一个在任意 Linux 机器上一键把自己变成 Xray **客户端**的脚本：用户传一条 `vless://` 分享链接，脚本解析后生成客户端配置、装成 systemd 服务，本地 `127.0.0.1:1080` 提供 SOCKS5 代理。

**决策**：内核用 Xray（与服务端同一二进制）；传参用 `vless://` 链接；本地只开 SOCKS5(1080)；装为 systemd 服务常驻；架构自动检测；支持 curl|bash 安装，兼容参数(A)与环境变量(B)两种传链接方式。

## 受影响文件

- `src/xray/xray-client-install.sh` — 新建：解析链接 → 生成客户端 config → 装 systemd 服务；含 `uninstall` 子命令
- `CLIENT_CONFIG.md` — Linux 一节改为 REALITY + 一键脚本用法
- `README.md` — Xray 章节补「Linux 一键客户端」入口

## 用法与参数解析

**方式 A：参数传链接**
```bash
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/xray-client-install.sh \
  | sudo bash -s -- "vless://uuid@ip:port?security=reality&pbk=...&sid=...&sni=...&flow=xtls-rprx-vision&type=tcp"
```

**方式 B：环境变量**
```bash
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/xray-client-install.sh \
  | sudo VLESS_LINK="vless://..." bash
```

取链接优先级：`$1` > `$VLESS_LINK`；两者皆空 → 报错退出并打印用法。

**关键约束**：curl|bash 时脚本占用 stdin，不能交互式 `read`，必须从参数或环境变量取链接。

**解析逻辑**（纯 bash + sed/grep，无额外依赖）：
- 去掉 `vless://` 前缀
- `uuid` = `@` 前部分
- `server_ip` = `@` 与 `:` 之间
- `port` = `:` 后到 `?` 之间
- query 参数逐个提取：`pbk`、`sid`、`sni`、`flow`、`fp`、`security`
- `fp` 缺省时默认 `chrome`
- 校验 `security=reality` 且 uuid/ip/port/pbk 非空，否则报错退出并打印链接格式

## 架构检测

`uname -m` 映射：
- `x86_64` → `Xray-linux-64.zip`
- `aarch64` / `arm64` → `Xray-linux-arm64-v8a.zip`
- 其他 → 报错退出

从 GitHub latest release 下载，装到 `/usr/local/Xray/xray`。

## 客户端 config.json（/etc/xray-client/config.json）

```json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 1080,
      "protocol": "socks",
      "settings": { "udp": true }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "<server_ip>",
          "port": <port>,
          "users": [{ "id": "<uuid>", "encryption": "none", "flow": "<flow>" }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "<sni>",
          "fingerprint": "<fp>",
          "publicKey": "<pbk>",
          "shortId": "<sid>"
        }
      }
    }
  ]
}
```

SOCKS5 仅监听 `127.0.0.1`（仅本机使用）。

## 目录隔离

客户端用 `/etc/xray-client/`，与服务端 `/etc/xray/` 完全分开，同机互不干扰。二进制 `/usr/local/Xray/` 共享。

## systemd 服务（xray-client.service）

```ini
[Unit]
Description=Xray Client Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/Xray/xray -c /etc/xray-client/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

装完 `daemon-reload` → `start` → `enable`，验证 `is-active`。

## 卸载子命令

`sudo bash xray-client-install.sh uninstall`：停服务、`disable`、删 `xray-client.service`、`daemon-reload`、删 `/etc/xray-client/`。不删 `/usr/local/Xray`（服务端可能在用）。

## 结尾输出

```
✓ Xray 客户端已启动，SOCKS5 代理: 127.0.0.1:1080

测试连接:
  curl -x socks5h://127.0.0.1:1080 https://www.google.com
  curl -x socks5h://127.0.0.1:1080 https://ipinfo.io/ip

管理命令:
  sudo systemctl status xray-client
  sudo systemctl restart xray-client
  sudo journalctl -u xray-client -f
  sudo bash xray-client-install.sh uninstall
```

## 错误处理

- 非 root → 退出
- 链接缺失/格式非法/非 reality → 报错并打印格式示例
- 不支持的架构 → 退出
- 下载失败 → 退出
- config 生成后 `xray -test` 验证失败 → 退出
- 服务启动失败 → 打印 `journalctl -u xray-client -n 20`

## 文档

- `CLIENT_CONFIG.md` Linux 一节改为 REALITY + 一键脚本 A/B 用法
- `README.md` Xray 章节补 Linux 一键客户端入口

## 测试（本环境不实际安装）

- 三处（脚本）`bash -n` 语法检查
- config.json 模板占位值替换后过 `python3 json.load`
- 链接解析单测：用真实链接断言 uuid/ip/port/pbk/sid/sni/flow 提取正确
- 真实连通由用户在客户端机器用 `curl -x socks5h://127.0.0.1:1080 ...` 验证（交付标注）

## 不做的事（YAGNI）

- 不做 HTTP 代理端口（只 SOCKS5）
- 不做 TUN 全局透明代理
- 不做 sing-box 内核
- 不重写 CLIENT_CONFIG.md 中 Linux 以外平台的旧自签内容（避免范围蔓延）
