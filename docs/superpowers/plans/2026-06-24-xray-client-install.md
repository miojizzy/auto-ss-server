# Linux 一键安装 Xray 客户端 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新建一个 Linux 一键脚本，解析 vless reality 链接、生成 Xray 客户端配置、装成 systemd 服务，本地提供 SOCKS5 代理。

**Architecture:** 单个 bash 脚本 `xray-client-install.sh`。从参数($1)或环境变量(VLESS_LINK)取链接，纯 bash/sed 解析，自动检测架构下载 Xray，写 `/etc/xray-client/config.json`，装 `xray-client.service`。含 uninstall 子命令。

**Tech Stack:** Bash, Xray-core, systemd, openssl(无需), python3(仅测试用)。无测试框架；验证靠 bash -n + JSON 校验 + 链接解析单测。

**重要约束:** 不在开发环境运行或安装。仅语法检查与离线逻辑测试。真实连通由用户在客户端机器验证。

---

## 文件结构

- `src/xray/xray-client-install.sh` — 新建：主脚本（解析+安装+卸载）
- `CLIENT_CONFIG.md` — Linux 一节改为 REALITY + 一键脚本用法
- `README.md` — Xray 章节补 Linux 一键客户端入口

---

### Task 1: 创建脚本骨架（颜色函数、root 检查、取链接、用法）

**Files:**
- Create: `src/xray/xray-client-install.sh`

- [ ] **Step 1: 写脚本骨架（只到全局变量 + usage + root 检查，入口分发留到 Task 6）**

创建 `src/xray/xray-client-install.sh`，内容：

```bash
#!/bin/bash

# Xray 客户端一键安装脚本（REALITY）
# 用法:
#   sudo bash xray-client-install.sh "vless://..."
#   VLESS_LINK="vless://..." sudo bash xray-client-install.sh
#   sudo bash xray-client-install.sh uninstall
#   curl -fsSL <url> | sudo bash -s -- "vless://..."
#   curl -fsSL <url> | sudo VLESS_LINK="vless://..." bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step()    { echo -e "${BLUE}========================================${NC}"; echo -e "${GREEN}[步骤 $1]${NC} $2"; echo -e "${BLUE}========================================${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ $1${NC}"; }

CLIENT_DIR="/etc/xray-client"
CLIENT_CONFIG="$CLIENT_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/xray-client.service"
XRAY_BIN="/usr/local/Xray/xray"
SOCKS_PORT=1080

usage() {
    echo "用法:"
    echo "  sudo bash xray-client-install.sh \"vless://uuid@ip:port?security=reality&pbk=...&sid=...&sni=...&flow=xtls-rprx-vision&type=tcp\""
    echo "  VLESS_LINK=\"vless://...\" sudo bash xray-client-install.sh"
    echo "  sudo bash xray-client-install.sh uninstall"
}

# 检查 root
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本必须以 root 身份运行"
    echo "请使用 sudo"
    exit 1
fi
```

本 Task 写到 root 检查为止。所有功能函数（parse_link/install_xray/...）和入口分发由 Task 2-6 依次追加，避免引用未定义函数。注意：root 检查放在文件靠前没问题，因为入口分发（Task 6 追加在最末）才会真正调用各函数，bash 顺序执行到那时函数已全部定义。

- [ ] **Step 2: 语法检查**

Run: `bash -n src/xray/xray-client-install.sh`
Expected: 无输出

- [ ] **Step 3: 提交**

```bash
chmod +x src/xray/xray-client-install.sh
git add src/xray/xray-client-install.sh
git commit -m "feat: xray-client-install 脚本骨架"
```

---

### Task 2: 链接解析函数 parse_link

**Files:**
- Modify: `src/xray/xray-client-install.sh`

- [ ] **Step 1: 在颜色函数与变量定义之后、root 检查之前，插入 parse_link 函数**

