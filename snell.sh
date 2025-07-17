#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 基础配置
SERVICE_NAME="snell.service"
INSTALL_DIR="/usr/local/bin"
CONF_DIR="/etc/snell"
CONF_FILE="${CONF_DIR}/snell-server.conf"
SYSTEMD_SERVICE_FILE="/lib/systemd/system/snell.service"

# 版本和架构配置
VERSION="v5.0.0"
ARCH="$(arch)"

# 构造下载链接
if [[ "$ARCH" == "aarch64" ]]; then
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
else
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
fi

# 提取下载压缩文件版本号（用于展示）
VERSION_PARSED=$(basename "$SNELL_URL" | sed -nE 's/^snell-server-(v[0-9]+\.[0-9]+\.[a-zA-Z0-9]+)-.*/\1/p')

# 检测系统类型（只支持debian）
get_system_type() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# 等待包管理器锁
wait_for_package_manager() {
    local system_type="$(get_system_type)"
    if [ "$system_type" = "debian" ]; then
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
           || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 \
           || fuser /var/cache/apt/archives/lock >/dev/null 2>&1 \
           || pgrep -x apt >/dev/null 2>&1; do
            echo -e "${YELLOW}等待其他 apt 进程完成${RESET}"
            sleep 1
        done
    fi
}

# 安装必要的软件包
install_required_packages() {
    echo -e "${GREEN}安装必要的软件包${RESET}"
    apt-get update -q
    apt-get install -y -q wget unzip curl
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请以 root 权限运行此脚本.${RESET}"
        exit 1
    fi
}

# 检查 Snell 是否已安装
check_snell_installed() {
    if command -v snell-server &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 检查 Snell 是否正在运行
check_snell_running() {
    systemctl is-active --quiet "$SERVICE_NAME"
    return $?
}

# 启动 Snell 服务
start_snell() {
    systemctl start "$SERVICE_NAME"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 启动成功${RESET}"
    else
        echo -e "${RED}Snell 启动失败${RESET}"
    fi
}

# 停止 Snell 服务
stop_snell() {
    systemctl stop "$SERVICE_NAME"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 停止成功${RESET}"
    else
        echo -e "${RED}Snell 停止失败${RESET}"
    fi
}

# 安装 Snell
install_snell() {
    echo -e "${GREEN}正在安装 Snell${RESET}"

    # 等待包管理器
    wait_for_package_manager

    # 安装必要的软件包
    if ! install_required_packages; then
        echo -e "${RED}安装必要软件包失败，请检查您的网络连接。${RESET}"
        exit 1
    fi

    # 下载 Snell 服务器文件
    wget -q "${SNELL_URL}" -O snell-server.zip
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载 Snell 失败。${RESET}"
        exit 1
    fi

    # 解压缩文件到指定目录
    unzip -o -q snell-server.zip -d "${INSTALL_DIR}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}解压缩 Snell 失败。${RESET}"
        exit 1
    fi

    # 删除下载的 zip 文件
    rm -f snell-server.zip

    # 赋予执行权限
    chmod +x "${INSTALL_DIR}/snell-server"

    # 生成随机端口和密码
    RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
    RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

    # 检查 snell 用户是否已存在
    if ! id "snell" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin snell
    fi

    # 创建配置文件目录
    mkdir -p "${CONF_DIR}"

    # 创建配置文件
    cat > "${CONF_FILE}" << EOF
[snell-server]
listen = ::0:${RANDOM_PORT}
psk = ${RANDOM_PSK}
ipv6 = true
EOF

    # 创建 Systemd 服务文件
    cat > "${SYSTEMD_SERVICE_FILE}" << EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=snell
Group=snell
ExecStart=${INSTALL_DIR}/snell-server -c ${CONF_FILE}
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW
LimitNOFILE=32768
Restart=on-failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF

    # 重载 Systemd 配置
    systemctl daemon-reload
    if [ $? -ne 0 ]; then
        echo -e "${RED}重载 Systemd 配置失败。${RESET}"
        exit 1
    fi

    # 开机自启动 Snell
    systemctl enable snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}开机自启动 Snell 失败。${RESET}"
        exit 1
    fi

    # 启动 Snell 服务
    systemctl start snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}启动 Snell 服务失败。${RESET}"
        exit 1
    fi

    # 查看 Snell 日志
    echo -e "${GREEN}Snell 安装成功${RESET}"
    sleep 3 && journalctl -u snell.service -n 8 --no-pager

    # 获取本机IP地址
    HOST_IP=$(curl -s http://checkip.amazonaws.com)

    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)

    echo -e "${GREEN}Snell 示例配置，非TF版本请改为version = 4${RESET}"
    cat << EOF > /etc/snell/config.txt
${IP_COUNTRY} = snell, ${HOST_IP}, ${RANDOM_PORT}, psk = ${RANDOM_PSK}, version = 5, reuse = true
EOF
    cat /etc/snell/config.txt
}

