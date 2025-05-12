#!/usr/bin/env bash

# Abort on any error (if any command fails).
set -e

# Update package list and install prerequisites
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget expect iproute2 openvpn rinetd

# Disable and remove firewall services (ufw, nftables)
echo "Disabling ufw and nftables (if installed)" # 关闭系统防火墙 (ufw, nftables)
if command -v ufw >/dev/null; then
    systemctl disable --now ufw
    apt-get remove --purge -y ufw
fi
if command -v nft >/dev/null || systemctl is-active --quiet nftables; then
    systemctl disable --now nftables || true
    apt-get remove --purge -y nftables
fi

# Enable IPv4 and IPv6 forwarding in sysctl
echo "Enabling IP forwarding" # 开启 IPv4 和 IPv6 转发
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
grep -qxF 'net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

# Download and install OpenVPN using Angristan's script with expect automation
cd /root
if [ ! -f /root/client.ovpn ]; then
    echo "Running OpenVPN install script..." # 自动安装 OpenVPN
    curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
    chmod +x openvpn-install.sh
    expect <<EOF
set timeout -1
spawn bash openvpn-install.sh
expect "Public IPv4 address / hostname" { send "\r" }
expect "Protocol [1]:" { send "2\r" }
expect "Port [1194]:" { send "31500\r" }
expect "DNS server [1]:" { send "\r" }
expect "IPv6 address [1]:" { send "\r" }
expect "Client name:" { send "\r" }
expect eof
EOF
else
    echo "OpenVPN appears to be already installed, skipping installation."
fi

# Install and configure rinetd
echo "Configuring rinetd port forwarding" # 配置 rinetd 端口转发
if ! grep -q "10.8.0.2 31400" /etc/rinetd.conf; then
    cat >> /etc/rinetd.conf <<EOL
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
EOL
fi
systemctl restart rinetd

# Self-check
echo "Performing self-checks..." # 自检: 检查服务和端口
if ss -tunlp | grep -q ":31500 "; then
    echo "[OK] OpenVPN is listening on port 31500"
else
    echo "[ERROR] OpenVPN is not listening on port 31500"
fi
if [ -f /root/client.ovpn ]; then
    echo "[OK] /root/client.ovpn exists"
else
    echo "[ERROR] /root/client.ovpn does not exist"
fi
if systemctl is-active --quiet rinetd; then
    echo "[OK] rinetd is running"
else
    echo "[ERROR] rinetd is not running"
fi
for port in {31400..31409} 825; do
    if ss -tunlp | grep -q ":$port "; then
        echo "[OK] rinetd port $port is listening"
    else
        echo "[ERROR] rinetd port $port is not listening"
    fi
done