```bash
# 解析 vless:// 链接，导出全局变量 V_UUID V_IP V_PORT V_PBK V_SID V_SNI V_FLOW V_FP V_SECURITY
parse_link() {
    local link="$1"
    # 去掉 vless:// 前缀和 #备注
    link="${link#vless://}"
    link="${link%%#*}"

    # 主体: uuid@ip:port?query
    local userinfo="${link%%\?*}"     # uuid@ip:port
    local query="${link#*\?}"         # 查询串
    [[ "$query" == "$link" ]] && query=""

    V_UUID="${userinfo%%@*}"
    local hostport="${userinfo#*@}"   # ip:port
    V_IP="${hostport%%:*}"
    V_PORT="${hostport##*:}"

    # 从 query 提取单个参数
    _q() { echo "$query" | tr '&' '\n' | grep -E "^$1=" | head -1 | cut -d= -f2-; }
    V_SECURITY="$(_q security)"
    V_PBK="$(_q pbk)"
    V_SID="$(_q sid)"
    V_SNI="$(_q sni)"
    V_FLOW="$(_q flow)"
    V_FP="$(_q fp)"
    [[ -z "$V_FP" ]] && V_FP="chrome"

    # 校验
    if [[ "$V_SECURITY" != "reality" ]]; then
        print_error "链接 security 必须为 reality（当前: ${V_SECURITY:-空}）"
        exit 1
    fi
    if [[ -z "$V_UUID" || -z "$V_IP" || -z "$V_PORT" || -z "$V_PBK" ]]; then
        print_error "链接缺少必需字段 (uuid/ip/port/pbk)"
        usage
        exit 1
    fi
}
```

- [ ] **Step 2: 语法检查**

Run: `bash -n src/xray/xray-client-install.sh`
Expected: 无输出

- [ ] **Step 3: 链接解析单测（用真实链接验证提取正确）**

Run:
```bash
# 提取 parse_link 函数 + 依赖的 print_error/usage 桩，单独测试
cat > /tmp/test-parse.sh <<'SH'
print_error() { echo "ERR: $*"; }
usage() { :; }
SH
sed -n '/^parse_link() {/,/^}/p' src/xray/xray-client-install.sh >> /tmp/test-parse.sh
cat >> /tmp/test-parse.sh <<'SH'
parse_link "vless://1b4e997c-3776-4cd2-aa87-ce80a6d647be@13.200.200.12:8443?security=reality&encryption=none&pbk=waE5Qbg8lC18CqBIo6XjYFJhVOWj9czpGHR65jk432E&sid=0343a0bce47e163a&sni=www.microsoft.com&fp=chrome&flow=xtls-rprx-vision&type=tcp#xray-reality"
echo "uuid=$V_UUID"
echo "ip=$V_IP"
echo "port=$V_PORT"
echo "pbk=$V_PBK"
echo "sid=$V_SID"
echo "sni=$V_SNI"
echo "flow=$V_FLOW"
echo "fp=$V_FP"
echo "security=$V_SECURITY"
SH
bash /tmp/test-parse.sh
```
Expected:
```
uuid=1b4e997c-3776-4cd2-aa87-ce80a6d647be
ip=13.200.200.12
port=8443
pbk=waE5Qbg8lC18CqBIo6XjYFJhVOWj9czpGHR65jk432E
sid=0343a0bce47e163a
sni=www.microsoft.com
flow=xtls-rprx-vision
fp=chrome
security=reality
```

- [ ] **Step 4: 提交**

```bash
git add src/xray/xray-client-install.sh
git commit -m "feat: xray-client-install 解析 vless reality 链接"
```

---

### Task 3: 架构检测 + 下载安装 Xray

**Files:**
- Modify: `src/xray/xray-client-install.sh`

- [ ] **Step 1: 在 parse_link 之后插入 install_xray 函数**

