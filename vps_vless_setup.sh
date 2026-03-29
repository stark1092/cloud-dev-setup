#!/bin/bash

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage:
  bash vps_vless_setup.sh

Optional environment variables:
  SERVER_ADDRESS
  VLESS_PORT
  REALITY_DEST
  REALITY_SERVER_NAME
  CLIENT_FINGERPRINT
  NODE_REMARK
  VLESS_UUID
  VLESS_SHORT_ID
  REALITY_PRIVATE_KEY
  REALITY_PUBLIC_KEY
  XRAY_LOCAL_BINARY
  ENABLE_BBR=0
  FORCE_REGENERATE=1
EOF
    exit 0
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
die() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

STATE_DIR="/root/.vps-env"
STATE_FILE="$STATE_DIR/vps-vless.env"
SHARE_FILE="$STATE_DIR/vless-share-link.txt"
XRAY_CONFIG_PATH="/etc/xray/config.json"
XRAY_SERVICE_PATH="/etc/systemd/system/xray.service"

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "请以 root 身份运行此脚本"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_server_address() {
    if [[ -n "${SERVER_ADDRESS:-}" ]]; then
        printf '%s\n' "$SERVER_ADDRESS"
        return 0
    fi

    local detected=""
    if command_exists curl; then
        detected="$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || true)"
        if [[ -z "$detected" ]]; then
            detected="$(curl -4 -fsSL https://ifconfig.me 2>/dev/null || true)"
        fi
    fi

    if [[ -z "$detected" ]]; then
        detected="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi

    [[ -n "$detected" ]] || die "无法自动检测服务器地址，请通过 SERVER_ADDRESS 环境变量提供"
    printf '%s\n' "$detected"
}

ensure_state_dir() {
    install -d -m 700 "$STATE_DIR"
}

load_existing_state() {
    if [[ "${FORCE_REGENERATE:-0}" != "1" && -f "$STATE_FILE" ]]; then
        set -a
        source "$STATE_FILE"
        set +a
        info "已加载现有节点参数: $STATE_FILE"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        info "检测到系统: ${PRETTY_NAME:-${ID:-unknown}}"
    else
        warn "未找到 /etc/os-release，继续执行"
    fi
}

install_packages() {
    info "安装基础依赖"
    apt-get update -qq
    apt-get install -y -qq curl wget unzip jq openssl ca-certificates iproute2 procps
    success "基础依赖已安装"
}

enable_bbr_if_needed() {
    if [[ "${ENABLE_BBR:-1}" != "1" ]]; then
        info "跳过 BBR 配置"
        return 0
    fi

    local current
    current="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
    if [[ "$current" == "bbr" ]]; then
        info "BBR 已启用，跳过"
        return 0
    fi

    cat > /etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system >/dev/null
    success "已启用 BBR"
}

install_xray() {
    if command_exists xray; then
        info "检测到 xray，跳过安装"
        return 0
    fi

    info "安装 xray-core"

    if [[ -n "${XRAY_LOCAL_BINARY:-}" ]]; then
        [[ -f "$XRAY_LOCAL_BINARY" ]] || die "XRAY_LOCAL_BINARY 指向的文件不存在: $XRAY_LOCAL_BINARY"
        install -m 755 "$XRAY_LOCAL_BINARY" /usr/local/bin/xray
        command_exists xray || die "从本地二进制安装 xray 失败"
        success "已从本地二进制安装 xray-core"
        return 0
    fi

    local installer="/tmp/xray-install.sh"
    curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o "$installer"
    bash "$installer" install
    rm -f "$installer"
    command_exists xray || die "xray 安装后仍不可用"
    success "xray-core 安装完成"
}

generate_random_short_id() {
    if command_exists openssl; then
        openssl rand -hex 4
    else
        od -An -N4 -tx1 /dev/urandom | tr -d ' \n'
    fi
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

generate_keys() {
    if [[ -n "${REALITY_PRIVATE_KEY:-}" && -n "${REALITY_PUBLIC_KEY:-}" ]]; then
        info "使用环境变量提供的 Reality 密钥对"
        return 0
    fi

    if [[ -n "${REALITY_PRIVATE_KEY:-}" || -n "${REALITY_PUBLIC_KEY:-}" ]]; then
        die "REALITY_PRIVATE_KEY 与 REALITY_PUBLIC_KEY 必须同时提供"
    fi

    info "生成 Reality 密钥对"
    local key_output
    key_output="$(xray x25519)"
    REALITY_PRIVATE_KEY="$(printf '%s\n' "$key_output" | awk -F': ' '/Private key:/ {print $2}')"
    REALITY_PUBLIC_KEY="$(printf '%s\n' "$key_output" | awk -F': ' '/Public key:/ {print $2}')"
    [[ -n "$REALITY_PRIVATE_KEY" && -n "$REALITY_PUBLIC_KEY" ]] || die "生成 Reality 密钥对失败"
    success "Reality 密钥对生成完成"
}

initialize_values() {
    SERVER_ADDRESS="$(detect_server_address)"
    VLESS_PORT="${VLESS_PORT:-443}"
    REALITY_DEST="${REALITY_DEST:-www.microsoft.com:443}"
    REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-${REALITY_DEST%%:*}}"
    CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
    NODE_REMARK="${NODE_REMARK:-$(hostname -s)-vless-reality}"
    NODE_REMARK="${NODE_REMARK// /-}"
    VLESS_UUID="${VLESS_UUID:-$(generate_uuid)}"
    VLESS_SHORT_ID="${VLESS_SHORT_ID:-$(generate_random_short_id)}"

    generate_keys

    VLESS_SHARE_LINK="vless://${VLESS_UUID}@${SERVER_ADDRESS}:${VLESS_PORT}?security=reality&type=tcp&sni=${REALITY_SERVER_NAME}&fp=${CLIENT_FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&sid=${VLESS_SHORT_ID}&flow=xtls-rprx-vision#${NODE_REMARK}"
}

