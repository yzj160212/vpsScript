#!/bin/bash

# 颜色代码定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 日志输出函数（带时间戳）
log_info()  { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*${RESET}"; }
log_warn()  { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*${RESET}"; }
log_error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*${RESET}"; }

# 变量集中定义
SERVICE_NAME="snell.service"
INSTALL_DIR="/usr/local/bin"
CONF_DIR="/etc/snell"
CONF_FILE="${CONF_DIR}/snell-server.conf"
SYSTEMD_SERVICE_FILE="/lib/systemd/system/snell.service"

# 版本和架构配置
VERSION="v5.0.0b3"
ARCH="$(arch)"

# 构造下载链接
if [[ "$ARCH" == "aarch64" ]]; then
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
else
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
fi

# 提取下载压缩文件版本号（用于展示）
VERSION_PARSED=$(basename "$SNELL_URL" | sed -nE 's/^snell-server-(v[0-9]+\.[0-9]+\.[a-zA-Z0-9]+)-.*/\1/p')

# 统一错误处理函数
error_exit() {
    log_error "$1"
    exit 1
}

# 统一成功退出函数
success_exit() {
    log_info "$1"
    exit 0
}

# 临时文件清理函数
cleanup_temp() {
    [ -f snell-server.zip ] && rm -f snell-server.zip
}

# 捕获 EXIT 信号，自动清理临时文件并提示
trap 'cleanup_temp; log_info "脚本已退出，临时文件已清理。"' EXIT

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
            log_warn "等待其他 apt 进程完成"
            sleep 1
        done
    fi
}

# 安装必要的软件包
install_required_packages() {
    log_info "安装必要的软件包"
    apt-get update -q
    [ $? -eq 0 ] || error_exit "apt-get update 失败"
    apt-get install -y -q wget unzip curl
    [ $? -eq 0 ] || error_exit "安装 wget unzip curl 失败"
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" != "0" ]; then
        error_exit "请以 root 权限运行此脚本."
    fi
}

# 检查 Snell 是否已安装
check_snell_installed() {
    if [[ -x "${INSTALL_DIR}/snell-server" ]]; then
        return 0
    else
        return 1
    fi
}

# 检查 Snell 是否正在运行
check_snell_running() {
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        if ! systemctl status "$SERVICE_NAME" &>/dev/null; then
            log_warn "无法获取 Snell 服务状态，systemctl 命令失败"
            systemctl status "$SERVICE_NAME"
            return 1
        fi
        systemctl status "$SERVICE_NAME"
        return 1
    fi
    return 0
}

# 启用 Snell 服务
enable_snell_service() {
    systemctl enable snell
    [ $? -eq 0 ] || error_exit "开机自启动 Snell 失败"
}

# 重启 Snell 服务
restart_snell_service() {
    systemctl restart snell
    [ $? -eq 0 ] || error_exit "重启 Snell 失败"
}

# 重新加载 systemd 配置
reload_snell_service() {
    systemctl daemon-reload
    [ $? -eq 0 ] || error_exit "重载 Systemd 配置失败"
}

# 显示 Snell 服务日志
show_svc_log() {
    if command -v journalctl &>/dev/null; then
        journalctl -u snell.service -n 8 --no-pager
    else
        systemctl status snell
    fi
}

# 下载 Snell 文件
# 参数：无
# 结果：下载 snell-server.zip 到当前目录
# 失败自动 error_exit
download_snell() {
    echo "正在下载 Snell..."
    if ! command -v wget &>/dev/null; then
        error_exit "wget 命令不存在，请先安装 wget"
    fi
    wget -q "${SNELL_URL}" -O snell-server.zip
    [ $? -eq 0 ] || error_exit "下载 Snell 失败"
}

# 解压 Snell 文件到安装目录
extract_snell() {
    echo "正在解压 Snell..."
    if ! command -v unzip &>/dev/null; then
        error_exit "unzip 命令不存在，请先安装 unzip"
    fi
    unzip -o -q snell-server.zip -d "${INSTALL_DIR}"
    [ $? -eq 0 ] || error_exit "解压 Snell 失败"
}

# 赋予 snell-server 执行权限
set_snell_permission() {
    chmod +x "${INSTALL_DIR}/snell-server"
    [ $? -eq 0 ] || error_exit "赋予执行权限失败"
}

# 生成主配置文件
# 参数：端口、密码
# 用于 install_snell
# 结果：写入 ${CONF_FILE}
generate_snell_config() {
    local port="$1"
    local psk="$2"
    cat > "${CONF_FILE}" << EOF
[snell-server]
listen = ::0:${port}
psk = ${psk}
ipv6 = true
EOF
    [ $? -eq 0 ] || error_exit "写入配置文件失败"
}

# 生成随机端口
# 增加最大尝试次数和命令可用性检查
generate_random_port() {
    if ! command -v shuf &>/dev/null; then
        error_exit "shuf 命令不存在，请先安装 coreutils"
    fi
    if ! command -v ss &>/dev/null; then
        error_exit "ss 命令不存在，请先安装 iproute2"
    fi
    local try=0
    while true; do
        local port=$(shuf -i 30000-63000 -n 1)
        ss -lnt | awk '{print $4}' | grep -q ":$port$" || { echo "$port"; return; }
        try=$((try+1))
        [ $try -ge 10 ] && error_exit "无法找到可用端口，请检查端口占用"
    done
}

# 一键准备 Snell 二进制文件及依赖
setup_snell() {
    wait_for_package_manager
    install_required_packages
    download_snell
    extract_snell
    set_snell_permission
}

# 安装或更新 Snell 公共核心逻辑
# 参数1: install/new 或 update
install_or_update_snell_core() {
    local mode="$1" # install 或 update
    echo "开始${mode} Snell 版本: ${VERSION_PARSED}"
    setup_snell
    # 版本号校验
    local ACTUAL_VERSION
    ACTUAL_VERSION=$("${INSTALL_DIR}/snell-server" --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[a-zA-Z0-9]+')
    if [[ "$ACTUAL_VERSION" != "$VERSION_PARSED" ]]; then
        error_exit "版本号不匹配: 期望 ${VERSION_PARSED}, 实际 ${ACTUAL_VERSION}"
    fi
    if [ "$mode" = "install" ]; then
        local RANDOM_PORT RANDOM_PSK
        RANDOM_PORT=$(generate_random_port)
        [ $? -eq 0 ] || error_exit "生成随机端口失败"
        RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)
        [ $? -eq 0 ] || error_exit "生成随机密码失败"
        if ! id "snell" &>/dev/null; then
            useradd -r -s /usr/sbin/nologin snell
            [ $? -eq 0 ] || error_exit "创建 snell 用户失败"
        fi
        mkdir -p "${CONF_DIR}"
        [ $? -eq 0 ] || error_exit "创建配置目录失败"
        generate_snell_config "$RANDOM_PORT" "$RANDOM_PSK"
    else
        local CUR_PORT CUR_PSK
        if [ -f "${CONF_FILE}" ]; then
            CUR_PORT=$(grep '^listen' "${CONF_FILE}" | awk -F: '{print $NF}')
            CUR_PSK=$(grep '^psk' "${CONF_FILE}" | awk -F= '{print $2}' | xargs)
        else
            CUR_PORT=$(generate_random_port)
            CUR_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)
        fi
        generate_snell_config "$CUR_PORT" "$CUR_PSK"
    fi
    cat > "${SYSTEMD_SERVICE_FILE}" << EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=snell
Group=snell
ExecStart=${INSTALL_DIR}/snell-server -c ${CONF_FILE}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "${SYSTEMD_SERVICE_FILE}"
    [ $? -eq 0 ] || error_exit "设置 systemd 服务文件权限失败"
    reload_snell_service
    enable_snell_service
    restart_snell_service
    echo "Snell ${mode}成功，版本: ${VERSION_PARSED}"
    show_svc_log
}