```bash
# 检测架构并下载安装 Xray 二进制（若已存在则跳过下载）
install_xray() {
    print_step "1" "检测架构并安装 Xray"

    local arch zip
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  zip="Xray-linux-64.zip" ;;
        aarch64|arm64) zip="Xray-linux-arm64-v8a.zip" ;;
        *) print_error "不支持的架构: $arch"; exit 1 ;;
    esac
    print_success "架构: $arch -> $zip"

    if [[ -x "$XRAY_BIN" ]]; then
        print_info "检测到已存在 Xray 二进制，跳过下载"
        return 0
    fi

    print_info "安装依赖 (curl unzip)..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y curl unzip >/dev/null
    fi

    mkdir -p /usr/local/Xray
    cd /tmp
    local ver url
    ver="$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
    url="https://github.com/XTLS/Xray-core/releases/download/${ver}/${zip}"
    print_info "下载 Xray ${ver} ..."
    if ! curl -fsSL "$url" -o xray-client.zip; then
        print_error "下载失败: $url"
        exit 1
    fi
    unzip -o xray-client.zip xray -d /usr/local/Xray >/dev/null
    rm -f xray-client.zip
    chmod +x "$XRAY_BIN"
    print_success "Xray 安装完成"
}
```

- [ ] **Step 2: 语法检查**

Run: `bash -n src/xray/xray-client-install.sh`
Expected: 无输出

- [ ] **Step 3: 提交**

```bash
git add src/xray/xray-client-install.sh
git commit -m "feat: xray-client-install 架构检测与下载"
```

---

### Task 4: 生成客户端 config.json

**Files:**
- Modify: `src/xray/xray-client-install.sh`

- [ ] **Step 1: 在 install_xray 之后插入 write_config 函数**

```bash
# 生成客户端 config.json
write_config() {
    print_step "2" "生成客户端配置"
    mkdir -p "$CLIENT_DIR"
    cat > "$CLIENT_CONFIG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": $SOCKS_PORT,
      "protocol": "socks",
      "settings": { "udp": true }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$V_IP",
            "port": $V_PORT,
            "users": [
              { "id": "$V_UUID", "encryption": "none", "flow": "$V_FLOW" }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "$V_SNI",
          "fingerprint": "$V_FP",
          "publicKey": "$V_PBK",
          "shortId": "$V_SID"
        }
      }
    }
  ]
}
EOF
    print_success "配置已写入 $CLIENT_CONFIG"

    print_info "验证配置..."
    if ! "$XRAY_BIN" -test -c "$CLIENT_CONFIG" >/dev/null 2>&1; then
        print_error "配置验证失败"
        "$XRAY_BIN" -test -c "$CLIENT_CONFIG"
        exit 1
    fi
    print_success "配置验证通过"
}
```

- [ ] **Step 2: 语法检查**

Run: `bash -n src/xray/xray-client-install.sh`
Expected: 无输出

- [ ] **Step 3: JSON 模板合法性校验（占位值替换变量后过 json.load）**

Run:
```bash
sed -n '/cat > "\$CLIENT_CONFIG" <<EOF/,/^EOF$/p' src/xray/xray-client-install.sh \
  | sed '1d;$d' \
  | sed 's/\$SOCKS_PORT/1080/g; s/\$V_IP/1.2.3.4/g; s/\$V_PORT/8443/g; s/\$V_UUID/uuid/g; s/\$V_FLOW/xtls-rprx-vision/g; s/\$V_SNI/www.microsoft.com/g; s/\$V_FP/chrome/g; s/\$V_PBK/pbk/g; s/\$V_SID/sid/g' \
  | python3 -c 'import sys,json; json.load(sys.stdin); print("JSON OK")'
```
Expected: `JSON OK`

- [ ] **Step 4: 提交**

```bash
git add src/xray/xray-client-install.sh
git commit -m "feat: xray-client-install 生成客户端配置"
```

---

### Task 5: systemd 服务 + 结尾输出 + 卸载函数

**Files:**
- Modify: `src/xray/xray-client-install.sh`

- [ ] **Step 1: 在 write_config 之后插入 setup_service / print_result / do_uninstall 函数**

