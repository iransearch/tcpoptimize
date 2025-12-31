diff --git a/proxy.sh b/proxy.sh
index 0000000..1111111 100755
--- a/proxy.sh
+++ b/proxy.sh
@@ -1,78 +1,144 @@
 #!/bin/bash
 
-echo "Starting system optimization for high-load TCP/UDP proxy server..."
+set -euo pipefail
+
+echo "Starting system optimization for high-load TCP/UDP proxy server..."
+
+require_root() {
+  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
+    echo "❌ Please run as root (sudo)."
+    exit 1
+  fi
+}
+
+backup_file() {
+  local f="$1"
+  local backup_dir="/var/backups/tcpoptimize"
+  mkdir -p "$backup_dir"
+  if [[ -f "$f" ]]; then
+    local ts
+    ts="$(date +%Y%m%d_%H%M%S)"
+    cp -a "$f" "$backup_dir/$(basename "$f").$ts.bak"
+    echo "🗄️  Backup: $f -> $backup_dir/$(basename "$f").$ts.bak"
+  fi
+}
+
+ensure_line_in_file() {
+  local line="$1"
+  local file="$2"
+  touch "$file"
+  grep -qxF "$line" "$file" || echo "$line" >> "$file"
+}
+
+require_root
 
-# Enable IP forwarding
-echo 1 > /proc/sys/net/ipv4/ip_forward
-grep -qxF 'echo 1 > /proc/sys/net/ipv4/ip_forward' /etc/rc.local || echo 'echo 1 > /proc/sys/net/ipv4/ip_forward' >> /etc/rc.local
-chmod +x /etc/rc.local
+# Backups (before any edits)
+backup_file /etc/sysctl.conf
+backup_file /etc/rc.local
+backup_file /etc/security/limits.conf
+backup_file /etc/modules-load.d/modules.conf
+
+# Enable IP forwarding (immediate + persistent via sysctl.d below)
+echo 1 > /proc/sys/net/ipv4/ip_forward
 
 # Set file limits
-cat <<EOF >> /etc/security/limits.conf
-* soft nofile 1048576
-* hard nofile 1048576
-* soft nproc 65535
-* hard nproc 65535
-EOF
+if [[ -d /etc/security/limits.d ]]; then
+  LIMITS_FILE="/etc/security/limits.d/99-tcpoptimize.conf"
+  if [[ ! -f "$LIMITS_FILE" ]]; then
+    cat <<'EOF' > "$LIMITS_FILE"
+# tcpoptimize (idempotent)
+* soft nofile 1048576
+* hard nofile 1048576
+* soft nproc 65535
+* hard nproc 65535
+EOF
+    echo "✅ Written $LIMITS_FILE"
+  else
+    echo "ℹ️  $LIMITS_FILE already exists (skip)"
+  fi
+else
+  # Fallback: add once to limits.conf with markers
+  MARK_BEGIN="# tcpoptimize BEGIN"
+  MARK_END="# tcpoptimize END"
+  if ! grep -qF "$MARK_BEGIN" /etc/security/limits.conf 2>/dev/null; then
+    cat <<EOF >> /etc/security/limits.conf
+$MARK_BEGIN
+* soft nofile 1048576
+* hard nofile 1048576
+* soft nproc 65535
+* hard nproc 65535
+$MARK_END
+EOF
+    echo "✅ Appended limits to /etc/security/limits.conf (once)"
+  else
+    echo "ℹ️  limits markers already present in /etc/security/limits.conf (skip)"
+  fi
+fi
 
-# Overwrite sysctl.conf completely with optimized values
-echo "Overwriting /etc/sysctl.conf..."
-cat <<EOF > /etc/sysctl.conf
+# Write sysctl via sysctl.d (idempotent, no overwrite of sysctl.conf)
+SYSCTL_FILE="/etc/sysctl.d/99-tcpoptimize.conf"
+if [[ ! -f "$SYSCTL_FILE" ]]; then
+  echo "Writing $SYSCTL_FILE ..."
+else
+  echo "Updating $SYSCTL_FILE ..."
+fi
+
+cat <<'EOF' > "$SYSCTL_FILE"
 # Memory
 fs.file-max = 2097152
 vm.min_free_kbytes = 65536
 vm.swappiness = 10
 vm.vfs_cache_pressure = 50
 
+# Forwarding (persistent)
+net.ipv4.ip_forward = 1
+
+# Low-latency queue (helps jitter)
+net.core.default_qdisc = fq
+
 # TCP/UDP buffer optimization
 net.core.rmem_max = 268435456
 net.core.wmem_max = 268435456
-net.core.rmem_default = 134217728
-net.core.wmem_default = 134217728
+net.core.rmem_default = 262144
+net.core.wmem_default = 262144
 
 # UDP memory settings
-net.ipv4.udp_rmem_min = 8192
-net.ipv4.udp_wmem_min = 8192
+net.ipv4.udp_rmem_min = 16384
+net.ipv4.udp_wmem_min = 16384
 net.ipv4.udp_mem = 262144 327680 393216
 
 # Backlog / queue
-net.core.netdev_max_backlog = 500000
+net.core.netdev_max_backlog = 250000
 net.core.somaxconn = 65535
 
 # TCP performance
 net.ipv4.tcp_syncookies = 1
 net.ipv4.tcp_tw_reuse = 1
 net.ipv4.tcp_fin_timeout = 15
 net.ipv4.tcp_keepalive_time = 600
 net.ipv4.tcp_max_syn_backlog = 65535
 net.ipv4.tcp_max_tw_buckets = 2000000
 net.ipv4.tcp_fastopen = 3
 net.ipv4.tcp_mtu_probing = 1
 net.ipv4.tcp_congestion_control = bbr
 net.ipv4.tcp_rmem = 4096 87380 268435456
 net.ipv4.tcp_wmem = 4096 65536 268435456
 
 # Port range
 net.ipv4.ip_local_port_range = 10000 65535
 
 # Redirect protections
 net.ipv4.conf.all.accept_redirects = 0
 net.ipv4.conf.all.send_redirects = 0
 net.ipv4.conf.default.accept_redirects = 0
 net.ipv4.conf.default.send_redirects = 0
-EOF
+EOF
 
-# Apply sysctl settings
-sysctl -p
+# Apply sysctl settings (all sysctl.d + sysctl.conf)
+sysctl --system
 
 # Load BBR
 modprobe tcp_bbr
-echo "tcp_bbr" | tee -a /etc/modules-load.d/modules.conf
-sysctl -w net.ipv4.tcp_congestion_control=bbr
-# Enable IP forwarding
-echo "1" > /proc/sys/net/ipv4/ip_forward
-grep -q "net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
+mkdir -p /etc/modules-load.d
+ensure_line_in_file "tcp_bbr" /etc/modules-load.d/modules.conf
+sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null || true
 
 # Create backup script
 cat > /usr/local/bin/backup_v2bx_config.sh << 'EOF'
 #!/bin/bash
 backup_dir="/etc/V2bX/backups"
 mkdir -p "$backup_dir"
 timestamp=$(date +"%Y%m%d_%H%M")
 cp /etc/V2bX/config.json "$backup_dir/config-$timestamp.bak"
 find "$backup_dir" -name "config-*.bak" -type f -mtime +10 -exec rm -f {} \;
 EOF
 
 chmod +x /usr/local/bin/backup_v2bx_config.sh
@@ -104,4 +170,4 @@ echo "✅ Optimization and backup setup complete."
 
 echo ""
-echo "✅ All settings have been fully replaced and applied. A reboot is recommended."
+echo "✅ Settings applied via sysctl.d (idempotent). A reboot is recommended."
