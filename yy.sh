#!/bin/bash
set -e  # 如果任何命令失败，立即退出

# VPS 设置脚本

# 记录配置清单
CONFIG_LIST=""

# 函数：检查命令执行状态
check_command() {
    if [ $? -eq 0 ]; then
        printf "%s 成功\n" "$1"
        CONFIG_LIST+="$1 成功\n"
    else
        printf "%s 失败\n" "$1"
        exit 1
    fi
}

# 函数：配置 SSH
configure_ssh() {
    local ssh_port="$1"
    local ssh_public_key="$2"

    sudo sed -i "s/^#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
    check_command "SSH 端口修改"

    # 确保 root 用户的 .ssh 目录存在并设置权限
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    # 确保 authorized_keys 文件存在并设置权限
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    # 写入公钥
    echo "$ssh_public_key" >> /root/.ssh/authorized_keys
}

# 函数：启用 BBR 加速
enable_bbr() {
    echo "启用 BBR 加速..."
    echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
}

# 函数：启用 TCP Fast Open
enable_tcp_fast_open() {
    echo "启用 TCP Fast Open..."
    echo "net.ipv4.tcp_fastopen = 3" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
}

# 函数：调整 TCP 参数
adjust_tcp_parameters() {
    echo "调整 TCP 参数..."
    sudo bash -c 'cat >> /etc/sysctl.conf <<EOF
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_window_scaling = 1
net.core.somaxconn = 1024
EOF'
    sudo sysctl -p
}

# 函数：设置高性能 DNS
set_dns() {
    echo "设置高性能 DNS..."
    sudo bash -c 'cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF'
}

# 函数：优化网络接口
optimize_network_interface() {
    echo "优化网络接口..."
    # 假设网络接口为 eth0，修改为你的实际接口名称
    sudo ip link set dev eth0 mtu 1500
}

# 函数：安装 XanMod BBR v3
install_xanmod_bbr() {
    echo "准备安装 XanMod 内核..."
    
    # 检查架构
    if [ "$(uname -m)" != "x86_64" ]; then
        echo "错误: 仅支持x86_64架构"
        return 1
    fi
    
    # 检查系统
    if ! grep -Eqi "debian|ubuntu" /etc/os-release; then
        echo "错误: 仅支持Debian/Ubuntu系统"
        return 1
    fi
    
    # 注册PGP密钥
    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes
    
    # 添加存储库
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-release.list
    
    # 更新包列表
    sudo apt update -y
    
    # 尝试安装最新版本
    echo "尝试安装最新版本内核..."
    if sudo apt install -y linux-xanmod-x64v4; then
        echo "成功安装最新版本内核"
    else
        echo "最新版本安装失败，尝试安装较低版本..."
        if sudo apt install -y linux-xanmod-x64v2; then
            echo "成功安装兼容版本内核"
        else
            echo "内核安装失败"
            return 1
        fi
    fi
    
    # 启用 BBR
    enable_bbr
}

# 函数：手动编译安装BBR v3
install_bbr3_manual() {
    echo "准备手动编译安装BBR v3..."
    
    # 安装编译依赖
    sudo apt update
    sudo apt install -y build-essential git
    
    # 克隆源码
    git clone -b v3 https://github.com/google/bbr.git
    cd bbr
    
    # 编译安装
    make
    sudo make install
    
    # 启用 BBR
    enable_bbr
}

# 更新系统
sudo apt update && sudo apt upgrade -y
check_command "系统更新"

# 更改时区
sudo timedatectl set-timezone Asia/Shanghai
check_command "时区设置"

# 上传sshd_config
sudo wget -O /etc/ssh/sshd_config https://raw.githubusercontent.com/yzj160212/vpsScript/main/sshd_config
check_command "上传 sshd_config"

# 修改 SSH 端口
printf "\e[1;32m请输入自定义 SSH 端口号 (1-65535):\e[0m\n"
read -p "" SSH_PORT

# 输入验证：检查端口号是否在有效范围内
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    echo "无效的端口号，请输入一个有效的端口号 (1-65535)。"
    exit 1
fi

# 配置 SSH
printf "\e[1;32m请输入您的 SSH 公钥:\e[0m\n"
read -p "" SSH_PUBLIC_KEY

# 输入验证：检查公钥是否为空
if [ -z "$SSH_PUBLIC_KEY" ]; then
    echo "SSH 公钥不能为空。"
    exit 1
fi

configure_ssh "$SSH_PORT" "$SSH_PUBLIC_KEY"

# 重启 SSH
sudo service sshd restart

# 安装 fail2ban
sudo apt install fail2ban -y
check_command "fail2ban 安装"

# 上传 fail2ban 配置文件
sudo wget -O /etc/fail2ban/jail.local https://raw.githubusercontent.com/yzj160212/vpsScript/main/jail.local
check_command "上传 fail2ban 配置文件"

# 重启 fail2ban 服务
sudo systemctl restart fail2ban
check_command "fail2ban 服务重启"

# 安装和启用 UFW 防火墙
sudo apt install ufw -y
check_command "UFW 安装"

# 允许 SSH 端口
sudo ufw allow "$SSH_PORT"/tcp
check_command "放行 SSH 端口 $SSH_PORT"

# 允许 HTTP 和 HTTPS 端口
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
check_command "放行 HTTP 和 HTTPS 端口"

# 启用 UFW
sudo ufw enable
check_command "UFW 启用"

# 验证 fail2ban 是否安装
if systemctl is-active --quiet fail2ban; then
    echo "fail2ban 服务正在运行"
    CONFIG_LIST+="fail2ban 服务正在运行\n"
else
    echo "fail2ban 服务未运行"
    exit 1
fi

# 重启服务器后自动重启 fail2ban 服务
sudo systemctl enable fail2ban
check_command "fail2ban 服务设置为开机自启动"

# 执行网络优化设置
enable_bbr
enable_tcp_fast_open
adjust_tcp_parameters
set_dns
optimize_network_interface

# 安装 BBR v3
printf "\e[1;32m请选择安装 BBR v3 的方式:\n1. 安装 XanMod BBR v3\n2. 手动编译 BBR v3\n3. 跳过安装\e[0m\n"
read -p "请输入选项 [1-3]: " choice

case "$choice" in
    1)
        install_xanmod_bbr
        ;;
    2)
        install_bbr3_manual
        ;;
    3)
        echo "跳过 BBR v3 安装"
        ;;
    *)
        echo "无效的选择"
        exit 1
        ;;
esac

echo "网络优化设置完成！"