write_xray_config() {
    if [[ -f "$XRAY_CONFIG_PATH" ]]; then
        cp "$XRAY_CONFIG_PATH" "$XRAY_CONFIG_PATH.bak.$(date +%Y%m%d%H%M%S)"
    fi

    mkdir -p /etc/xray
    cat > "$XRAY_CONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${VLESS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${VLESS_UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}",
          "xver": 0,
          "serverNames": [
            "${REALITY_SERVER_NAME}"
          ],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [
            "${VLESS_SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
    success "已写入 $XRAY_CONFIG_PATH"
}

write_systemd_service() {
    cat > "$XRAY_SERVICE_PATH" <<'EOF'
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
    systemctl enable xray >/dev/null
    systemctl restart xray
    success "xray 服务已启动"
}

configure_firewall_if_needed() {
    if ! command_exists ufw; then
        info "未检测到 ufw，跳过本地防火墙配置"
        return 0
    fi

    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        info "ufw 未启用，跳过本地防火墙配置"
        return 0
    fi

    ufw allow 22/tcp >/dev/null || true
    ufw allow "${VLESS_PORT}/tcp" >/dev/null || true
    success "已更新 ufw 规则"
}

write_state_files() {
    ensure_state_dir
    cat > "$STATE_FILE" <<EOF
SERVER_ADDRESS='${SERVER_ADDRESS}'
VLESS_PORT='${VLESS_PORT}'
REALITY_DEST='${REALITY_DEST}'
REALITY_SERVER_NAME='${REALITY_SERVER_NAME}'
CLIENT_FINGERPRINT='${CLIENT_FINGERPRINT}'
NODE_REMARK='${NODE_REMARK}'
VLESS_UUID='${VLESS_UUID}'
VLESS_SHORT_ID='${VLESS_SHORT_ID}'
REALITY_PRIVATE_KEY='${REALITY_PRIVATE_KEY}'
REALITY_PUBLIC_KEY='${REALITY_PUBLIC_KEY}'
VLESS_SHARE_LINK='${VLESS_SHARE_LINK}'
EOF
    chmod 600 "$STATE_FILE"

    printf '%s\n' "$VLESS_SHARE_LINK" > "$SHARE_FILE"
    chmod 600 "$SHARE_FILE"
    success "已写入节点参数: $STATE_FILE"
    success "已写入分享链接: $SHARE_FILE"
}

verify_setup() {
    systemctl is-active --quiet xray || {
        journalctl -u xray -n 50 >&2
        die "xray 服务未正常运行"
    }

    if ! ss -tuln | grep -q ":${VLESS_PORT} "; then
        warn "未在 ss 输出中检测到 :${VLESS_PORT} 监听，请手动复核"
    fi
}

print_summary() {
    printf '\n'
    success "VLESS Reality 服务端已就绪"
    printf '服务器地址: %s\n' "$SERVER_ADDRESS"
    printf '端口:       %s\n' "$VLESS_PORT"
    printf 'SNI:        %s\n' "$REALITY_SERVER_NAME"
    printf 'Dest:       %s\n' "$REALITY_DEST"
    printf 'UUID:       %s\n' "$VLESS_UUID"
    printf 'Short ID:   %s\n' "$VLESS_SHORT_ID"
    printf 'Public Key: %s\n' "$REALITY_PUBLIC_KEY"
    printf '\n分享链接:\n%s\n' "$VLESS_SHARE_LINK"
    printf '\n状态文件: %s\n' "$STATE_FILE"
    printf '分享链接文件: %s\n' "$SHARE_FILE"
    printf '\n下一步：\n'
    printf '1. 先用普通客户端导入上述分享链接做连通性验证\n'
    printf '2. 如需接入 PVE，再在 PVE 宿主机运行: bash setup.sh pve-xray\n'
}

main() {
    require_root
    detect_os
    ensure_state_dir
    load_existing_state
    install_packages
    enable_bbr_if_needed
    install_xray
    initialize_values
    write_xray_config
    write_systemd_service
    configure_firewall_if_needed
    write_state_files
    verify_setup
    print_summary
}

main "$@"
