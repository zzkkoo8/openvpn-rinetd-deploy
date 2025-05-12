#!/bin/bash

# 永久关闭系统防火墙并开启系统转发功能
sudo ufw disable  # 关闭防火墙，避免端口限制
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf  # 启用IP转发，支持VPN流量
sudo sysctl -p  # 应用系统配置

# 安装expect工具，用于自动化OpenVPN安装
sudo apt-get update  # 更新软件包列表
sudo apt-get install expect curl iproute2 -y  # 安装expect，自动处理交互式输入和其它工具

# 下载并准备OpenVPN一键部署脚本
curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh  # 下载OpenVPN安装脚本
chmod +x openvpn-install.sh  # 赋予执行权限

# 创建expect脚本以自动填入OpenVPN参数（TCP协议，端口31500）
cat <<EOF > install_openvpn.exp
#!/usr/bin/expect -f
set timeout -1  # 设置无超时限制
spawn ./openvpn-install.sh  # 启动OpenVPN安装脚本
expect "IP address:"  # 等待IP地址提示
send "\r"  # 接受默认IP，按回车
expect "Protocol [UDP]:"  # 等待协议选择提示
send "TCP\r"  # 选择TCP协议
expect "Port [1194]:"  # 等待端口提示
send "31500\r"  # 设置端口为31500
expect "DNS [1]:"  # 等待DNS选择提示
send "\r"  # 接受默认DNS
expect "Client name [client]:"  # 等待客户端名称提示
send "\r"  # 接受默认名称
expect "Press any key to continue..."  # 等待继续提示
send "\r"  # 按任意键继续
expect eof  # 等待脚本执行结束
EOF

# 执行OpenVPN安装
chmod +x install_openvpn.exp  # 赋予expect脚本执行权限
./install_openvpn.exp  # 运行expect脚本，自动安装OpenVPN

# 安装rinetd并追加端口转发配置
sudo apt-get install rinetd -y  # 安装rinetd，用于端口转发
cat <<EOF | sudo tee -a /etc/rinetd.conf  # 添加端口转发规则到配置文件
# Pi-Node端口转发配置
0.0.0.0 31400 10.8.0.2 31400  # 转发31400端口
0.0.0.0 31401 10.8.0.2 31401  # 转发31401端口
0.0.0.0 31402 10.8.0.2 31402  # 转发31402端口
0.0.0.0 31403 10.8.0.2 31403  # 转发31403端口
0.0.0.0 31404 10.8.0.2 31404  # 转发31404端口
0.0.0.0 31405 10.8.0.2 31405  # 转发31405端口
0.0.0.0 31406 10.8.0.2 31406  # 转发31406端口
0.0.0.0 31407 10.8.0.2 31407  # 转发31407端口
0.0.0.0 31408 10.8.0.2 31408  # 转发31408端口
0.0.0.0 31409 10.8.0.2 31409  # 转发31409端口
0.0.0.0 825 10.8.0.2 825      # 转发825端口
EOF

# 重启rinetd以应用配置
sudo systemctl restart rinetd  # 重启rinetd服务，使配置生效

echo "部署完成！"  # 提示用户部署已完成
#!/bin/bash

# 获取并输出系统基本信息
echo "=== 系统基本信息 ==="
echo "系统版本:"
lsb_release -a 2>/dev/null || cat /etc/os-release
echo -e "\n内核版本:"
uname -r
echo -e "\nCPU 信息:"
lscpu | grep -E "Model name|Architecture|CPU\(s\)"
echo -e "\n内存信息:"
free -h | grep -E "Mem|Swap"

# 获取并输出公网 IP
echo -e "\n=== 网络信息 ==="
echo "公网 IP:"
curl -s ifconfig.me || echo "无法获取公网 IP，请检查网络连接"

# 输出 OpenVPN 配置文件路径
echo -e "\n=== OpenVPN 配置信息 ==="
echo "OpenVPN 服务器配置文件: /etc/openvpn/server.conf"
echo "OpenVPN 客户端配置文件: /root/client.ovpn"

# 检查端口转发是否成功
echo -e "\n=== 端口转发状态 ==="
PORTS="31400 31401 31402 31403 31404 31405 31406 31407 31408 31409 825"
for port in $PORTS; do
    if ss -tuln | grep -q ":$port "; then
        echo "端口 $port: 转发成功"
    else
        echo "端口 $port: 转发失败"
    fi
done

# 总结本次部署信息
echo -e "\n=== 本次部署信息总结 ==="
echo "系统公网 IP: $(curl -s ifconfig.me || echo "获取失败")"
echo "OpenVPN 服务器配置文件路径: /etc/openvpn/server.conf"
echo "OpenVPN 客户端配置文件路径: /root/client.ovpn"
echo "端口转发状态（以 31400 为例）: $(if ss -tuln | grep -q ":31400 "; then echo "成功"; else echo "失败"; fi)"
