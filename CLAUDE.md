# VPS-ENV

服务器和虚拟化环境配置脚本集合，涵盖 GCP 工作站、VPS 代理节点与 PVE 家庭实验室。

## 目录结构

```
VPS-ENV/
├── gcp_provision.sh      # GCP Ubuntu 工作站一键配置（tmux/zsh/docker/mise 等）
├── proxy_toggle.sh       # 代理切换工具（source 后使用 proxy on/off/status）
├── VPS-VLESS.md          # 新 VPS 部署 VLESS Reality 服务端指南
├── pve_xray_setup.sh     # PVE 宿主机：接入 VLESS Reality 节点，生成 xray 客户端配置
├── pve_tproxy_setup.sh   # PVE 宿主机：升级为透明代理（tproxy + DNS 防泄漏）
├── PVE.md                # PVE 家庭实验室完整配置记录
├── PVE-VLESS.md          # VLESS Reality 节点接入与排障指南
├── COMMANDS.md           # 常用命令速查
└── TOOLS.md              # 工具使用教程
```

## PVE 环境概览

- 硬件：AMD Ryzen 7 7840HS
- 系统：Proxmox VE 9.1.6（Debian Trixie）
- 代理：xray VLESS + Reality + XTLS Vision，透明代理模式
- LXC 网络：统一走 vmbr1（10.10.10.0/24 NAT 子网），经 PVE 路由层代理

## PVE 脚本执行顺序

1. `pve_xray_setup.sh` — 初始化 xray 和 VLESS Reality 客户端配置
   - ⚠️ xray 需在 Mac 上下载后 scp 到 PVE（GitHub 在大陆无法直连）
2. `pve_tproxy_setup.sh` — 升级为全流量透明代理

详细步骤见 `PVE.md`。

## 注意事项

- xray 配置文件位于 `/etc/xray/config.json`，含敏感信息，不提交到仓库
- iptables 白名单在 `/etc/xray/iptables.sh` 的 `WHITELIST_IPS` 数组中维护
- LXC 容器通过 SSH 跳板访问：`ssh -J root@<PVE_IP> root@10.10.10.x`
- 后续计划：接入 Tailscale，所有设备通过 100.64.x.x 直连
