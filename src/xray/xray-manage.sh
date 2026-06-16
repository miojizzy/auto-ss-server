#!/bin/bash

# Xray管理脚本
# 使用方法: bash xray-manage.sh [命令]

XRAY_CONFIG="/etc/xray/config.json"
XRAY_LOG_ERROR="/var/log/xray/error.log"
XRAY_LOG_ACCESS="/var/log/xray/access.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    echo -e "${BLUE}Xray VLESS 服务管理工具${NC}"
    echo ""
    echo "使用方法: sudo bash xray-manage.sh [命令]"
    echo ""
    echo -e "${YELLOW}可用命令:${NC}"
    echo "  status      - 查看服务状态"
    echo "  start       - 启动服务"
    echo "  stop        - 停止服务"
    echo "  restart     - 重启服务"
    echo "  logs        - 查看实时日志（systemd日志）"
    echo "  error       - 查看错误日志"
    echo "  access      - 查看访问日志"
    echo "  test        - 测试配置文件"
    echo "  info        - 显示服务器信息"
    echo "  stats       - 显示流量统计"
    echo "  reload      - 重新加载配置"
    echo "  help        - 显示此帮助信息"
    echo ""
}

show_status() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}服务状态${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    systemctl status xray
}

start_service() {
    echo -e "${YELLOW}正在启动Xray服务...${NC}"
    systemctl start xray
    sleep 2
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}✓ 服务启动成功${NC}"
    else
        echo -e "${RED}✗ 服务启动失败${NC}"
        return 1
    fi
}

stop_service() {
    echo -e "${YELLOW}正在停止Xray服务...${NC}"
    systemctl stop xray
    sleep 1
    echo -e "${GREEN}✓ 服务已停止${NC}"
}

restart_service() {
    echo -e "${YELLOW}正在重启Xray服务...${NC}"
    systemctl restart xray
    sleep 2
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}✓ 服务重启成功${NC}"
    else
        echo -e "${RED}✗ 服务重启失败${NC}"
        return 1
    fi
}

show_logs() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}实时日志（按 Ctrl+C 退出）${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    journalctl -u xray -f
}

show_error_log() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}错误日志${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    if [ -f "$XRAY_LOG_ERROR" ]; then
        tail -n 50 "$XRAY_LOG_ERROR"
    else
        echo -e "${RED}错误日志文件不存在${NC}"
    fi
}

show_access_log() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}访问日志${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    if [ -f "$XRAY_LOG_ACCESS" ]; then
        tail -n 50 "$XRAY_LOG_ACCESS"
    else
        echo -e "${RED}访问日志文件不存在${NC}"
    fi
}

test_config() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}测试配置文件${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    if /usr/local/Xray/xray -c "$XRAY_CONFIG" -test; then
        echo -e "${GREEN}✓ 配置文件有效${NC}"
    else
        echo -e "${RED}✗ 配置文件有错误${NC}"
        return 1
    fi
}

show_info() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}服务器信息${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"

    # 获取UUID
    UUID=$(grep -o '"id": "[^"]*"' "$XRAY_CONFIG" | head -1 | cut -d'"' -f4)

    # 获取IP
    IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo -e "  ${BLUE}Xray版本:${NC} $(/usr/local/Xray/xray -version | head -1)"
    echo -e "  ${BLUE}服务器IP:${NC} $IP"
    echo -e "  ${BLUE}监听端口:${NC} 443"
    echo -e "  ${BLUE}协议:${NC} VLESS"
    echo -e "  ${BLUE}UUID:${NC} $UUID"
    echo -e "  ${BLUE}流控:${NC} xtls-rprx-vision"
    echo -e "  ${BLUE}TLS:${NC} 自签证书"
    echo ""

    echo -e "${YELLOW}VLESS分享链接:${NC}"
    echo "vless://$UUID@$IP:443?security=tls&flow=xtls-rprx-vision&type=tcp&allowInsecure=1"
    echo ""
}

show_stats() {
    echo -e "${BLUE}═════════════════════════════════════${NC}"
    echo -e "${YELLOW}流量统计${NC}"
    echo -e "${BLUE}═════════════════════════════════════${NC}"

    echo -e "${YELLOW}内存使用:${NC}"
    ps aux | grep xray | grep -v grep | awk '{print $6 " KB"}'

    echo ""
    echo -e "${YELLOW}网络连接数:${NC}"
    netstat -an 2>/dev/null | grep :443 | wc -l

    echo ""
    echo -e "${YELLOW}最近连接:${NC}"
    if [ -f "$XRAY_LOG_ACCESS" ]; then
        tail -n 5 "$XRAY_LOG_ACCESS"
    fi
}

reload_service() {
    echo -e "${YELLOW}正在重新加载配置...${NC}"

    # 先测试配置
    if /usr/local/Xray/xray -c "$XRAY_CONFIG" -test > /dev/null 2>&1; then
        systemctl restart xray
        sleep 2
        echo -e "${GREEN}✓ 配置已重新加载${NC}"
    else
        echo -e "${RED}✗ 配置文件有错误，未重新加载${NC}"
        return 1
    fi
}

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}此脚本必须以root身份运行${NC}"
    echo "请使用: sudo bash xray-manage.sh [命令]"
    exit 1
fi

# 处理命令
case "$1" in
    status)
        show_status
        ;;
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    logs)
        show_logs
        ;;
    error)
        show_error_log
        ;;
    access)
        show_access_log
        ;;
    test)
        test_config
        ;;
    info)
        show_info
        ;;
    stats)
        show_stats
        ;;
    reload)
        reload_service
        ;;
    help)
        print_help
        ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        echo ""
        print_help
        exit 1
        ;;
esac
