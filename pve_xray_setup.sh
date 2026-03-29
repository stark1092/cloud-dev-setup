#!/bin/bash
# ============================================
# PVE 宿主机 xray 安装脚本
# 本地代理端口: SOCKS5 :1080 / HTTP :1081
# 用法: bash pve_xray_setup.sh
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage:
  bash pve_xray_setup.sh
  VLESS_LINK='vless://...' bash pve_xray_setup.sh

If VLESS_LINK is not provided, the script will prompt for it.
EOF
    exit 0
fi

die() {
    echo -e "${RED}$1${NC}"
    exit 1
}

if [[ -n "${VLESS_LINK:-}" ]]; then
    echo -e "${BLUE}检测到环境变量 VLESS_LINK，直接使用${NC}"
else
    echo -e "${BLUE}请粘贴你的 VLESS Reality 链接（输入后回车）:${NC}"
    read -r VLESS_LINK
fi

if ! command -v python3 &>/dev/null; then
    die "未检测到 python3，无法解析 VLESS 链接"
fi

mapfile -t PARSED_FIELDS < <(python3 - "$VLESS_LINK" <<'PYEOF'
import sys
from urllib.parse import parse_qs, unquote, urlsplit
from uuid import UUID

link = sys.argv[1].strip()
if not link:
    raise SystemExit("未提供 VLESS 链接")

parts = urlsplit(link)
if parts.scheme.lower() != "vless":
    raise SystemExit("链接必须以 vless:// 开头")

if not parts.username:
    raise SystemExit("VLESS 链接缺少 UUID")

uuid_value = unquote(parts.username)
try:
    UUID(uuid_value)
except ValueError as exc:
    raise SystemExit("UUID 格式无效") from exc

try:
    port = parts.port
except ValueError as exc:
    raise SystemExit("VLESS 链接端口无效") from exc

if not parts.hostname or port is None:
    raise SystemExit("VLESS 链接缺少服务器地址或端口")

query = parse_qs(parts.query, keep_blank_values=True)


def pick(*keys, default=""):
    for key in keys:
        values = query.get(key)
        if values:
            value = values[0]
            if value != "":
                return unquote(value)
    return default


security = pick("security").lower()
network = pick("type", "network", default="tcp").lower()
sni = pick("sni", "serverName")
public_key = pick("pbk", "publicKey")
short_id = pick("sid", "shortId")
fingerprint = pick("fp", "fingerprint", "client-fingerprint", default="chrome").lower()
flow = pick("flow", default="xtls-rprx-vision").lower()

if security != "reality":
    raise SystemExit(f"当前脚本仅支持 security=reality，实际为 {security or '空'}")

if network != "tcp":
    raise SystemExit(f"当前脚本仅支持 type=tcp，实际为 {network or '空'}")

if not sni:
    raise SystemExit("VLESS 链接缺少 sni/serverName")

if not public_key:
    raise SystemExit("VLESS 链接缺少 pbk/publicKey")

if flow != "xtls-rprx-vision":
    raise SystemExit(f"当前脚本仅支持 flow=xtls-rprx-vision，实际为 {flow or '空'}")

for field in (
    uuid_value,
    parts.hostname,
    str(port),
    sni,
    public_key,
    short_id,
    fingerprint,
    flow,
):
    print(field)
PYEOF
) || die "解析 VLESS Reality 链接失败，请检查链接是否完整"

if [[ ${#PARSED_FIELDS[@]} -ne 8 ]]; then
    die "解析结果字段数量异常，请检查分享链接格式"
fi

UUID="${PARSED_FIELDS[0]}"
SERVER_HOST="${PARSED_FIELDS[1]}"
SERVER_PORT="${PARSED_FIELDS[2]}"
SNI="${PARSED_FIELDS[3]}"
PUBLIC_KEY="${PARSED_FIELDS[4]}"
SHORT_ID="${PARSED_FIELDS[5]}"
FINGERPRINT="${PARSED_FIELDS[6]}"
FLOW="${PARSED_FIELDS[7]}"

if [[ -z "$SHORT_ID" ]]; then
    SHORT_ID_DISPLAY="(empty)"
else
    SHORT_ID_DISPLAY="$SHORT_ID"
fi

echo -e "${GREEN}解析结果:${NC}"
echo "  服务器: $SERVER_HOST:$SERVER_PORT"
echo "  SNI:    $SNI"
echo "  指纹:   $FINGERPRINT"
echo "  Flow:   $FLOW"
echo "  公钥:   ${PUBLIC_KEY:0:12}******"
echo "  ShortID:${SHORT_ID_DISPLAY}"
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
                "encryption": "none",
                "flow": "$FLOW"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "$FINGERPRINT",
          "serverName": "$SNI",
          "publicKey": "$PUBLIC_KEY",
          "shortId": "$SHORT_ID"
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
echo "监听端口:"
echo "  SOCKS5: 0.0.0.0:1080 (宿主机本地可用 127.0.0.1:1080)"
echo "  HTTP:   0.0.0.0:1081 (宿主机本地可用 127.0.0.1:1081)"
echo ""
echo "LXC 容器内使用（替换 <PVE_HOST_IP> 为宿主机 IP）:"
echo "  export http_proxy=http://<PVE_HOST_IP>:1081"
echo "  export https_proxy=http://<PVE_HOST_IP>:1081"
echo ""
echo "服务管理:"
echo "  systemctl status xray"
echo "  systemctl restart xray"
echo "  journalctl -u xray -f"
echo ""
echo "如果脚本拒绝你的分享链接，请参考 PVE-VLESS.md 检查 pbk/sni/flow 等字段"
echo -e "${BLUE}=============================${NC}"