```bash
# 安装并启动 systemd 服务
setup_service() {
    print_step "3" "配置 systemd 服务"
    cat > "$SERVICE_FILE" <<'EOF'
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
EOF
    systemctl daemon-reload
    systemctl restart xray-client
    sleep 2
    if systemctl is-active --quiet xray-client; then
        print_success "xray-client 服务已启动"
    else
        print_error "服务启动失败"
        journalctl -u xray-client -n 20
        exit 1
    fi
    systemctl enable xray-client >/dev/null 2>&1
    print_success "已设置开机自启"
}

print_result() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    print_success "Xray 客户端已启动，SOCKS5 代理: 127.0.0.1:$SOCKS_PORT"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}测试连接:${NC}"
    echo "  curl -x socks5h://127.0.0.1:$SOCKS_PORT https://www.google.com"
    echo "  curl -x socks5h://127.0.0.1:$SOCKS_PORT https://ipinfo.io/ip"
    echo ""
    echo -e "${YELLOW}管理命令:${NC}"
    echo "  sudo systemctl status xray-client"
    echo "  sudo systemctl restart xray-client"
    echo "  sudo journalctl -u xray-client -f"
    echo "  sudo bash xray-client-install.sh uninstall"
    echo ""
}

# 卸载
do_uninstall() {
    print_step "1" "卸载 Xray 客户端"
    if systemctl list-unit-files 2>/dev/null | grep -q '^xray-client\.service'; then
        systemctl stop xray-client 2>/dev/null || true
        systemctl disable xray-client 2>/dev/null || true
        print_success "服务已停止并禁用"
    else
        print_info "未找到 xray-client 服务（跳过）"
    fi
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        systemctl reset-failed 2>/dev/null || true
        print_success "服务文件已删除"
    fi
    rm -rf "$CLIENT_DIR"
    print_success "已删除 $CLIENT_DIR"
    print_info "二进制 /usr/local/Xray 未删除（可能被服务端使用）"
}
```

- [ ] **Step 2: 语法检查**

Run: `bash -n src/xray/xray-client-install.sh`
Expected: 无输出

- [ ] **Step 3: 提交**

```bash
git add src/xray/xray-client-install.sh
git commit -m "feat: xray-client-install systemd 服务与卸载"
```

---

### Task 6: 串联主流程（main + 子命令分发）

**Files:**
- Modify: `src/xray/xray-client-install.sh`

- [ ] **Step 1: 在文件末尾（do_uninstall 函数之后）追加 main 与入口分发**

在 `do_uninstall` 函数定义之后追加：

```bash
main() {
    parse_link "$VLESS_LINK"
    install_xray
    write_config
    setup_service
    print_result
}

# ===== 入口 =====
ACTION="${1:-}"

if [[ "$ACTION" == "uninstall" ]]; then
    do_uninstall
    exit 0
fi

# 取链接：参数优先，其次环境变量
VLESS_LINK="${1:-${VLESS_LINK:-}}"
if [[ -z "$VLESS_LINK" ]]; then
    print_error "未提供 vless:// 链接"
    usage
    exit 1
fi

main
```

最终文件结构顺序：shebang/注释 → set → 颜色函数 → 全局变量 → usage → root 检查 → parse_link → install_xray → write_config → setup_service → print_result → do_uninstall → main → 入口分发。注意 root 检查（Task 1 写入）在函数定义之前，但因为函数调用都发生在文件末尾的入口段，bash 执行到那里时函数均已定义，没有问题。

- [ ] **Step 2: 语法检查**

Run: `bash -n src/xray/xray-client-install.sh`
Expected: 无输出

- [ ] **Step 3: 验证无链接时报错 + uninstall 分发（非 root 环境下用 EUID 跳过测试，仅测分发逻辑）**

