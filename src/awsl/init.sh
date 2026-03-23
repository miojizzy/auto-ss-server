#!/bin/bash
# awsl 工具安装脚本

set -e

INSTALL_DIR="/root/bin"
SCRIPT_NAME="awsl"

echo "安装 awsl 工具..."

# 创建安装目录
mkdir -p ${INSTALL_DIR}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 复制主程序
cp "${SCRIPT_DIR}/awsl" "${INSTALL_DIR}/${SCRIPT_NAME}"
chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"

# 确保 PATH 包含安装目录
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo "添加 ${INSTALL_DIR} 到 PATH..."
    echo "export PATH=\$PATH:${INSTALL_DIR}" >> ~/.bashrc
    export PATH=$PATH:${INSTALL_DIR}
fi

echo ""
echo "安装完成!"
echo "使用方法: awsl --help"
echo ""
echo "首次使用请运行以下命令配置 AWS 凭证:"
echo "  aws configure"
