#!/bin/bash

# VPS 设置脚本

# 记录配置清单
CONFIG_LIST=""

# 更新系统
sudo apt update && sudo apt upgrade -y
if [ $? -eq 0 ]; then
    echo "系统更新成功"
    CONFIG_LIST+="系统更新成功\n"
else
    echo "系统更新失败"
    exit 1
fi

# 更改时区
sudo timedatectl set-timezone Asia/Shanghai
if [ $? -eq 0 ]; then
    echo "时区设置成功"
    CONFIG_LIST+="时区设置为 Asia/Shanghai\n"
else
    echo "时区设置失败"
    exit 1
fi

# 上传sshd_config
sudo wget -O /etc/ssh/sshd_config https://raw.githubusercontent.com/yzj160212/vpsScript/main/sshd_config

# 修改 SSH 端口
echo -e "\e[1;32m请输入自定义 SSH 端口号:\e[0m"
read -p "" SSH_PORT
sudo sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
if [ $? -eq 0 ]; then
    echo "SSH 端口修改成功"
    CONFIG_LIST+="SSH 端口设置为 $SSH_PORT\n"
else
    echo "SSH 端口修改失败"
    exit 1
fi

# 重启 SSH
sudo service sshd restart

# 创建新用户
echo -e "\e[1;32m请输入新用户名称:\e[0m"
read -p "" NEW_USER
sudo adduser $NEW_USER
if [ $? -eq 0 ]; then
    echo "新用户 $NEW_USER 创建成功"
    CONFIG_LIST+="新用户 $NEW_USER 创建成功\n"
else
    echo "新用户创建失败"
    exit 1
fi

# 安装 sudo
sudo apt install sudo -y
if [ $? -eq 0 ]; then
    echo "sudo 安装成功"
    CONFIG_LIST+="sudo 安装成功\n"
else
    echo "sudo 安装失败"
    exit 1
fi

# 配置 sudo 权限
sudo visudo -c
if [ $? -eq 0 ]; then
    echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers
    echo "sudo 权限配置成功"
    CONFIG_LIST+="用户 $NEW_USER 配置 sudo 权限成功\n"
else
    echo "sudo 权限配置失败"
    exit 1
fi

# 禁止 root 登录
sudo sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
if [ $? -eq 0 ]; then
    echo "禁止 root 登录设置成功"
    CONFIG_LIST+="禁止 root 登录设置成功\n"
else
    echo "禁止 root 登录设置失败"
    exit 1
fi

# 配置 SSH 密钥登录
echo -e "\e[1;32m请输入您的 SSH 公钥:\e[0m"
read -p "" SSH_PUBLIC_KEY

# 确保新用户的 .ssh 目录存在并设置权限
sudo mkdir -p /home/$NEW_USER/.ssh
sudo chmod 700 /home/$NEW_USER/.ssh

# 确保 authorized_keys 文件存在并设置权限
sudo touch /home/$NEW_USER/.ssh/authorized_keys
sudo chmod 600 /home/$NEW_USER/.ssh/authorized_keys

# 写入公钥
echo "$SSH_PUBLIC_KEY" | sudo tee -a /home/$NEW_USER/.ssh/authorized_keys

# 重启 SSH
sudo service sshd restart

# 安装 fail2ban
sudo apt install fail2ban -y
if [ $? -eq 0 ]; then
    echo "fail2ban 安装成功"
    CONFIG_LIST+="fail2ban 安装成功\n"
else
    echo "fail2ban 安装失败"
    exit 1
fi

# 上传 fail2ban 配置文件
sudo wget -O /etc/fail2ban/jail.conf https://raw.githubusercontent.com/yzj160212/vpsScript/main/jail.conf

# 重启 fail2ban 服务
sudo systemctl restart fail2ban
if [ $? -eq 0 ]; then
    echo "fail2ban 服务重启成功"
    CONFIG_LIST+="fail2ban 服务重启成功\n"
else
    echo "fail2ban 服务重启失败"
    exit 1
fi

# 安装和启用 UFW 防火墙
sudo apt install ufw -y
if [ $? -eq 0 ]; then
    echo "UFW 安装成功"
    CONFIG_LIST+="UFW 安装成功\n"
else
    echo "UFW 安装失败"
    exit 1
fi

# 允许 SSH 端口
sudo ufw allow $SSH_PORT/tcp
if [ $? -eq 0 ]; then
    echo "放行 SSH 端口 $SSH_PORT 成功"
    CONFIG_LIST+="放行 SSH 端口 $SSH_PORT 成功\n"
else
    echo "放行 SSH 端口 $SSH_PORT 失败"
    exit 1
fi

# 允许 HTTP 和 HTTPS 端口
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
if [ $? -eq 0 ]; then
    echo "放行 HTTP 和 HTTPS 端口成功"
    CONFIG_LIST+="放行 HTTP 和 HTTPS 端口成功\n"
else
    echo "放行 HTTP 和 HTTPS 端口失败"
    exit 1
fi

# 启用 UFW
sudo ufw enable
if [ $? -eq 0 ]; then
    echo "UFW 启用成功"
    CONFIG_LIST+="UFW 启用成功\n"
else
    echo "UFW 启用失败"
    exit 1
fi

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
if [ $? -eq 0 ]; then
    echo "fail2ban 服务设置为开机自启动"
    CONFIG_LIST+="fail2ban 服务设置为开机自启动\n"
else
    echo "fail2ban 服务设置为开机自启动失败"
    exit 1
fi

# 输出配置清单
echo -e "\n配置清单:\n$CONFIG_LIST" > vps_configuration_summary.txt

# 提示用户复制配置清单
echo "配置清单已保存到 vps_configuration_summary.txt"
