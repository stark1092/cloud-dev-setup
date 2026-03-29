#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat <<'EOF'
Usage:
  bash pve_tailscale_setup.sh
  TAILSCALE_HOSTNAME='pve-homelab' bash pve_tailscale_setup.sh
  TAILSCALE_AUTH_KEY='tskey-auth-xxxxx' bash pve_tailscale_setup.sh

Optional env:
  TAILSCALE_HOSTNAME          Override Tailscale machine name
  TAILSCALE_AUTH_KEY          Non-interactive auth key
  TAILSCALE_ADVERTISE_ROUTES  Defaults to 10.10.10.0/24
  TAILSCALE_ACCEPT_DNS        Defaults to false
  TAILSCALE_ENABLE_SSH        Defaults to 0
  TAILSCALE_LOGIN_SERVER      Optional control server override
EOF
}

die() {
    echo -e "${RED}$1${NC}" >&2
    exit 1
}

normalize_bool() {
    local raw="${1:-}"
    case "${raw,,}" in
        1|true|yes|on)
            echo "true"
            ;;
        0|false|no|off|'')
            echo "false"
            ;;
        *)
            die "无法识别布尔值: ${raw}"
            ;;
    esac
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ ${EUID} -ne 0 ]]; then
    die "请以 root 运行此脚本"
fi

TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
TAILSCALE_ADVERTISE_ROUTES="${TAILSCALE_ADVERTISE_ROUTES:-10.10.10.0/24}"
TAILSCALE_ACCEPT_DNS="$(normalize_bool "${TAILSCALE_ACCEPT_DNS:-false}")"
TAILSCALE_ENABLE_SSH="$(normalize_bool "${TAILSCALE_ENABLE_SSH:-0}")"
TAILSCALE_LOGIN_SERVER="${TAILSCALE_LOGIN_SERVER:-}"

echo -e "${BLUE}准备在 PVE 宿主机上安装 / 配置 Tailscale${NC}"
echo "  主机名: ${TAILSCALE_HOSTNAME:-<保持系统默认>}"
echo "  广播路由: ${TAILSCALE_ADVERTISE_ROUTES:-<none>}"
echo "  接收 DNS: ${TAILSCALE_ACCEPT_DNS}"
echo "  启用 Tailscale SSH: ${TAILSCALE_ENABLE_SSH}"
echo ""

echo -e "${BLUE}安装基础依赖...${NC}"
apt update
apt install -y curl ca-certificates

if command -v tailscale >/dev/null 2>&1; then
    echo -e "${GREEN}tailscale 已安装，跳过安装步骤${NC}"
else
    echo -e "${BLUE}安装 tailscale...${NC}"
    curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled

if [[ -n "${TAILSCALE_ADVERTISE_ROUTES}" ]]; then
    echo -e "${BLUE}开启 IP forwarding（subnet router 需要）...${NC}"
    cat > /etc/sysctl.d/99-tailscale.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
    sysctl -p /etc/sysctl.d/99-tailscale.conf
fi

up_args=("--accept-dns=${TAILSCALE_ACCEPT_DNS}")

if [[ -n "${TAILSCALE_HOSTNAME}" ]]; then
    up_args+=("--hostname=${TAILSCALE_HOSTNAME}")
fi

if [[ -n "${TAILSCALE_ADVERTISE_ROUTES}" ]]; then
    up_args+=("--advertise-routes=${TAILSCALE_ADVERTISE_ROUTES}")
fi

if [[ "${TAILSCALE_ENABLE_SSH}" == "true" ]]; then
    up_args+=("--ssh")
fi

if [[ -n "${TAILSCALE_LOGIN_SERVER}" ]]; then
    up_args+=("--login-server=${TAILSCALE_LOGIN_SERVER}")
fi

if [[ -n "${TAILSCALE_AUTH_KEY}" ]]; then
    up_args+=("--auth-key=${TAILSCALE_AUTH_KEY}")
fi

echo -e "${BLUE}执行 tailscale up...${NC}"
if ! tailscale up "${up_args[@]}"; then
    echo ""
    echo -e "${YELLOW}如果上面已经打印出登录链接，请先在浏览器完成登录，然后执行 tailscale status 检查状态。${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}tailscale up 执行完成${NC}"
echo -e "${BLUE}当前状态:${NC}"
tailscale status || true

echo ""
echo -e "${BLUE}后续检查建议:${NC}"
echo "  tailscale ip -4"
echo "  tailscale netcheck"
echo ""

if [[ -n "${TAILSCALE_ADVERTISE_ROUTES}" ]]; then
    echo -e "${YELLOW}别忘了在 Tailscale 管理台批准子网路由: ${TAILSCALE_ADVERTISE_ROUTES}${NC}"
    echo "  路径: Machines -> 当前设备 -> Edit route settings"
    echo ""
fi

if [[ "${TAILSCALE_ENABLE_SSH}" == "true" ]]; then
    echo -e "${YELLOW}已启用 Tailscale SSH。请确认 tailnet 的 SSH policy 允许你访问该主机。${NC}"
    echo ""
fi

echo -e "${GREEN}完成。你现在可以从本地设备测试访问 PVE 宿主机，并在批准子网路由后测试访问 10.10.10.0/24 下的 LXC。${NC}"
