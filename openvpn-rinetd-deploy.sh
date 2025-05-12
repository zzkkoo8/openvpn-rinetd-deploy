#!/bin/bash
# 一键部署 OpenVPN (TCP 31500) + rinetd 端口转发 (Ubuntu 24)
# 功能：
#  1. 永久关闭防火墙 (ufw/nftables)，开启 IPv4/IPv6 转发
#  2. 安装依赖：curl, wget, expect, iproute2, openvpn, rinetd
#  3. 自动无人值守安装 OpenVPN（协议 TCP，端口 31500）
#  4. 配置并重启 rinetd，添加 Pi-Node 端口转发规则
#  5. 部署完成后自检服务状态和端口监听

set -e
trap 'echo "错误：脚本在第${LINENO}行执行失败。"; exit 1' ERR

# 确保以 root 运行
if [[ $EUID -ne 0 ]]; then
    echo "请以 root 身份运行此脚本。" >&2
    exit 1
fi

echo "=== 开始部署 OpenVPN + rinetd (Ubuntu 24) ==="

########################################
# 1. 关闭防火墙，开启内核转发
########################################
echo ">>> 关闭 ufw（如已安装）"
if command -v ufw &>/dev/null; then
    ufw disable
    systemctl disable ufw &>/dev/null || true
fi

echo ">>> 关闭 nftables（如已安装）"
systemctl disable --now nftables &>/dev/null || true

echo ">>> 清空 iptables 和 ip6tables 规则，设为 ACCEPT"
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
ip6tables -F && ip6tables -t nat -F && ip6tables -t mangle -F && ip6tables -X
ip6tables -P INPUT ACCEPT && ip6tables -P FORWARD ACCEPT && ip6tables -P OUTPUT ACCEPT

echo ">>> 永久开启 IPv4/IPv6 转发"
for key in net.ipv4.ip_forward net.ipv6.conf.all.forwarding net.ipv6.conf.default.forwarding; do
    grep -q "^$key=1" /etc/sysctl.conf || echo "$key=1" >> /etc/sysctl.conf
done
sysctl -p

########################################
# 2. 安装依赖
########################################
echo ">>> 更新软件包列表"
apt-get update -y

echo ">>> 安装依赖包：curl, wget, expect, iproute2, openvpn, rinetd"
apt-get install -y curl wget expect iproute2 openvpn rinetd

########################################
# 3. 自动化安装 OpenVPN (TCP 31500)
########################################
echo ">>> 下载 OpenVPN 一键安装脚本"
wget -qO /root/openvpn-install.sh https://git.io/vpn
chmod +x /root/openvpn-install.sh

echo ">>> 生成 Expect 脚本以自动完成交互"
cat > /root/openvpn-install.exp << 'EOF'
#!/usr/bin/expect -f
set timeout -1
spawn bash /root/openvpn-install.sh

# 自动回答所有提示：
# - 默认值直接回车（包括公网 IP/主机名）
# - 协议选择: 2 (TCP)
# - 自定义端口: 31500
expect {
    -re "(Public IPv4 address|IP address).*:"    { send "\r"; exp_continue }
    "IPv6 support"                              { send "\r"; exp_continue }
    "Port choice"                               { send "2\r"; exp_continue }
    "Custom port"                               { send "31500\r"; exp_continue }
    "Protocol"                                  { send "2\r"; exp_continue }
    -re "DNS \\[[0-9]+\\]:"                     { send "\r"; exp_continue }
    "Compression"                               { send "\r"; exp_continue }
    "Encryption settings"                       { send "\r"; exp_continue }
    "Client name"                               { send "\r"; exp_continue }
    "Press any key"                             { send "\r" }
}
expect eof
EOF
chmod +x /root/openvpn-install.exp

echo ">>> 运行 Expect 脚本，开始 OpenVPN 安装"
bash /root/openvpn-install.exp

########################################
# 4. 安装 & 配置 rinetd
########################################
echo ">>> 确保 rinetd 已安装"
# (已在依赖步骤安装)

echo ">>> 追加 Pi-Node 端口转发规则到 /etc/rinetd.conf"
cat >> /etc/rinetd.conf << 'EOF'
# Pi-Node 节点端口转发
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
0.0.0.0   825 10.8.0.2 825
EOF

echo ">>> 重启 rinetd 服务"
systemctl restart rinetd

########################################
# 5. 自检部署结果
########################################
echo
echo "=== 部署结果自检 ==="

# OpenVPN 服务状态
if systemctl is-active openvpn-server@server.service &>/dev/null || pgrep -x openvpn &>/dev/null; then
    echo "✔ OpenVPN 服务：运行中"
else
    echo "✖ OpenVPN 服务：未运行"
fi

# OpenVPN 监听端口
if ss -tuln | grep -q ':31500'; then
    echo "✔ OpenVPN 端口 31500：已监听"
else
    echo "✖ OpenVPN 端口 31500：未监听"
fi

# 客户端配置文件存在检查
if [[ -f /root/client.ovpn ]]; then
    echo "✔ 客户端文件 /root/client.ovpn：已生成"
else
    echo "✖ 客户端文件 /root/client.ovpn：未找到"
fi

# rinetd 服务状态
if systemctl is-active rinetd &>/dev/null; then
    echo "✔ rinetd 服务：运行中"
else
    echo "✖ rinetd 服务：未运行"
fi

# rinetd 端口监听检查
for port in 31400 31401 31402 31403 31404 31405 31406 31407 31408 31409 825; do
    if ss -tuln | grep -q ":$port "; then
        echo "✔ rinetd 端口 $port：监听中"
    else
        echo "✖ rinetd 端口 $port：未监听"
    fi
done

echo 
echo "=== 全部部署完成 ==="
