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