# CLAUDE.md

This file exists as a **Claude Code compatibility shim**.

## Start here

Read [`AGENTS.md`](./AGENTS.md) first.

`AGENTS.md` is the single source of truth for:

- role selection (`gcp`, `vps-vless`, `pve-xray`, `pve-tproxy`)
- command dispatch / script entrypoints
- sensitive-state boundaries
- links to the human-facing scenario docs

If `CLAUDE.md` and `AGENTS.md` ever disagree, follow `AGENTS.md`.

## Recommended Claude Code workflow

1. Ask the human which role this machine should take
2. Read the matching docs referenced from `AGENTS.md`
3. Use `setup.sh` only as an optional convenience wrapper after the role is already clear

## Why this file is thin

The repository intentionally keeps operational guidance in one canonical place to avoid drift between Claude Code and OpenCode.
