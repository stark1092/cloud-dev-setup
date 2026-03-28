#!/bin/bash
# ============================================
# PVE xray 透明代理配置脚本
# 模式: 全流量代理 + 白名单直连
# DNS: 全部通过代理解析（防泄漏）
# 用法: bash pve_tproxy_setup.sh
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── 1. 创建 xray 专用用户（用于防止流量回环）──────────────────────────────

if ! id xray &>/dev/null; then
    useradd -r -s /sbin/nologin xray
    echo -e "${GREEN}创建 xray 用户${NC}"
fi

# ── 2. 为 xray 配置添加 tproxy 入站 ──────────────────────────────────────

python3 - <<'PYEOF'
import json, sys

path = '/etc/xray/config.json'
with open(path) as f:
    cfg = json.load(f)

# 检查是否已有 tproxy 入站
ports = [i.get('port') for i in cfg.get('inbounds', [])]
if 12345 in ports:
    print("tproxy 入站已存在，跳过")
else:
    cfg['inbounds'].append({
        "port": 12345,
        "protocol": "dokodemo-door",
        "settings": {
            "network": "tcp,udp",
            "followRedirect": True
        },
        "sniffing": {
            "enabled": True,
            "destOverride": ["http", "tls"]
        },
        "streamSettings": {
            "sockopt": { "tproxy": "tproxy" }
        }
    })
    print("已添加 tproxy 入站（端口 12345）")

# 添加 DNS 配置（查询通过代理，防泄漏）
cfg['dns'] = {
    "servers": ["8.8.8.8", "1.1.1.1"],
    "queryStrategy": "UseIP"
}

# 确保有 direct 出站
if not any(o.get('protocol') == 'freedom' for o in cfg.get('outbounds', [])):
    cfg['outbounds'].append({"protocol": "freedom", "tag": "direct"})

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
print("配置文件更新完成")
PYEOF

# ── 3. 写 iptables 规则脚本 ───────────────────────────────────────────────

cat > /etc/xray/iptables.sh <<'EOF'
#!/bin/bash
# ============================================
# xray 透明代理 iptables 规则
# 修改白名单：编辑 WHITELIST_IPS 数组
# ============================================

# ---- 白名单 IP（直连，不走代理）----
WHITELIST_IPS=(
    # Tailscale 网段（自动包含，无需手动添加）
    # 国内 VPS 示例（取消注释并填写）：
    # "x.x.x.x"
    # "y.y.y.y"
)

# 加载 tproxy 内核模块
modprobe xt_TPROXY
modprobe xt_owner

# 策略路由：mark=1 的包走 lo 表
ip rule add fwmark 1 table 100 2>/dev/null || true
ip route add local default dev lo table 100 2>/dev/null || true

# ── PREROUTING（覆盖 LXC 容器和转发流量）──

iptables -t mangle -N XRAY 2>/dev/null || iptables -t mangle -F XRAY

# 内置白名单
iptables -t mangle -A XRAY -d 127.0.0.0/8     -j RETURN
iptables -t mangle -A XRAY -d 224.0.0.0/4     -j RETURN
iptables -t mangle -A XRAY -d 240.0.0.0/4     -j RETURN
iptables -t mangle -A XRAY -d 169.254.0.0/16  -j RETURN
iptables -t mangle -A XRAY -d 10.0.0.0/8      -j RETURN
iptables -t mangle -A XRAY -d 172.16.0.0/12   -j RETURN
iptables -t mangle -A XRAY -d 192.168.0.0/16  -j RETURN
iptables -t mangle -A XRAY -d 100.64.0.0/10   -j RETURN  # Tailscale

# 用户自定义白名单
for ip in "${WHITELIST_IPS[@]}"; do
    iptables -t mangle -A XRAY -d "$ip" -j RETURN
done

# 其余流量 → tproxy
iptables -t mangle -A XRAY -p tcp -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A XRAY -p udp -j TPROXY --on-port 12345 --tproxy-mark 1

iptables -t mangle -C PREROUTING -j XRAY 2>/dev/null || \
    iptables -t mangle -A PREROUTING -j XRAY

# ── OUTPUT（覆盖 PVE 宿主机自身流量）──

