# Xray 改用 REALITY 替换自签证书 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Xray 安装从自签 TLS 证书改为 REALITY，客户端不再需要 allowInsecure，并让显示配置/管理/卸载脚本及文档同步。

**Architecture:** 安装脚本用 `xray x25519` 生成密钥对、`openssl rand` 生成 shortId，写 REALITY 配置和 `/etc/xray/reality.env`（持久化参数）。显示/管理脚本改为读 env 拼 REALITY 分享链接。

**Tech Stack:** Bash, Xray-core, openssl, systemd。无测试框架；验证靠 `bash -n` 语法检查 + 密钥解析逻辑的 mock 测试。

**重要约束:** 不在开发环境运行或安装。所有验证仅限语法检查与离线逻辑测试。真实端到端连接由用户在服务器上验证。

---

## 文件结构

- `src/xray/xray-install.sh` — 修改：删除证书生成段，新增 REALITY 密钥生成段，改 config.json，写 reality.env
- `src/xray/show-config.sh` — 修改：读 reality.env 生成 REALITY 链接
- `src/xray/xray-manage.sh` — 修改：`info` 命令读 reality.env 生成 REALITY 链接
- `src/xray/xray-uninstall.sh` — 无需改（删整 /etc/xray 已覆盖 env）；仅核对
- `XRAY_INSTALL.md` / `README.md` — 文档措辞更新
- `docs/superpowers/specs/2026-06-24-xray-reality-design.md` — 已存在的设计参考

---

### Task 1: 安装脚本 — 替换证书生成为 REALITY 密钥生成

**Files:**
- Modify: `src/xray/xray-install.sh:186-203`（阶段5 自签证书段）

- [ ] **Step 1: 替换证书生成段为 REALITY 密钥生成**

把 `src/xray/xray-install.sh` 中第 186-203 行（从 `# ============ 阶段5: 生成自签证书 ============` 到 `print_success "权限设置完成"`）整段替换为：

```bash
# ============ 阶段5b: 生成 REALITY 密钥 ============
print_step "5" "生成 REALITY 密钥"

# 伪装目标（借用真实大站的 TLS 指纹）
REALITY_DEST="www.microsoft.com:443"
REALITY_SERVER_NAME="www.microsoft.com"

print_info "生成 x25519 密钥对..."
X25519_OUTPUT=$(/usr/local/Xray/xray x25519)
# 兼容新旧版本字段名：旧版 "Private key:" / "Public key:"，新版 "PrivateKey:" / "Password:"
REALITY_PRIVATE_KEY=$(echo "$X25519_OUTPUT" | grep -iE 'private[ ]?key' | awk -F: '{print $2}' | tr -d '[:space:]')
REALITY_PUBLIC_KEY=$(echo "$X25519_OUTPUT" | grep -iE 'public[ ]?key|password' | awk -F: '{print $2}' | tr -d '[:space:]')

if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
    print_error "REALITY 密钥生成失败，无法解析 xray x25519 输出"
    echo "$X25519_OUTPUT"
    exit 1
fi
print_success "x25519 密钥对生成完成"

print_info "生成 shortId..."
REALITY_SHORT_ID=$(openssl rand -hex 8)
print_success "shortId: ${YELLOW}$REALITY_SHORT_ID${NC}"
```

- [ ] **Step 2: 语法检查**

Run: `bash -n src/xray/xray-install.sh`
Expected: 无输出（退出码 0）

- [ ] **Step 3: 提交**

```bash
git add src/xray/xray-install.sh
git commit -m "feat: xray-install 改用 REALITY 密钥替代自签证书生成"
```

---

### Task 2: 安装脚本 — 改 config.json 的 streamSettings

**Files:**
- Modify: `src/xray/xray-install.sh`（阶段6，原 231-243 行的 streamSettings 块）

- [ ] **Step 1: 替换 streamSettings 块**

在 `src/xray/xray-install.sh` 的 `cat > /etc/xray/config.json <<EOF` 配置中，把 `streamSettings` 块（原 `"network": "tcp"` 起到 tlsSettings 结束）替换为：

```
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DEST",
          "xver": 0,
          "serverNames": ["$REALITY_SERVER_NAME"],
          "privateKey": "$REALITY_PRIVATE_KEY",
          "shortIds": ["$REALITY_SHORT_ID"]
        }
      }
```

注意：inbounds 的 `port` / `clients` / `flow: xtls-rprx-vision` / `decryption: none` 保持不变。outbounds 不变。

- [ ] **Step 2: 语法检查**

Run: `bash -n src/xray/xray-install.sh`
Expected: 无输出

