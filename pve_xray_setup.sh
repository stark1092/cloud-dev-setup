#!/bin/bash
# ============================================
# PVE 宿主机 xray 安装脚本
# 协议: VLESS + TLS + TCP
# 本地代理端口: SOCKS5 :1080 / HTTP :1081
# 用法: bash pve_xray_setup.sh
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── 1. 读取 VLESS 链接 ──────────────────────────────────────────────────────

echo -e "${BLUE}请粘贴你的 VLESS 链接（输入后回车）:${NC}"
read -r VLESS_LINK

# 格式: vless://UUID@host:port?security=tls&type=tcp...#name
UUID=$(echo "$VLESS_LINK" | sed 's|vless://||' | cut -d'@' -f1)
HOSTPORT=$(echo "$VLESS_LINK" | sed 's|vless://||' | cut -d'@' -f2 | cut -d'?' -f1)
SERVER_HOST=$(echo "$HOSTPORT" | cut -d':' -f1)
SERVER_PORT=$(echo "$HOSTPORT" | cut -d':' -f2)

# SNI 优先从链接参数取，否则用 host
SNI=$(echo "$VLESS_LINK" | grep -oP 'sni=\K[^&\#]+' || true)
if [[ -z "$SNI" ]]; then
    SNI="$SERVER_HOST"
fi

echo -e "${GREEN}解析结果:${NC}"
echo "  服务器: $SERVER_HOST:$SERVER_PORT"
echo "  SNI:    $SNI"
echo "  UUID:   ${UUID:0:8}******"
echo ""

# ── 2. 安装 xray-core ───────────────────────────────────────────────────────
#
# ⚠️  注意：GitHub 在中国大陆无法直连，自动下载会失败。
#    请在 Mac 上手动下载后 scp 到 PVE：
#
#    Mac:
#      curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" \
#           -o /tmp/xray-linux-64.zip
#      scp /tmp/xray-linux-64.zip root@<PVE_IP>:/tmp/
#
#    PVE:
#      cd /tmp && unzip xray-linux-64.zip
#      install -m 755 xray /usr/local/bin/xray
#
#    确认安装后跳过本段，从「3. 生成配置文件」继续。
# ─────────────────────────────────────────────────────────────────────────────

if ! command -v xray &>/dev/null; then
    echo -e "${RED}未检测到 xray，请按脚本注释手动安装后重新运行${NC}"
    exit 1
fi

echo -e "${GREEN}xray $(xray version | head -1) 已就位${NC}"

# ── 3. 生成配置文件 ─────────────────────────────────────────────────────────

mkdir -p /etc/xray

cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 1080,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    },
    {
      "port": 1081,
      "listen": "0.0.0.0",
      "protocol": "http",
      "settings": {}
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_HOST",
            "port": $SERVER_PORT,
            "users": [
              {
                "id": "$UUID",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "$SNI"
        }
      }
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

echo -e "${GREEN}配置文件已写入 /etc/xray/config.json${NC}"

# ── 4. 注册 systemd 服务 ────────────────────────────────────────────────────

cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

sleep 2
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}xray 服务运行正常${NC}"
else
    echo -e "${RED}xray 服务启动失败，查看日志:${NC}"
    journalctl -u xray -n 20
    exit 1
fi

# ── 5. 配置 apt 全局代理 ────────────────────────────────────────────────────

cat > /etc/apt/apt.conf.d/99proxy <<'EOF'
Acquire::http::Proxy "http://127.0.0.1:1081";
Acquire::https::Proxy "http://127.0.0.1:1081";
EOF

echo -e "${GREEN}apt 代理已配置${NC}"

# ── 6. 验证 ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}验证代理连通性...${NC}"
if curl -fsSL --proxy http://127.0.0.1:1081 --max-time 10 https://www.google.com -o /dev/null; then
    echo -e "${GREEN}代理连通正常${NC}"
else
    echo -e "${YELLOW}连通性验证失败，请检查 VLESS 配置或服务器状态${NC}"
    echo "  查看日志: journalctl -u xray -f"
fi

# ── 7. 输出使用说明 ─────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}=============================${NC}"
echo -e "${GREEN}安装完成！${NC}"
echo ""
echo "代理端口:"
echo "  SOCKS5: 127.0.0.1:1080"
echo "  HTTP:   127.0.0.1:1081"
echo ""
echo "LXC 容器内使用（替换 <PVE_HOST_IP> 为宿主机 IP）:"
echo "  export http_proxy=http://<PVE_HOST_IP>:1081"
echo "  export https_proxy=http://<PVE_HOST_IP>:1081"
echo ""
echo "服务管理:"
echo "  systemctl status xray"
echo "  systemctl restart xray"
echo "  journalctl -u xray -f"
echo -e "${BLUE}=============================${NC}"