install_snell() {
    install_or_update_snell_core install
}

update_snell() {
    if [ ! -f "${INSTALL_DIR}/snell-server" ]; then
        log_warn "Snell 未安装，跳过更新"
        return
    fi
    install_or_update_snell_core update
}

# 卸载 Snell
uninstall_snell() {
    log_info "正在卸载 Snell"
    systemctl stop snell
    [ $? -eq 0 ] || error_exit "停止 Snell 服务失败"
    systemctl disable snell
    [ $? -eq 0 ] || error_exit "禁用开机自启动失败"
    rm -f "${SYSTEMD_SERVICE_FILE}"
    [ $? -eq 0 ] || error_exit "删除 Systemd 服务文件失败"
    systemctl daemon-reload
    rm -f "${INSTALL_DIR}/snell-server"
    rm -rf "${CONF_DIR}"
    log_info "Snell 卸载成功"
}

# 启动 Snell 服务
start_snell() {
    systemctl start snell
    [ $? -eq 0 ] || error_exit "启动 Snell 失败"
}

# 停止 Snell 服务
stop_snell() {
    systemctl stop snell
    [ $? -eq 0 ] || error_exit "停止 Snell 失败"
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
            log_info "3. 停止 Snell 服务"
        else
            running_status="${RED}未启动${RESET}"
            log_info "3. 启动 Snell 服务"
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
    echo "4. 更新 Snell 服务"
    echo "5. 查看 Snell 配置"
    echo "0. 退出"
    echo -e "${CYAN}════════════════════════════════${RESET}"
    while true; do
        read -p "请输入选项编号: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le 5 ]; then
            break
        else
            echo -e "${RED}无效的选项，请输入 0-5 之间的数字${RESET}"
        fi
    done
    echo ""
}

# 处理菜单选项逻辑
handle_menu_choice() {
    case "$1" in
        1)
            install_snell
            ;;
        2)
            check_snell_installed
            snell_installed=$?
            if [ $snell_installed -eq 0 ]; then
                uninstall_snell
            else
                log_error "Snell 尚未安装"
            fi
            ;;
        3)
            check_snell_installed
            snell_installed=$?
            check_snell_running
            snell_running=$?
            if [ $snell_installed -eq 0 ]; then
                if [ $snell_running -eq 0 ]; then
                    stop_snell
                else
                    start_snell
                fi
            else
                log_error "Snell 尚未安装"
            fi
            ;;
        4)
            update_snell
            ;;
        5)
            if [ -f "${CONF_FILE}" ]; then
                cat "${CONF_FILE}"
            else
                log_error "配置文件不存在"
            fi
            ;;
        0)
            success_exit "已退出 Snell 管理工具"
            ;;
        *)
            log_error "无效的选项"
            ;;
    esac
}

main() {
    if [ "$(get_system_type)" != "debian" ]; then
        error_exit "本脚本仅支持 Debian 系统"
    fi
    check_root
    while true; do
        show_menu
        handle_menu_choice "$choice"
        read -p "按 enter 键继续..."
    done
}

main