- [ ] **Step 3: 校验生成的 JSON 模板合法性（用占位值替换 shell 变量后过 JSON 解析）**

Run:
```bash
sed -n '/cat > \/etc\/xray\/config.json/,/^EOF$/p' src/xray/xray-install.sh \
  | sed '1d;$d' \
  | sed 's/\$XRAY_PORT/443/g; s/\$XRAY_UUID/uuid/g; s/\$REALITY_DEST/www.microsoft.com:443/g; s/\$REALITY_SERVER_NAME/www.microsoft.com/g; s/\$REALITY_PRIVATE_KEY/priv/g; s/\$REALITY_SHORT_ID/abcd/g' \
  | python3 -c 'import sys,json; json.load(sys.stdin); print("JSON OK")'
```
Expected: `JSON OK`

- [ ] **Step 4: 提交**

```bash
git add src/xray/xray-install.sh
git commit -m "feat: xray-install config.json 改用 reality streamSettings"
```

---

### Task 3: 安装脚本 — 写 reality.env 并更新结尾分享链接

**Files:**
- Modify: `src/xray/xray-install.sh`（config.json 生成后、阶段7 验证前，插入写 env；以及阶段11/结尾的分享链接行）

- [ ] **Step 1: 在 config.json 生成后插入写 reality.env**

在 `print_success "配置文件创建完成"` 之后、`# ============ 阶段7: 验证配置文件 ============` 之前插入：

```bash
print_info "保存 REALITY 参数到 /etc/xray/reality.env"
cat > /etc/xray/reality.env <<EOF
XRAY_PORT=$XRAY_PORT
XRAY_UUID=$XRAY_UUID
PUBLIC_KEY=$REALITY_PUBLIC_KEY
SHORT_ID=$REALITY_SHORT_ID
SERVER_NAME=$REALITY_SERVER_NAME
SERVER_IP=$SERVER_IP
EOF
chmod 600 /etc/xray/reality.env
print_success "REALITY 参数已保存"
```

- [ ] **Step 2: 替换结尾的分享链接与配置信息块**

把结尾 `print_step "11"` 之后到 VLESS 分享链接（原含 `跳过证书验证` 和 `security=tls&...allowInsecure=1` 的整块）替换为下面内容。找到从 `echo -e "  ${BLUE}协议:${NC} VLESS"` 到那条 `vless://...allowInsecure=1` 链接行的区间，替换为：

```bash
echo -e "  ${BLUE}协议:${NC} VLESS"
echo -e "  ${BLUE}地址:${NC} $SERVER_IP"
echo -e "  ${BLUE}端口:${NC} $XRAY_PORT"
echo -e "  ${BLUE}UUID:${NC} $XRAY_UUID"
echo -e "  ${BLUE}传输:${NC} TCP"
echo -e "  ${BLUE}安全:${NC} REALITY"
echo -e "  ${BLUE}流控:${NC} xtls-rprx-vision"
echo -e "  ${BLUE}SNI:${NC} $REALITY_SERVER_NAME"
echo -e "  ${BLUE}公钥(pbk):${NC} $REALITY_PUBLIC_KEY"
echo -e "  ${BLUE}shortId(sid):${NC} $REALITY_SHORT_ID"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}VLESS分享链接${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "vless://$XRAY_UUID@$SERVER_IP:$XRAY_PORT?security=reality&encryption=none&pbk=$REALITY_PUBLIC_KEY&sid=$REALITY_SHORT_ID&sni=$REALITY_SERVER_NAME&fp=chrome&flow=xtls-rprx-vision&type=tcp#xray-reality"
```

- [ ] **Step 3: 语法检查**

Run: `bash -n src/xray/xray-install.sh`
Expected: 无输出

- [ ] **Step 4: 确认无残留自签引用**

Run: `grep -nE 'server\.crt|server\.key|allowInsecure|自签|security=tls' src/xray/xray-install.sh || echo "CLEAN"`
Expected: `CLEAN`

- [ ] **Step 5: 提交**

```bash
git add src/xray/xray-install.sh
git commit -m "feat: xray-install 写 reality.env 并输出 REALITY 分享链接"
```

---

### Task 4: x25519 密钥解析逻辑的 mock 测试

**Files:**
- 临时验证，无需提交测试文件

- [ ] **Step 1: 用新旧两种格式的 mock 输出验证解析表达式**