# 更新 Snell
update_snell() {
    if [ ! -f "${INSTALL_DIR}/snell-server" ]; then
        echo -e "${YELLOW}Snell 未安装，跳过更新${RESET}"
        return
    fi

    echo -e "${GREEN}Snell 正在更新${RESET}"

    # 停止 Snell
    systemctl stop snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}停止 Snell 失败。${RESET}"
        exit 1
    fi

    # 等待包管理器
    wait_for_package_manager

    # 安装必要的软件包
    if ! install_required_packages; then
        echo -e "${RED}安装必要软件包失败，请检查您的网络连接。${RESET}"
        exit 1
    fi

    # 下载并安装新版本
    wget -q "${SNELL_URL}" -O snell-server.zip
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载 Snell 失败。${RESET}"
        exit 1
    fi

    unzip -o -q snell-server.zip -d "${INSTALL_DIR}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}解压缩 Snell 失败。${RESET}"
        exit 1
    fi

    rm -f snell-server.zip
    chmod +x "${INSTALL_DIR}/snell-server"

    systemctl restart snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}重启 Snell 失败。${RESET}"
        exit 1
    fi

    echo -e "${GREEN}Snell 更新成功，非TF版本请改为version = 4${RESET}"
    cat /etc/snell/config.txt
}

# 卸载 Snell
uninstall_snell() {
    echo -e "${GREEN}正在卸载 Snell${RESET}"

    systemctl stop snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}停止 Snell 服务失败。${RESET}"
        exit 1
    fi

    systemctl disable snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}禁用开机自启动失败。${RESET}"
        exit 1
    fi

    rm -f /lib/systemd/system/snell.service
    if [ $? -ne 0 ]; then
        echo -e "${RED}删除 Systemd 服务文件失败。${RESET}"
        exit 1
    fi

    systemctl daemon-reload
    rm -f /usr/local/bin/snell-server
    rm -rf /etc/snell

    echo -e "${GREEN}Snell 卸载成功${RESET}"
}

# 显示菜单
show_menu() {
    clear
    check_snell_installed
    snell_installed=$?
    check_snell_running
    snell_running=$?

    if [ $snell_installed -eq 0 ]; then
        installation_status="${GREEN}已安装${RESET}"
        version_status="${GREEN}${VERSION_PARSED}${RESET}"

        if [ $snell_running -eq 0 ]; then
            running_status="${GREEN}已启动${RESET}"
        else
            running_status="${RED}未启动${RESET}"
        fi
    else
        installation_status="${RED}未安装${RESET}"
        running_status="${RED}未启动${RESET}"
        version_status="—"
    fi

    echo -e "${CYAN}╔══════════════════════════════╗${RESET}"
    echo -e "${CYAN}║        🚀 Snell Proxy         ║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════╝${RESET}"
    echo -e "安装状态: ${installation_status}"
    echo -e "运行状态: ${running_status}"
    echo -e "运行版本: ${version_status}"
    echo ""
    echo "1. 安装 Snell 服务"
    echo "2. 卸载 Snell 服务"
    if [ $snell_installed -eq 0 ]; then
        if [ $snell_running -eq 0 ]; then
            echo "3. 停止 Snell 服务"
        else
            echo "3. 启动 Snell 服务"
        fi
    fi
    echo "4. 更新 Snell 服务"
    echo "5. 查看 Snell 配置"
    echo "0. 退出"
    echo -e "${CYAN}════════════════════════════════${RESET}"
    while true; do
        read -p "请输入选项编号: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            break
        else
            echo -e "${RED}无效的选项${RESET}"
        fi
    done
    echo ""
}

# 捕获 Ctrl+C 信号
trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

# 主循环
main() {
    if [ "$(get_system_type)" != "debian" ]; then
        echo -e "${RED}本脚本仅支持 Debian 系统${RESET}"
        exit 1
    fi

    check_root

    # touch "$LOG_FILE"
    # chmod 644 "$LOG_FILE"

    while true; do
        show_menu
        case "${choice}" in
            1)
                install_snell
                ;;
            2)
                if [ $snell_installed -eq 0 ]; then
                    uninstall_snell
                else
                    echo -e "${RED}Snell 尚未安装${RESET}"
                fi
                ;;
            3)
                if [ $snell_installed -eq 0 ]; then
                    if [ $snell_running -eq 0 ]; then
                        stop_snell
                    else
                        start_snell
                    fi
                else
                    echo -e "${RED}Snell 尚未安装${RESET}"
                fi
                ;;
            4)
                update_snell
                ;;
            5)
                if [ -f /etc/snell/config.txt ]; then
                    cat /etc/snell/config.txt
                else
                    echo -e "${RED}配置文件不存在${RESET}"
                fi
                ;;
            0)
                echo -e "${GREEN}已退出 Snell 管理工具${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选项${RESET}"
                ;;
        esac
        read -p "按 enter 键继续..."
    done
}

main