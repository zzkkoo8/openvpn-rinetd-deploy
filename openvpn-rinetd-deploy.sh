#!/bin/bash
# 自动部署 OpenVPN 和 rinetd 脚本 (适用于 Ubuntu 24)
# 1. 关闭防火墙 (ufw, nftables)，开启内核转发 (IPv4/IPv6)
# 2. 安装所需软件 (curl, expect, openvpn, rinetd 等)
# 3. 下载并自动执行 OpenVPN 一键安装脚本 (协议：TCP，端口：31500)
# 4. 安装 rinetd 并添加端口转发规则，然后重启 rinetd
# 5. 检查部署状态 (OpenVPN 和 rinetd 服务、端口监听、客户端配置)
set -e
trap 'echo "错误：脚本在第${LINENO}行执行失败。"; exit 1' ERR

# 确认以 root 身份运行
if [[ $EUID -ne 0 ]]; then
    echo "请以 root 身份运行此脚本。" >&2
    exit 1
fi

echo "=== 开始部署 OpenVPN + rinetd (Ubuntu 24) ==="

## 1. 禁用防火墙并开启内核转发
echo ">>> 关闭 ufw 防火墙 (如有安装) ..."
if command -v ufw >/dev/null 2>&1; then
    ufw disable
    systemctl disable ufw >/dev/null 2>&1 || true
fi
echo ">>> 关闭 nftables 防火墙 (如有安装) ..."
systemctl disable --now nftables >/dev/null 2>&1 || true
# 清理现有 iptables 规则，允许所有流量
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
ip6tables -F
ip6tables -t nat -F
ip6tables -t mangle -F
ip6tables -X
ip6tables -P INPUT ACCEPT
ip6tables -P FORWARD ACCEPT
ip6tables -P OUTPUT ACCEPT

echo ">>> 启用内核 IPv4/IPv6 转发..."
# 防止重复添加配置项
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" | tee -a /etc/sysctl.conf
grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" | tee -a /etc/sysctl.conf
grep -q "^net.ipv6.conf.default.forwarding=1" /etc/sysctl.conf || echo "net.ipv6.conf.default.forwarding=1" | tee -a /etc/sysctl.conf
sysctl -p

## 2. 更新软件包列表并安装必要依赖
echo ">>> 更新软件包列表..."
apt-get update -y
echo ">>> 安装 curl, expect, iproute2, openvpn, rinetd 等..."
apt-get install -y curl expect iproute2 openvpn rinetd

## 3. 下载并执行 OpenVPN 一键安装脚本 (协议: TCP, 端口: 31500)
echo ">>> 下载 OpenVPN 一键安装脚本..."
if ! wget -q -O openvpn-install.sh https://git.io/vpn; then
    echo "错误：无法下载 OpenVPN 安装脚本。" >&2
    exit 1
fi
chmod +x openvpn-install.sh

echo ">>> 使用 expect 自动填写安装参数 (协议: TCP, 端口: 31500)..."
cat << 'EOF' > install_openvpn.exp
#!/usr/bin/expect -f
set timeout -1
spawn ./openvpn-install.sh
expect "IP address"
send "\r"
expect "Protocol"
send "2\r"
expect "Port"
send "31500\r"
expect "DNS"
send "\r"
expect "Client name"
send "\r"
expect "Press any key"
send "\r"
expect eof
EOF
chmod +x install_openvpn.exp

echo ">>> 运行 OpenVPN 安装脚本..."
./install_openvpn.exp

## 4. 安装 rinetd 并追加端口转发配置
echo ">>> 安装 rinetd (端口转发工具)..."
apt-get install -y rinetd

echo ">>> 配置 rinetd 端口转发规则..."
cat << EOF >> /etc/rinetd.conf
# Pi-Node节点端口转发
0.0.0.0 31400 10.8.0.2 31400
0.0.0.0 31401 10.8.0.2 31401
0.0.0.0 31402 10.8.0.2 31402
0.0.0.0 31403 10.8.0.2 31403
0.0.0.0 31404 10.8.0.2 31404
0.0.0.0 31405 10.8.0.2 31405
0.0.0.0 31406 10.8.0.2 31406
0.0.0.0 31407 10.8.0.2 31407
0.0.0.0 31408 10.8.0.2 31408
0.0.0.0 31409 10.8.0.2 31409
0.0.0.0 825   10.8.0.2 825
EOF
echo ">>> 重启 rinetd 服务以应用配置..."
systemctl restart rinetd

## 5. 部署状态检查
echo "=== 部署状态检查 ==="
echo "OpenVPN 服务检查:"
if systemctl is-active openvpn-server@server.service >/dev/null 2>&1 || pgrep -x openvpn >/dev/null 2>&1; then
    echo "  - OpenVPN: 正在运行"
else
    echo "  - OpenVPN: 未运行"
fi
# 检查 OpenVPN 监听端口
if ss -tuln | grep -q ':31500'; then
    echo "  - 端口 31500: 已监听"
else
    echo "  - 端口 31500: 未监听"
fi
# 检查客户端配置文件
if [[ -f /root/client.ovpn ]]; then
    echo "  - 客户端配置文件 (/root/client.ovpn): 已生成"
else
    echo "  - 客户端配置文件 (/root/client.ovpn): 未找到"
fi

echo "rinetd 服务检查:"
if systemctl is-active rinetd >/dev/null 2>&1; then
    echo "  - rinetd: 正在运行"
else
    echo "  - rinetd: 未运行"
fi
echo "rinetd 转发端口监听情况:"
for port in 31400 31401 31402 31403 31404 31405 31406 31407 31408 31409 825; do
    if ss -tuln | grep -q ":$port "; then
        echo "  - 端口 $port: 转发监听中"
    else
        echo "  - 端口 $port: 未监听"
    fi
done

echo "=== 部署完成 ==="