Run:
```bash
parse() {
  local out="$1"
  local priv pub
  priv=$(echo "$out" | grep -iE 'private[ ]?key' | awk -F: '{print $2}' | tr -d '[:space:]')
  pub=$(echo "$out" | grep -iE 'public[ ]?key|password' | awk -F: '{print $2}' | tr -d '[:space:]')
  echo "priv=$priv pub=$pub"
}
# 旧版格式
parse "Private key: AAAA
Public key: BBBB"
# 新版格式
parse "PrivateKey: CCCC
Password: DDDD"
```
Expected:
```
priv=AAAA pub=BBBB
priv=CCCC pub=DDDD
```

若两种格式都能正确提取，解析逻辑通过。无需提交（这是对 Task 1 已写逻辑的验证）。

---

### Task 5: show-config.sh 改读 reality.env

**Files:**
- Modify: `src/xray/show-config.sh`（整体重写参数提取与链接生成逻辑）

- [ ] **Step 1: 重写参数提取段**

把 `src/xray/show-config.sh` 中 `CONFIG_FILE="/etc/xray/config.json"` 到 `VLESS_LINK=...` 那段（含原 config 检查、grep 提取 port/uuid、hostname IP 探测、旧 VLESS_LINK）替换为：

```bash
REALITY_ENV="/etc/xray/reality.env"

# 检查 REALITY 配置
if [ ! -f "$REALITY_ENV" ]; then
    print_error "未检测到 REALITY 配置: $REALITY_ENV"
    echo "请先运行安装脚本 (xray-install.sh)"
    exit 1
fi

# shellcheck disable=SC1090
source "$REALITY_ENV"

if [ -z "${XRAY_PORT:-}" ] || [ -z "${XRAY_UUID:-}" ] || [ -z "${PUBLIC_KEY:-}" ] \
   || [ -z "${SHORT_ID:-}" ] || [ -z "${SERVER_NAME:-}" ] || [ -z "${SERVER_IP:-}" ]; then
    print_error "REALITY 配置不完整，请重新运行安装脚本"
    exit 1
fi

# 生成分享链接
VLESS_LINK="vless://$XRAY_UUID@$SERVER_IP:$XRAY_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&sid=$SHORT_ID&sni=$SERVER_NAME&fp=chrome&flow=xtls-rprx-vision&type=tcp#xray-reality"
```

- [ ] **Step 2: 更新显示信息块**

把显示块中 `地址/端口/UUID/传输/安全/流控/跳过证书验证` 那几行替换为：

```bash
echo -e "  ${BLUE}协议:${NC} VLESS"
echo -e "  ${BLUE}地址:${NC} $SERVER_IP"
echo -e "  ${BLUE}端口:${NC} $XRAY_PORT"
echo -e "  ${BLUE}UUID:${NC} $XRAY_UUID"
echo -e "  ${BLUE}传输:${NC} TCP"
echo -e "  ${BLUE}安全:${NC} REALITY"
echo -e "  ${BLUE}流控:${NC} xtls-rprx-vision"
echo -e "  ${BLUE}SNI:${NC} $SERVER_NAME"
echo -e "  ${BLUE}公钥(pbk):${NC} $PUBLIC_KEY"
echo -e "  ${BLUE}shortId(sid):${NC} $SHORT_ID"
```

- [ ] **Step 3: 语法检查**

Run: `bash -n src/xray/show-config.sh`
Expected: 无输出

- [ ] **Step 4: 确认无残留旧引用**

Run: `grep -nE 'allowInsecure|security=tls|hostname -I|跳过证书' src/xray/show-config.sh || echo "CLEAN"`
Expected: `CLEAN`

- [ ] **Step 5: 提交**

```bash
git add src/xray/show-config.sh
git commit -m "feat: show-config 读 reality.env 生成 REALITY 分享链接"
```

---

### Task 6: xray-manage.sh 的 info 命令改读 reality.env

**Files:**
- Modify: `src/xray/xray-manage.sh:117-145`（show_info 函数）

- [ ] **Step 1: 重写 show_info 函数**

把 `show_info()` 函数体（第 117-145 行，从 `show_info() {` 到对应的 `}`）替换为：

