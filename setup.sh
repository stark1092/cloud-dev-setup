#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROLE="${1:-}"
if [[ $# -gt 0 ]]; then
    shift
fi

usage() {
    cat <<'EOF'
Usage:
  bash setup.sh gcp
  bash setup.sh vps-vless
  bash setup.sh pve-tailscale
  bash setup.sh pve-xray
  bash setup.sh pve-tproxy

Examples:
  bash setup.sh vps-vless
  TAILSCALE_HOSTNAME='pve-homelab' bash setup.sh pve-tailscale
  VLESS_LINK='vless://...' bash setup.sh pve-xray
EOF
}

run_pve_xray() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        bash "$ROOT_DIR/pve_xray_setup.sh" --help
        return 0
    fi

    if [[ -n "${VLESS_LINK:-}" ]]; then
        printf '%s\n' "$VLESS_LINK" | bash "$ROOT_DIR/pve_xray_setup.sh"
    else
        bash "$ROOT_DIR/pve_xray_setup.sh"
    fi
}

case "$ROLE" in
    gcp)
        bash "$ROOT_DIR/gcp_provision.sh" "$@"
        ;;
    vps-vless|vps-vless-server)
        bash "$ROOT_DIR/vps_vless_setup.sh" "$@"
        ;;
    pve-tailscale)
        bash "$ROOT_DIR/pve_tailscale_setup.sh" "$@"
        ;;
    pve-xray)
        run_pve_xray "$@"
        ;;
    pve-tproxy)
        bash "$ROOT_DIR/pve_tproxy_setup.sh" "$@"
        ;;
    *)
        usage
        exit 1
        ;;
esac
