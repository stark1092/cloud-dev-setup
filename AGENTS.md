# AGENTS.md

This repository is intended to be executable by an AI coding agent after cloning onto a fresh server.

This is the **canonical agent operations document** for both OpenCode and Claude Code.
If `AGENTS.md` and `CLAUDE.md` ever differ, follow `AGENTS.md`.

## How agents should start

Use this file as the primary entry document regardless of which agent frontend you use.

Recommended interaction model:

1. Ask the human which role this machine should take: `gcp`, `vps-vless`, `pve-tailscale`, `pve-xray`, or `pve-tproxy`
2. Read the matching docs before making changes
3. Use `setup.sh` only as a convenience dispatcher after the role is already clear

So `setup.sh` is **optional helper tooling**, not the only valid entrypoint.

`CLAUDE.md` should remain a thin compatibility shim that points back here, rather than a second full instruction set.

## Optional command dispatcher

```bash
bash setup.sh gcp
bash setup.sh vps-vless
TAILSCALE_HOSTNAME='pve-homelab' bash setup.sh pve-tailscale
VLESS_LINK='vless://...' bash setup.sh pve-xray
bash setup.sh pve-tproxy
```

## Role mapping

| Role | Command | Purpose |
|------|---------|---------|
| GCP workstation | `bash setup.sh gcp` | Ubuntu developer workstation bootstrap |
| VPS VLESS server | `bash setup.sh vps-vless` | Install xray Reality server and print share link |
| PVE Tailscale | `TAILSCALE_HOSTNAME='pve-homelab' bash setup.sh pve-tailscale` | Install Tailscale on PVE and advertise the LXC subnet |
| PVE xray client | `VLESS_LINK='vless://...' bash setup.sh pve-xray` | Generate `/etc/xray/config.json` from a share link |
| PVE tproxy | `bash setup.sh pve-tproxy` | Upgrade PVE host into transparent proxy mode |

Direct script usage is also valid when the role is already explicit.

## Important inputs

For `bash setup.sh vps-vless`, these environment variables are optional overrides:

- `SERVER_ADDRESS`
- `VLESS_PORT`
- `REALITY_DEST`
- `REALITY_SERVER_NAME`
- `CLIENT_FINGERPRINT`
- `NODE_REMARK`
- `VLESS_UUID`
- `VLESS_SHORT_ID`
- `REALITY_PRIVATE_KEY`
- `REALITY_PUBLIC_KEY`
- `XRAY_LOCAL_BINARY`
- `ENABLE_BBR=0`
- `FORCE_REGENERATE=1`

For `bash setup.sh pve-xray`, provide:

- `VLESS_LINK='vless://...'`

For `bash setup.sh pve-tailscale`, these environment variables are optional overrides:

- `TAILSCALE_HOSTNAME`
- `TAILSCALE_AUTH_KEY`
- `TAILSCALE_ADVERTISE_ROUTES`
- `TAILSCALE_ACCEPT_DNS=false`
- `TAILSCALE_ENABLE_SSH=1`
- `TAILSCALE_LOGIN_SERVER`

## Operational boundaries

- Never commit real UUIDs, private keys, public keys, short IDs, or share links.
- Never commit real Tailscale auth keys.
- Treat `/root/.vps-env/` and `/etc/xray/` as sensitive local state.
- Treat `/var/lib/tailscale/` as sensitive local state.
- `pve_tproxy_setup.sh` changes routing, iptables, and `/etc/resolv.conf`; only run it on the intended PVE host.
- Prefer environment variables or local files over hardcoding secrets in repository files.

## Human reference docs

- `README.md`: top-level usage
- `VPS-VLESS.md`: server-side explanation and troubleshooting
- `PVE-TAILSCALE.md`: PVE-side Tailscale onboarding guide
- `PVE-VLESS.md`: PVE-side consumption guide
- `PVE.md`: home lab network context
