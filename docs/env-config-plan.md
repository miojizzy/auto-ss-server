# 环境变量配置隔离方案

## 背景

项目是公开 repo，不能把服务器的端口/密钥/UUID 等私密配置提交进来。

## 方案

**三层优先级**（高 → 低）：
1. 命令行环境变量（`XRAY_PORT=xxx sudo bash server.sh install`）
2. 服务器本地 `/etc/xray-server.env` / `/etc/xray-client.env` / `/etc/ss-server.env` / `/etc/ss-client.env`
3. 脚本内默认值（随机生成或内置常量）

repo 里只放 `.env.example` 模板文件，真实 `.env` 只存在于服务器本地，从不提交。

---

## 各脚本可指定的配置项

### src/xray/server.sh

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `XRAY_PORT` | `443` | 监听端口（已支持，补充读 env 文件） |
| `XRAY_UUID` | `uuidgen` 随机 | 指定后重装不换客户端链接 |
| `REALITY_SNI` | `www.microsoft.com` | 伪装目标域名 |
| `REALITY_DEST` | `${REALITY_SNI}:443` | 伪装目标（默认跟 SNI 一致） |
| `REALITY_SHORT_ID` | `openssl rand -hex 8` 随机 | shortId |
| `REALITY_PRIVATE_KEY` | `xray x25519` 随机 | 私钥（指定后公钥保持不变） |

配置文件路径：`/etc/xray-server.env`

### src/xray/client.sh

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `VLESS_LINK` | 无（必填） | vless:// 分享链接（已支持，补充读 env 文件） |

配置文件路径：`/etc/xray-client.env`

### src/shadowsocks/server.sh

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `SS_PORT` | 随机 | 监听端口（已支持，补充读 env 文件） |
| `SS_PASSWORD` | 随机 | 密码（已支持参数传入，补充读 env 文件） |
| `SS_METHOD` | `chacha20-ietf-poly1305` | 加密方式（已支持，补充读 env 文件） |
| `METRICS_PORT` | `9091` | metrics 端口（已支持，补充读 env 文件） |

配置文件路径：`/etc/ss-server.env`

### src/shadowsocks/client.sh

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `SS_LINK` | 无（必填） | ss:// 分享链接（已支持，补充读 env 文件） |

配置文件路径：`/etc/ss-client.env`

---

## 要做的改动

### 四个脚本各自

在参数解析最前面（取环境变量之前）加：
```bash
# 加载本地配置（若存在）；命令行传入的环境变量优先级更高，不覆盖
ENV_FILE="<对应路径>"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
```

注意：用 `. `（source）而非 `export`，已在外部设置的变量不会被文件里的值覆盖（利用 `${VAR:-default}` 的已有机制）。

### src/xray/server.sh 额外新增

在生成 UUID/密钥对/shortId 之前检查环境变量是否已指定，已指定则跳过随机生成：
- `XRAY_UUID` 有值 → 跳过 `uuidgen`
- `REALITY_PRIVATE_KEY` 有值 → 跳过 `xray x25519`（同时需要提供 `REALITY_PUBLIC_KEY`）
- `REALITY_SHORT_ID` 有值 → 跳过 `openssl rand`
- `REALITY_SNI` 有值 → 替换 `www.microsoft.com`

### 新增 .env.example 文件（提交到 repo）

`xray-server.env.example`、`xray-client.env.example`、`ss-server.env.example`、`ss-client.env.example` 统一放到 `config/` 目录。

内容只是注释说明 + 空值，没有真实数据，可以安全公开。

---

## 不做的事

- 不加密 env 文件（系统文件权限 600 足够）
- 不做 Vault / secrets manager（过度设计）
- 不改客户端的链接解析逻辑（链接本身就是参数，不需要 env 隔离）

---

## 状态

- [ ] src/xray/server.sh：读 /etc/xray-server.env + UUID/密钥可指定
- [ ] src/xray/client.sh：读 /etc/xray-client.env
- [ ] src/shadowsocks/server.sh：读 /etc/ss-server.env
- [ ] src/shadowsocks/client.sh：读 /etc/ss-client.env
- [ ] 新增 config/xray-server.env.example 等 4 个模板文件
- [ ] README 补充说明