Run:
```bash
# 临时去掉 root 检查后测试入口分发（不实际安装）
sed 's/if \[\[ \$EUID -ne 0 \]\]/if false/' src/xray/xray-client-install.sh > /tmp/cli-test.sh
# 无参数应报错退出
bash /tmp/cli-test.sh 2>&1 | grep -q "未提供" && echo "no-arg OK"
```
Expected: `no-arg OK`

- [ ] **Step 4: 提交**

```bash
git add src/xray/xray-client-install.sh
git commit -m "feat: xray-client-install 串联主流程与子命令分发"
```

---

### Task 7: 文档更新（CLIENT_CONFIG.md + README.md）

**Files:**
- Modify: `CLIENT_CONFIG.md`（Linux 用户一节）
- Modify: `README.md`（Xray 章节）

- [ ] **Step 1: 替换 CLIENT_CONFIG.md 的「5. Linux 用户」整节**

将 `CLIENT_CONFIG.md` 中从 `### 5. Linux 用户` 到下一个 `## 分享链接导入` 之前的全部内容，替换为：

```markdown
### 5. Linux 用户

#### 一键安装（REALITY，推荐）

在客户端 Linux 机器上执行（自动检测架构、装为 systemd 服务、本地 SOCKS5 1080）：

\`\`\`bash
# 方式 A：参数传链接
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/xray-client-install.sh \
  | sudo bash -s -- "vless://uuid@ip:port?security=reality&pbk=...&sid=...&sni=...&flow=xtls-rprx-vision&type=tcp"

# 方式 B：环境变量传链接
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/xray-client-install.sh \
  | sudo VLESS_LINK="vless://..." bash
\`\`\`

链接从服务器 \`sudo bash src/xray/show-config.sh\` 获取。

安装后本地 SOCKS5 代理在 \`127.0.0.1:1080\`，测试：

\`\`\`bash
curl -x socks5h://127.0.0.1:1080 https://ipinfo.io/ip   # 应显示服务器 IP
\`\`\`

管理 / 卸载：

\`\`\`bash
sudo systemctl status xray-client
sudo journalctl -u xray-client -f
sudo bash xray-client-install.sh uninstall
\`\`\`
```

（注意：实际写入时去掉上面代码块里 \` 的转义，写成正常的三反引号代码块。）

- [ ] **Step 2: 在 README.md Xray 章节的「一键卸载」小节之后，插入 Linux 一键客户端入口**

在 README.md `## Xray VLESS 服务` 章节中 `### 一键卸载` 代码块之后、`详细说明见` 之前，插入：

```markdown
### Linux 一键客户端

在客户端 Linux 机器上安装（解析分享链接，本地 SOCKS5 1080）：

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/xray/xray-client-install.sh \
  | sudo bash -s -- "vless://..."
\`\`\`

```

（实际写入去掉反引号转义。）

- [ ] **Step 3: 文档无残留检查**

Run: `grep -n "xray-client-install" CLIENT_CONFIG.md README.md`
Expected: 两个文件都至少有一处匹配

- [ ] **Step 4: 提交**

```bash
git add CLIENT_CONFIG.md README.md
git commit -m "docs: 添加 Linux 一键客户端安装说明"
```

---

### Task 8: 最终全量检查 + 推送

**Files:** 无（仅检查与推送）

- [ ] **Step 1: 脚本语法 + JSON + 解析单测复跑**

Run:
```bash
bash -n src/xray/xray-client-install.sh && echo "syntax OK"
```
Expected: `syntax OK`

- [ ] **Step 2: 推送**

```bash
git push
```
Expected: 推送成功到 origin/main

---

## 验证说明（交付时告知用户）

本环境不运行安装。已完成验证：脚本 bash -n 语法检查、config.json 模板 JSON 合法性、vless 链接解析单测（用真实链接断言各字段）、无参数报错分发逻辑。**真实连通（客户端机器装好后 `curl -x socks5h://127.0.0.1:1080 https://ipinfo.io/ip` 显示服务器 IP）需用户在客户端机器上验证。**
