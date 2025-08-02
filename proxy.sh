#!/bin/bash

echo "Starting system optimization for high-load UDP proxy server..."

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
grep -qxF 'echo 1 > /proc/sys/net/ipv4/ip_forward' /etc/rc.local || echo 'echo 1 > /proc/sys/net/ipv4/ip_forward' >> /etc/rc.local
chmod +x /etc/rc.local

# Set file limits
cat <<EOF >> /etc/security/limits.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
EOF

# Clean old sysctl network tuning values
echo "Cleaning old network settings from /etc/sysctl.conf..."
sed -i '/^net\./d' /etc/sysctl.conf
sed -i '/^fs\.file-max/d' /etc/sysctl.conf

# Add new sysctl values
cat <<EOF >> /etc/sysctl.conf
fs.file-max = 2097152

net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 67108864
net.core.wmem_default = 67108864
net.core.netdev_max_backlog = 500000
net.core.somaxconn = 65535

net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_local_port_range = 10000 65535

net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF

# Apply new sysctl settings
sysctl -p

# Load BBR
modprobe tcp_bbr
echo "tcp_bbr" | tee -a /etc/modules-load.d/modules.conf
sysctl -w net.ipv4.tcp_congestion_control=bbr

# Set cron job for v2bx restart every 3 hours
(crontab -l 2>/dev/null; echo "0 */3 * * * /usr/bin/v2bx restart") | crontab -

echo ""
echo "✅ Optimization complete. Reboot recommended."