iptables -t mangle -N XRAY_SELF 2>/dev/null || iptables -t mangle -F XRAY_SELF

# 内置白名单
iptables -t mangle -A XRAY_SELF -d 127.0.0.0/8     -j RETURN
iptables -t mangle -A XRAY_SELF -d 224.0.0.0/4     -j RETURN
iptables -t mangle -A XRAY_SELF -d 240.0.0.0/4     -j RETURN
iptables -t mangle -A XRAY_SELF -d 169.254.0.0/16  -j RETURN
iptables -t mangle -A XRAY_SELF -d 10.0.0.0/8      -j RETURN
iptables -t mangle -A XRAY_SELF -d 172.16.0.0/12   -j RETURN
iptables -t mangle -A XRAY_SELF -d 192.168.0.0/16  -j RETURN
iptables -t mangle -A XRAY_SELF -d 100.64.0.0/10   -j RETURN  # Tailscale

# 用户自定义白名单
for ip in "${WHITELIST_IPS[@]}"; do
    iptables -t mangle -A XRAY_SELF -d "$ip" -j RETURN
done

# 关键：排除 xray 自身流量（防回环）
iptables -t mangle -A XRAY_SELF -m owner --gid-owner xray -j RETURN

# 其余流量打 mark
iptables -t mangle -A XRAY_SELF -p tcp -j MARK --set-mark 1
iptables -t mangle -A XRAY_SELF -p udp -j MARK --set-mark 1

iptables -t mangle -C OUTPUT -j XRAY_SELF 2>/dev/null || \
    iptables -t mangle -A OUTPUT -j XRAY_SELF

echo "iptables 规则已加载"
EOF

cat > /etc/xray/iptables-clean.sh <<'EOF'
#!/bin/bash
# 清除 xray 透明代理规则

ip rule del fwmark 1 table 100 2>/dev/null || true
ip route del local default dev lo table 100 2>/dev/null || true

iptables -t mangle -D PREROUTING -j XRAY    2>/dev/null || true
iptables -t mangle -D OUTPUT     -j XRAY_SELF 2>/dev/null || true
iptables -t mangle -F XRAY       2>/dev/null || true
iptables -t mangle -X XRAY       2>/dev/null || true
iptables -t mangle -F XRAY_SELF  2>/dev/null || true
iptables -t mangle -X XRAY_SELF  2>/dev/null || true

echo "iptables 规则已清除"
EOF

chmod +x /etc/xray/iptables.sh /etc/xray/iptables-clean.sh

# ── 4. iptables 规则持久化（systemd 服务）────────────────────────────────

cat > /etc/systemd/system/xray-iptables.service <<'EOF'
[Unit]
Description=xray iptables transparent proxy rules
Before=xray.service

[Service]
Type=oneshot
ExecStart=/etc/xray/iptables.sh
ExecStop=/etc/xray/iptables-clean.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# ── 5. 更新 xray systemd 服务（以 xray 用户运行）────────────────────────

cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
After=network.target
Requires=xray-iptables.service
After=xray-iptables.service

[Service]
User=xray
Group=xray
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ── 6. 配置系统 DNS 走代理解析 ────────────────────────────────────────────

# 写入固定 DNS（iptables 会将其拦截并通过代理解析）
cat > /etc/resolv.conf <<'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# 防止 DHCP 覆盖 resolv.conf
chattr +i /etc/resolv.conf

# ── 7. 启动 ──────────────────────────────────────────────────────────────

systemctl daemon-reload
systemctl enable xray-iptables xray
systemctl restart xray-iptables xray

sleep 2

echo ""
echo -e "${BLUE}验证中...${NC}"
if curl -fsSL --max-time 10 https://ifconfig.me -o /tmp/myip.txt 2>/dev/null; then
    echo -e "${GREEN}透明代理正常，出口 IP: $(cat /tmp/myip.txt)${NC}"
else
    echo -e "${YELLOW}验证失败，检查日志: journalctl -u xray -f${NC}"
fi

echo ""
echo -e "${BLUE}白名单管理: 编辑 /etc/xray/iptables.sh 中的 WHITELIST_IPS 数组${NC}"
echo -e "${BLUE}修改后执行: systemctl restart xray-iptables${NC}"
