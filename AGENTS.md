# AGENTS.md

This repository is intended to be executable by an AI coding agent after cloning onto a fresh server.

## Preferred entrypoint

Use `setup.sh` first.

```bash
bash setup.sh gcp
bash setup.sh vps-vless
VLESS_LINK='vless://...' bash setup.sh pve-xray
bash setup.sh pve-tproxy
```

## Role mapping

| Role | Command | Purpose |
|------|---------|---------|
| GCP workstation | `bash setup.sh gcp` | Ubuntu developer workstation bootstrap |
| VPS VLESS server | `bash setup.sh vps-vless` | Install xray Reality server and print share link |
| PVE xray client | `VLESS_LINK='vless://...' bash setup.sh pve-xray` | Generate `/etc/xray/config.json` from a share link |
| PVE tproxy | `bash setup.sh pve-tproxy` | Upgrade PVE host into transparent proxy mode |

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

## Operational boundaries

- Never commit real UUIDs, private keys, public keys, short IDs, or share links.
- Treat `/root/.vps-env/` and `/etc/xray/` as sensitive local state.
- `pve_tproxy_setup.sh` changes routing, iptables, and `/etc/resolv.conf`; only run it on the intended PVE host.
- Prefer environment variables or local files over hardcoding secrets in repository files.

## Human reference docs

- `README.md`: top-level usage
- `VPS-VLESS.md`: server-side explanation and troubleshooting
- `PVE-VLESS.md`: PVE-side consumption guide
- `PVE.md`: home lab network context
