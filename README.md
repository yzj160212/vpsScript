### 一键装机（debian10专用）
```
wget https://raw.githubusercontent.com/yzj160212/vpsScript/main/vps_installation.sh -O vps_installation.sh && chmod +x vps_installation.sh && sudo ./vps_installation.sh
```

### 一键snell（只支持debian）
```
bash <(curl -fsSL snell-yy.vercel.app)
```

## 常用指令

| 命令                                     | 说明               |
|------------------------------------------|--------------------|
| `sudo systemctl stop snell`              | 停止 Snell 服务     |
| `sudo systemctl start snell`             | 启动 Snell 服务     |
| `sudo systemctl restart snell`           | 重启 Snell 状态     |
| `sudo systemctl status snell`            | 查看 Snell 服务     |
| `sudo journalctl -u snell.service -f`    | 查看 Snell 日志     |
| `sudo cat /etc/snell/snell-server.conf`  | 查看 Snell 配置     |
| `sudo vim /etc/snell/snell-server.conf`  | 修改 Snell 配置     |