```bash
show_info() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}服务器信息${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"

    local REALITY_ENV="/etc/xray/reality.env"
    if [ ! -f "$REALITY_ENV" ]; then
        echo -e "${RED}未检测到 REALITY 配置: $REALITY_ENV${NC}"
        echo "请先运行安装脚本 (xray-install.sh)"
        return 1
    fi

    # shellcheck disable=SC1090
    source "$REALITY_ENV"

    echo ""
    echo -e "  ${BLUE}Xray版本:${NC} $(/usr/local/Xray/xray -version | head -1)"
    echo -e "  ${BLUE}服务器IP:${NC} $SERVER_IP"
    echo -e "  ${BLUE}监听端口:${NC} $XRAY_PORT"
    echo -e "  ${BLUE}协议:${NC} VLESS"
    echo -e "  ${BLUE}UUID:${NC} $XRAY_UUID"
    echo -e "  ${BLUE}流控:${NC} xtls-rprx-vision"
    echo -e "  ${BLUE}安全:${NC} REALITY"
    echo -e "  ${BLUE}SNI:${NC} $SERVER_NAME"
    echo -e "  ${BLUE}公钥(pbk):${NC} $PUBLIC_KEY"
    echo -e "  ${BLUE}shortId(sid):${NC} $SHORT_ID"
    echo ""

    echo -e "${YELLOW}VLESS分享链接:${NC}"
    echo "vless://$XRAY_UUID@$SERVER_IP:$XRAY_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&sid=$SHORT_ID&sni=$SERVER_NAME&fp=chrome&flow=xtls-rprx-vision&type=tcp#xray-reality"
    echo ""
}
```

- [ ] **Step 2: 语法检查**

Run: `bash -n src/xray/xray-manage.sh`
Expected: 无输出

- [ ] **Step 3: 确认无残留旧引用**

Run: `grep -nE 'allowInsecure|security=tls|hostname -I' src/xray/xray-manage.sh || echo "CLEAN"`
Expected: `CLEAN`

- [ ] **Step 4: 提交**

```bash
git add src/xray/xray-manage.sh
git commit -m "feat: xray-manage info 读 reality.env 生成 REALITY 分享链接"
```

---

### Task 7: 文档更新（XRAY_INSTALL.md + README.md）

**Files:**
- Modify: `XRAY_INSTALL.md`（脚本特性、注意事项、客户端措辞）
- Modify: `README.md`（Xray 章节描述）

- [ ] **Step 1: 更新 XRAY_INSTALL.md 注意事项**

在 `XRAY_INSTALL.md` 的「注意事项」中，把 `会覆盖 /etc/xray/config.json` 那段保留，把任何"自签证书"或"开放防火墙 443"的措辞更新为 REALITY，并新增一行说明：

```markdown
⚠️ 使用 REALITY 协议，无需证书，客户端无需 allowInsecure
⚠️ 默认伪装目标 www.microsoft.com:443
```

并在「脚本特性」列表新增：

```markdown
✅ **REALITY 协议** - 借用真实大站 TLS 指纹，无需证书，抗封锁更强
```

- [ ] **Step 2: 更新 README.md Xray 章节**

把 README.md 中 `Xray VLESS（自签证书 + IP 方式）` 改为 `Xray VLESS（REALITY 协议，无需证书）`。

- [ ] **Step 3: 确认文档无残留"自签证书"**

Run: `grep -rn "自签证书\|allowInsecure" XRAY_INSTALL.md README.md || echo "CLEAN"`
Expected: `CLEAN`

- [ ] **Step 4: 提交**

```bash
git add XRAY_INSTALL.md README.md
git commit -m "docs: Xray 文档更新为 REALITY 协议"
```

---

### Task 8: 卸载脚本核对 + 最终全量检查 + 推送

**Files:**
- 核对 `src/xray/xray-uninstall.sh`（预期无改动）

- [ ] **Step 1: 核对卸载脚本**

Run: `grep -nE 'server\.crt|server\.key|reality' src/xray/xray-uninstall.sh || echo "无证书/reality 专项引用，删整 /etc/xray 已覆盖 reality.env"`
Expected: 输出说明（卸载脚本删 `/etc/xray` 整目录，已覆盖 `reality.env`，无需改动）

- [ ] **Step 2: 三脚本最终语法检查**

Run: `for f in src/xray/xray-install.sh src/xray/show-config.sh src/xray/xray-manage.sh src/xray/xray-uninstall.sh; do bash -n "$f" && echo "$f OK"; done`
Expected: 四个文件各输出 `... OK`

- [ ] **Step 3: 全仓库残留检查**

Run: `grep -rn "allowInsecure\|security=tls\|自签证书" src/xray/ || echo "CLEAN"`
Expected: `CLEAN`

- [ ] **Step 4: 推送**

```bash
git push
```
Expected: 推送成功到 origin/main

---

## 验证说明（交付时告知用户）

本环境不运行安装。已完成的验证：四脚本 `bash -n` 语法检查、config.json 模板 JSON 合法性、x25519 解析逻辑 mock 测试、残留旧引用扫描。**真实端到端连接（客户端用 REALITY 链接连上服务器）需用户在实际服务器上运行 `xray-install.sh` 后验证。**
