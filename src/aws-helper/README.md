# aws-helper — SSM 参数解引用器

在 AWS EC2 上把 Xray 的固定参数（UUID/密钥/shortId/SNI/端口）集中存到 SSM Parameter Store，实例启动时（user-data）自动拉出真实值注入 `server.sh`。

## 工作原理

`ssm-env.sh` 是一个**通用的 SSM 解引用器**，不绑定具体参数名：

- 把要固定的变量值设成 **SSM 参数路径**（以 `/` 开头）传入
- 脚本读出真实值，打印成同名变量 `NAME='真实值'`
- 值**不以 `/` 开头**则原样当字面值输出（如 `REALITY_SNI=www.yahoo.com`）
- 拉取失败（参数不存在/无权限）的变量跳过不输出，不中断

进度/错误信息打到 stderr，`NAME='value'` 结果打到 stdout，方便 `> 文件` 或 `eval`。

## 用法

```bash
# get(默认)：输出 NAME='value'
XRAY_UUID=/xray/uuid REALITY_SNI=www.yahoo.com \
  bash ssm-env.sh get XRAY_UUID REALITY_SNI
# 输出:
#   XRAY_UUID='ac8a556c-...'
#   REALITY_SNI='www.yahoo.com'

# env：每行加 export，供 eval
eval "$(XRAY_UUID=/xray/uuid bash ssm-env.sh env XRAY_UUID)"

# region：AWS_REGION 优先，否则自动从实例元数据(IMDSv2/v1)获取
AWS_REGION=ap-south-1 XRAY_UUID=/xray/uuid bash ssm-env.sh get XRAY_UUID
```

## 先把参数写进 SSM（手动，一次即可）

本工具**只读**，写入 SSM 请手动执行（用你自己独立生成的密钥）：

```bash
REGION=ap-south-1
aws ssm put-parameter --region $REGION --name /xray/uuid        --type String       --value "$(xray uuid)"
# 私钥用 SecureString 加密存储
aws ssm put-parameter --region $REGION --name /xray/private_key --type SecureString --value "你的私钥"
aws ssm put-parameter --region $REGION --name /xray/public_key  --type String       --value "你的公钥"
aws ssm put-parameter --region $REGION --name /xray/short_id    --type String       --value "$(openssl rand -hex 8)"
```

密钥生成：`xray uuid`、`xray x25519`（得 PrivateKey / Password=PublicKey）、`openssl rand -hex 8`。

## EC2 user-data（一键部署）

实例启动时自动拉参数 → 写 `/etc/xray-server.env` → 装 xray（`server.sh` 会自动加载该文件）：

```bash
#!/bin/bash
set -e
BASE=https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src

# 1) 解引用 SSM 参数，写成 server.sh 会自动加载的 env 文件
#    值填 SSM 路径的会被解引用；填字面值(如 SNI/端口)的原样保留
XRAY_UUID=/xray/uuid \
REALITY_PRIVATE_KEY=/xray/private_key \
REALITY_PUBLIC_KEY=/xray/public_key \
REALITY_SHORT_ID=/xray/short_id \
REALITY_SNI=www.yahoo.com \
XRAY_PORT=443 \
  bash <(curl -fsSL "$BASE/aws-helper/ssm-env.sh") get \
    XRAY_UUID REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY REALITY_SHORT_ID REALITY_SNI XRAY_PORT \
  | tee /etc/xray-server.env >/dev/null

# 2) 一键装 xray（自动读 /etc/xray-server.env 里的固定参数）
curl -fsSL "$BASE/xray/server.sh" | bash -s install
```

装完 xray 用固定参数起来，客户端分享链接只有服务器 IP 不同，换机器无需重配客户端。

## IAM 权限

实例角色（Instance Profile）需要：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ssm:GetParameter"],
      "Resource": "arn:aws:ssm:*:*:parameter/xray/*"
    },
    {
      "Effect": "Allow",
      "Action": ["kms:Decrypt"],
      "Resource": "*",
      "Comment": "仅当使用 SecureString(如 private_key) 时需要"
    }
  ]
}
```

> `kms:Decrypt` 仅在读取 SecureString 参数时需要；若全用 String 类型可去掉。JSON 里的 `Comment` 字段仅为说明，实际策略请删除。

## 依赖

- `aws` CLI（拉 SSM 时需要；纯字面值不需要）
- 无需 jq（用 `--output text` 逐个参数拉取）

### 安装 AWS CLI

用配套脚本一键装官方 AWS CLI v2（自动识别架构、幂等）：

```bash
curl -fsSL https://raw.githubusercontent.com/miojizzy/auto-ss-server/main/src/aws-helper/install-awscli.sh | sudo bash

# 强制重装/升级
sudo bash install-awscli.sh --force
```

EC2 上推荐挂 IAM 角色（Instance Profile），无需 `aws configure`。验证：`aws sts get-caller-identity`。

## 子命令

| 命令 | 说明 |
|------|------|
| `get VAR...` | 输出 `NAME='value'` 行（默认） |
| `env VAR...` | 每行加 `export` 前缀，供 `eval` |
| `help` | 显示帮助 |
